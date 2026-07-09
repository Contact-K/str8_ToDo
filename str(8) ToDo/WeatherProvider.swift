import Foundation
import SwiftUI
import Observation
import CoreLocation
import WeatherKit
import SwiftData

// MARK: - WeatherCache モデル
// 再構築可能なキャッシュなので .str8 バックアップ対象外
@Model final class WeatherCache {
    @Attribute(.unique) var day: Date   // startOfDay キー
    var symbolName: String
    var highCelsius: Double
    var lowCelsius: Double
    var fetchedAt: Date

    init(day: Date, symbolName: String, highCelsius: Double, lowCelsius: Double, fetchedAt: Date) {
        self.day = day
        self.symbolName = symbolName
        self.highCelsius = highCelsius
        self.lowCelsius = lowCelsius
        self.fetchedAt = fetchedAt
    }
}

// MARK: - WeatherFreshnessLabel
struct WeatherFreshnessLabel: View {
    let fetchedAt: Date

    private static let formatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }()

    var body: some View {
        Text(Self.formatter.localizedString(for: fetchedAt, relativeTo: .now))
            .font(.caption2)
            .foregroundStyle(.secondary)
    }
}

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

    func refresh(context: ModelContext) async {
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

            // 現在地を UserDefaults に保存（SunCalc/出発逆算が使う）
            UserDefaults.standard.set(location.coordinate.latitude, forKey: AppSettingsKey.lastKnownLatitude)
            UserDefaults.standard.set(location.coordinate.longitude, forKey: AppSettingsKey.lastKnownLongitude)

            // WeatherKit で天気情報を取得
            let weather = try await WeatherKit.WeatherService.shared.weather(for: location)

            // 温度をセ氏に変換してテキスト化
            let celsius = weather.currentWeather.temperature.converted(to: .celsius).value
            temperatureText = "\(Int(celsius))°C"

            // シンボルと更新日時を設定
            symbolName = weather.currentWeather.symbolName
            lastUpdated = .now

            // dailyForecast を WeatherCache に upsert（最大10日分）
            let cal = Calendar.current
            let today = cal.startOfDay(for: .now)

            for day in weather.dailyForecast.prefix(10) {
                let cacheDay = cal.startOfDay(for: day.date)
                let high = day.highTemperature.converted(to: .celsius).value
                let low = day.lowTemperature.converted(to: .celsius).value

                // day キーで既存行を検索
                let predicate = #Predicate<WeatherCache> { $0.day == cacheDay }
                let fetchDescriptor = FetchDescriptor(predicate: predicate)

                if let existingCache = try context.fetch(fetchDescriptor).first {
                    // 既存行を更新
                    existingCache.symbolName = day.symbolName
                    existingCache.highCelsius = high
                    existingCache.lowCelsius = low
                    existingCache.fetchedAt = .now
                } else {
                    // 新規行を挿入
                    let newCache = WeatherCache(
                        day: cacheDay,
                        symbolName: day.symbolName,
                        highCelsius: high,
                        lowCelsius: low,
                        fetchedAt: .now
                    )
                    context.insert(newCache)
                }
            }

            try? context.save()

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
