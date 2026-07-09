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

// MARK: - DepartureService（MapKit）

@MainActor
@Observable
final class DepartureService {
    /// 全ビュー共有インスタンス（ETA キャッシュを一元化）。
    static let shared = DepartureService()

    /// eta: nil = 直近の要求が失敗（TTL 内は再要求しない）。
    private var etaCache: [UUID: (eta: TimeInterval?, fetchedAt: Date)] = [:]

    /// 実行中要求（await 跨ぎの二重要求防止。日/週ビューの .task 同時発火対策）。
    private var inFlight: [UUID: Task<TimeInterval?, Never>] = [:]

    /// キャッシュ TTL: 出発まで1時間以内なら5分（鮮度優先）、それ以外は30分。
    static func cacheTTL(start: Date, now: Date) -> TimeInterval {
        start.timeIntervalSince(now) <= 3600 ? 5 * 60 : 30 * 60
    }

    /// 候補タスク群の ETA をまとめて取得。ゲート判定は eta(for:now:) に集約されているので
    /// 呼び出し側は候補タスクを渡すだけ。失敗（nil）は除外した辞書を返す。
    func etas(for tasks: [TaskItem], now: Date) async -> [UUID: TimeInterval] {
        var result: [UUID: TimeInterval] = [:]
        for task in tasks {
            if let eta = await eta(for: task, now: now) {
                result[task.id] = eta
            }
        }
        return result
    }

    /// 現在位置から PlaceTag 座標へのルート（移動時間）を取得。
    /// DepartureGate 判定はここが唯一の判定点（呼び出し側の事前チェック不要）。
    /// TTL 内は成功/失敗問わず再要求しない。エラー時は nil。
    func eta(for task: TaskItem, now: Date) async -> TimeInterval? {
        guard let startDate = task.startDate,
              DepartureGate.shouldRequestRoute(
                start: startDate,
                hasCoordinates: task.place?.latitude != nil && task.place?.longitude != nil,
                isTimePinned: task.isTimePinned,
                now: now
              ) else { return nil }

        // キャッシュ確認（失敗キャッシュも TTL 内は尊重して再要求しない）
        if let cached = etaCache[task.id],
           now.timeIntervalSince(cached.fetchedAt) < Self.cacheTTL(start: startDate, now: now) {
            return cached.eta
        }

        // 実行中要求があれば相乗り（await 中にキャッシュ未書き込みの窓があるため）
        if let running = inFlight[task.id] {
            return await running.value
        }

        // 現在位置（天気取得時に保存されたもの）。未保存なら要求しない。
        guard let origin = LastKnownLocation.load() else { return nil }
        guard let destLat = task.place?.latitude, let destLon = task.place?.longitude else { return nil }

        let taskID = task.id
        let request = Task { [weak self] () -> TimeInterval? in
            defer { self?.inFlight[taskID] = nil }

            let mkRequest = MKDirections.Request()
            mkRequest.source = MKMapItem(placemark: MKPlacemark(
                coordinate: CLLocationCoordinate2D(latitude: origin.latitude, longitude: origin.longitude)))
            mkRequest.destination = MKMapItem(placemark: MKPlacemark(
                coordinate: CLLocationCoordinate2D(latitude: destLat, longitude: destLon)))
            // ponytail: 移動手段は .automobile 固定。手段選択が要るなら TaskItem にフィールド追加から
            mkRequest.transportType = .automobile
            mkRequest.requestsAlternateRoutes = false

            let eta = (try? await MKDirections(request: mkRequest).calculate())?.routes.first?.expectedTravelTime
            self?.etaCache[taskID] = (eta: eta, fetchedAt: now)   // 失敗（nil）も同 TTL でキャッシュ
            return eta
        }
        inFlight[taskID] = request
        return await request.value
    }
}
