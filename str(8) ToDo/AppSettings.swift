import SwiftUI

// MARK: - AppSettings Keys
enum AppSettingsKey {
    static let syncSystemCalendar = "syncSystemCalendar"
    static let syncSystemCalendarDefault = false

    static let syncWeather = "syncWeather"
    static let syncWeatherDefault = false

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
            syncWeather: syncWeatherDefault,
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
    /// 天気取得時に保存された現在地。未保存（キー不存在）なら nil。
    /// (0,0) 実座標と区別するため存在チェックで判定する。
    static func load() -> (latitude: Double, longitude: Double)? {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: AppSettingsKey.lastKnownLatitude) != nil,
              defaults.object(forKey: AppSettingsKey.lastKnownLongitude) != nil else { return nil }
        return (defaults.double(forKey: AppSettingsKey.lastKnownLatitude),
                defaults.double(forKey: AppSettingsKey.lastKnownLongitude))
    }
}
