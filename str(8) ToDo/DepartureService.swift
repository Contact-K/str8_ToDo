//
//  DepartureService.swift
//  str8ToDo
//
//  MapKit の MKDirections で出発時刻を逆算。
//  時刻固定・座標あり・24h以内のタスクだけにルート要求を飛ばす。
//

import Foundation
import MapKit
import SwiftUI

// MARK: - 純関数ゲート

enum DepartureGate {
    /// ルート要求を飛ばすべきタスク条件の唯一の判定点。
    /// - 時刻厳守（isTimePinned = true）
    /// - 場所座標あり
    /// - 現在時刻 <= startDate <= 現在時刻 + 24h
    static func shouldRequestRoute(
        start: Date?,
        hasCoordinates: Bool,
        isTimePinned: Bool,
        now: Date
    ) -> Bool {
        guard let start = start, hasCoordinates, isTimePinned else { return false }
        let maxFuture = now.addingTimeInterval(24 * 3600)
        return now <= start && start <= maxFuture
    }
}

// MARK: - ETA キャッシュ

private struct CachedETA {
    let eta: TimeInterval
    let fetchedAt: Date
}

// MARK: - DepartureService（MapKit）

@MainActor
@Observable
final class DepartureService {
    private var etaCache: [UUID: CachedETA] = [:]
    private let cacheDuration: TimeInterval = 30 * 60  // 30 分有効

    /// 現在位置から PlaceTag 座標へのルート（移動時間）を取得。
    /// shouldRequestRoute で false なら呼ばないこと（UI側で事前チェック）。
    /// キャッシュ有効期間内は再要求しない。エラー時は nil。
    func eta(for task: TaskItem, now: Date) async -> TimeInterval? {
        // キャッシュ確認
        if let cached = etaCache[task.id] {
            if now.timeIntervalSince(cached.fetchedAt) < cacheDuration {
                return cached.eta
            } else {
                etaCache.removeValue(forKey: task.id)
            }
        }

        // ゲート判定（念のため）
        guard let startDate = task.startDate else { return nil }
        guard DepartureGate.shouldRequestRoute(
            start: startDate,
            hasCoordinates: task.place?.latitude != nil && task.place?.longitude != nil,
            isTimePinned: task.isTimePinned,
            now: now
        ) else { return nil }

        // AppSettings から現在位置を取得
        let (userLat, userLon) = getCurrentLocation()
        guard userLat != 0 || userLon != 0 else { return nil }

        // 目的地座標
        guard let destLat = task.place?.latitude, let destLon = task.place?.longitude else { return nil }

        // MKDirections リクエスト
        let sourcePlacemark = MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: userLat, longitude: userLon))
        let destinationPlacemark = MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: destLat, longitude: destLon))

        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: sourcePlacemark)
        request.destination = MKMapItem(placemark: destinationPlacemark)
        // ponytail: walking と .automobile の選択。既定は .automobile（手段が明示されなければ車）。
        request.transportType = .automobile
        request.requestsAlternateRoutes = false

        do {
            let directions = MKDirections(request: request)
            let response = try await directions.calculate()
            if let route = response.routes.first {
                let travelTime = route.expectedTravelTime
                etaCache[task.id] = CachedETA(eta: travelTime, fetchedAt: now)
                return travelTime
            }
        } catch {
            // 経路計算失敗→nil（移動行を出さないだけ）
            return nil
        }

        return nil
    }

    /// AppSettings から現在位置（緯度・経度）を取得。未取得なら (0, 0)。
    private func getCurrentLocation() -> (latitude: Double, longitude: Double) {
        let defaults = UserDefaults.standard
        let lat = defaults.double(forKey: AppSettingsKey.lastKnownLatitude)
        let lon = defaults.double(forKey: AppSettingsKey.lastKnownLongitude)
        return (lat, lon)
    }
}

// ponytail: MapKit 上流（位置情報取得）は別のサービス（LocationManager など）で担当。
// DepartureService は AppSettings に保存された座標を読むだけ。
