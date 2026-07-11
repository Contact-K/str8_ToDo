//
//  WeekMath.swift
//  str8ToDo
//
//  週境界の純粋計算。SwiftData 非依存で p13-selfcheck から直接コンパイル可能にする。
//

import Foundation

enum WeekMath {
    /// `AppSettings.weekShowSevenDays` に対応する Calendar.firstWeekday。
    /// 7日表示=日曜起点(1、WeekView の従来グリッドと一致)、平日表示=月曜起点(2)。
    static func firstWeekday(showSevenDays: Bool) -> Int {
        showSevenDays ? 1 : 2
    }

    /// 対象日を含む週の開始（firstWeekday 起点）00:00。
    static func weekStart(of date: Date, firstWeekday: Int = 2, calendar: Calendar = .current) -> Date {
        var cal = calendar
        cal.firstWeekday = firstWeekday
        let dayStart = cal.startOfDay(for: date)
        let components = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: dayStart)
        return cal.date(from: components) ?? dayStart
    }

    /// 対象日を含む週の開始 00:00 から翌週開始 00:00（排他）。
    static func weekRange(of date: Date, firstWeekday: Int = 2, calendar: Calendar = .current) -> Range<Date> {
        let start = weekStart(of: date, firstWeekday: firstWeekday, calendar: calendar)
        let end = calendar.date(byAdding: .day, value: 7, to: start) ?? start
        return start ..< end
    }
}
