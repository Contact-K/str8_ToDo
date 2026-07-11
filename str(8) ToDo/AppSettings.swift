import SwiftUI
import CoreLocation

// MARK: - AppSettings Keys
enum AppSettingsKey {
    static let syncSystemCalendar = "syncSystemCalendar"
    static let syncSystemCalendarDefault = false

    static let enableNotifications = "enableNotifications"
    static let enableNotificationsDefault = true

    /// 週ビューの表示日数（true=7日、false=平日5日）。
    static let weekShowSevenDays = "weekShowSevenDays"
    static let weekShowSevenDaysDefault = true

    /// 週次締めの通知曜日（0=日, 1=月, ..., 6=土）。iOS Calendar.Component.weekday の 1-indexed とは異なるので変換は呼び出し側が行う。
    static let weekReviewWeekday = "weekReviewWeekday"
    static let weekReviewWeekdayDefault = 0  // 日曜

    /// 週次締めの通知時刻（時のみ、0-23）。
    static let weekReviewHour = "weekReviewHour"
    static let weekReviewHourDefault = 20  // 20時

    /// クイック追加（P16）のサジェストフィールド（未認識ワードの辞書登録候補）を表示するか。
    static let enableDictionarySuggestions = "enableDictionarySuggestions"
    static let enableDictionarySuggestionsDefault = true

    /// 最終バックアップエクスポート日時（TimeInterval）。
    static let lastBackupExportDate = "lastBackupExportDate"

    /// 最後に取得した現在地の緯度（SunCalc/出発逆算が使う）
    static let lastKnownLatitude = "lastKnownLatitude"
    /// 最後に取得した現在地の経度（SunCalc/出発逆算が使う）
    static let lastKnownLongitude = "lastKnownLongitude"

    /// UserDefaults.standard に既定値を登録する。App 起動時に一度だけ呼ぶことで、
    /// 各読み出し側の `?? xxxDefault` フォールバックを不要にする。
    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            syncSystemCalendar: syncSystemCalendarDefault,
            enableNotifications: enableNotificationsDefault,
            weekShowSevenDays: weekShowSevenDaysDefault,
            weekReviewWeekday: weekReviewWeekdayDefault,
            weekReviewHour: weekReviewHourDefault,
            enableDictionarySuggestions: enableDictionarySuggestionsDefault
        ])
    }
}

// MARK: - 現在地ヘルパー

enum LastKnownLocation {
    /// 日の出日の入り(SunCalc)・出発逆算(DepartureService)が使う現在地キャッシュ。
    /// 未保存（キー不存在）なら nil。(0,0) 実座標と区別するため存在チェックで判定する。
    static func load() -> (latitude: Double, longitude: Double)? {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: AppSettingsKey.lastKnownLatitude) != nil,
              defaults.object(forKey: AppSettingsKey.lastKnownLongitude) != nil else { return nil }
        return (defaults.double(forKey: AppSettingsKey.lastKnownLatitude),
                defaults.double(forKey: AppSettingsKey.lastKnownLongitude))
    }

    /// 現在地を一度だけ取得してキャッシュを更新する（天気機能廃止に伴い旧天気取得プロバイダから移設）。
    /// 権限が無い/取得失敗なら何もしない（呼び出し側は load() の nil で未取得を判定）。
    static func refresh() async {
        let manager = CLLocationManager()
        switch manager.authorizationStatus {
        case .denied, .restricted:
            return
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        default:
            break
        }

        var location: CLLocation? = nil
        let updates = CLLocationUpdate.liveUpdates()
        var iterationCount = 0
        let maxIterations = 10
        do {
            for try await update in updates {
                iterationCount += 1
                if let loc = update.location {
                    location = loc
                    break
                }
                if update.authorizationDenied { break }
                if iterationCount >= maxIterations { break }
            }
        } catch {
            return
        }

        guard let location else { return }
        UserDefaults.standard.set(location.coordinate.latitude, forKey: AppSettingsKey.lastKnownLatitude)
        UserDefaults.standard.set(location.coordinate.longitude, forKey: AppSettingsKey.lastKnownLongitude)
    }
}
