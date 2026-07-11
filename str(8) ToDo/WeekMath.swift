//
//  WeekMath.swift
//  str8ToDo
//
//  週境界の純粋計算。SwiftData 非依存で p13-selfcheck から直接コンパイル可能にする。
//

import Foundation

enum WeekMath {
    /// 対象日を含む週の月曜 00:00。
    static func weekStart(of date: Date, calendar: Calendar = .current) -> Date {
        var cal = calendar
        cal.firstWeekday = 2
        let dayStart = cal.startOfDay(for: date)
        let components = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: dayStart)
        return cal.date(from: components) ?? dayStart
    }

    /// 対象日を含む週の月曜 00:00 から翌週月曜 00:00（排他）。
    static func weekRange(of date: Date, calendar: Calendar = .current) -> Range<Date> {
        let start = weekStart(of: date, calendar: calendar)
        let end = calendar.date(byAdding: .day, value: 7, to: start) ?? start
        return start ..< end
    }
}
