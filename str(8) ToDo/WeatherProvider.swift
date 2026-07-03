import Foundation
import SwiftUI
import Observation
import CoreLocation
import WeatherKit

@MainActor @Observable final class WeatherProvider {
    enum Status: String {
        case idle = "未取得"
        case loading = "取得中"
        case loaded = "取得済み"
        case denied = "位置情報が必要"
        case unavailable = "利用不可"
    }

    var status: Status = .idle
    var statusDetail: String? = nil
    var lastUpdated: Date? = nil
    var temperatureText: String? = nil
    var symbolName: String = "cloud.sun"

    func refresh() async {
        status = .loading
        statusDetail = nil

        do {
            let manager = CLLocationManager()

            // 許可状態を確認
            switch manager.authorizationStatus {
            case .denied, .restricted:
                status = .denied
                statusDetail = "位置情報が許可されていません（設定アプリで許可）"
                return
            case .notDetermined:
                manager.requestWhenInUseAuthorization()
            default:
                break
            }

            // 位置の確定を待つ（iOS 17+）
            // ワンショット取得：最初の有効位置でbreak、update.authorizationDeniedで打ち切り
            // デッドロック防止に最大数イテレーションで諦める
            var location: CLLocation? = nil
            let updates = CLLocationUpdate.liveUpdates()
            var iterationCount = 0
            let maxIterations = 10

            for try await update in updates {
                iterationCount += 1
                if let loc = update.location {
                    location = loc
                    break
                }
                if update.authorizationDenied {
                    break
                }
                if iterationCount >= maxIterations {
                    break
                }
            }

            guard let location = location else {
                status = .denied
                statusDetail = "現在地を取得できませんでした"
                return
            }

            // WeatherKit で天気情報を取得
            let weather = try await WeatherKit.WeatherService.shared.weather(for: location)

            // 温度をセ氏に変換してテキスト化
            let celsius = weather.currentWeather.temperature.converted(to: .celsius).value
            temperatureText = "\(Int(celsius))°C"

            // シンボルと更新日時を設定
            symbolName = weather.currentWeather.symbolName
            lastUpdated = .now

            status = .loaded
            statusDetail = nil
        } catch {
            let ns = error as NSError
            status = .unavailable
            // ドメイン＋コードまで出すと原因切り分けに有効（WeatherKitの認証/権限エラーなど）
            statusDetail = "天気を取得できません。\(error.localizedDescription)\n[domain: \(ns.domain) / code: \(ns.code)]"
            print("WeatherKit error:", ns.domain, ns.code, ns.userInfo)
        }
    }
}
