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

    /// 最終バックアップエクスポート日時（TimeInterval）。
    static let lastBackupExportDate = "lastBackupExportDate"

    /// 最後に取得した現在地の緯度（SunCalc/出発逆算が使う）
    static let lastKnownLatitude = "lastKnownLatitude"
    /// 最後に取得した現在地の経度（SunCalc/出発逆算が使う）
    static let lastKnownLongitude = "lastKnownLongitude"
}
