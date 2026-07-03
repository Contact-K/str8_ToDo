import SwiftUI

// MARK: - AppSettings Keys
enum AppSettingsKey {
    static let syncSystemCalendar = "syncSystemCalendar"
    static let syncSystemCalendarDefault = false

    static let syncWeather = "syncWeather"
    static let syncWeatherDefault = false

    static let enableNotifications = "enableNotifications"
    static let enableNotificationsDefault = true

    static let weekStartMinutes = "weekStartMinutes"
    static let weekStartMinutesDefault = 0

    static let weekEndMinutes = "weekEndMinutes"
    static let weekEndMinutesDefault = 1440

    static let weekBandIntervalHours = "weekBandIntervalHours"
    static let weekBandIntervalHoursDefault = 3
}

// MARK: - Week Band Structure
struct WeekBand: Identifiable, Hashable {
    let id: Int
    let label: String
    let startMinute: Int
    let endMinute: Int
}

// MARK: - Week Band Generation
@MainActor
func makeWeekBands(startMinute: Int, endMinute: Int, intervalMinutes: Int) -> [WeekBand] {
    let clampedStart = min(max(startMinute, 0), 1440)
    let clampedEnd = min(max(endMinute, 0), 1440)
    let clampedInterval = (intervalMinutes <= 0) ? 60 : min(max(intervalMinutes, 30), 720)

    // Fallback if end <= start
    let start = clampedEnd > clampedStart ? clampedStart : 0
    let end = clampedEnd > clampedStart ? clampedEnd : 1440

    var bands: [WeekBand] = []
    var bandIndex = 0
    var currentStart = start

    while currentStart < end {
        let currentEnd = min(currentStart + clampedInterval, end)
        let label = "\(hhmm(currentStart))–\(hhmm(currentEnd))"

        let band = WeekBand(
            id: bandIndex,
            label: label,
            startMinute: currentStart,
            endMinute: currentEnd
        )
        bands.append(band)

        currentStart = currentEnd
        bandIndex += 1
    }

    return bands
}

// MARK: - Time Formatting Helper
@MainActor
func hhmm(_ minutes: Int) -> String {
    let clamped = min(max(minutes, 0), 1440)
    let hours = clamped / 60
    let mins = clamped % 60
    return String(format: "%d:%02d", hours, mins)
}
