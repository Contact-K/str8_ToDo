// Run: DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swiftc -parse-as-library "str(8) ToDo/WeekMath.swift" p13-selfcheck.swift -o /tmp/p13check && /tmp/p13check

import Foundation

@main
struct P13SelfCheck {
    static func main() {
        var cal = Calendar(identifier: .gregorian)
        cal.firstWeekday = 2  // 月曜
        cal.timeZone = TimeZone(identifier: "UTC")!

        // Test 1: 月曜任意時刻 → その日の 00:00
        do {
            // 2026-07-06 (月) 15:30 UTC
            var comp = DateComponents(); comp.year = 2026; comp.month = 7; comp.day = 6; comp.hour = 15; comp.minute = 30
            let d = cal.date(from: comp)!
            let start = WeekMath.weekStart(of: d, calendar: cal)
            let expected = cal.startOfDay(for: d)
            assert(start == expected, "monday 15:30 -> monday 00:00 (got \(start), expected \(expected))")
        }

        // Test 2: 日曜（週の終わり）→ 前の月曜 00:00
        do {
            // 2026-07-12 (日) 23:00 UTC → 2026-07-06 (月) 00:00
            var comp = DateComponents(); comp.year = 2026; comp.month = 7; comp.day = 12; comp.hour = 23
            let d = cal.date(from: comp)!
            let start = WeekMath.weekStart(of: d, calendar: cal)
            var expectedComp = DateComponents(); expectedComp.year = 2026; expectedComp.month = 7; expectedComp.day = 6
            let expected = cal.date(from: expectedComp)!
            assert(start == expected, "sunday 23:00 -> previous monday 00:00 (got \(start), expected \(expected))")
        }

        // Test 3: weekRange は 7 日
        do {
            var comp = DateComponents(); comp.year = 2026; comp.month = 7; comp.day = 9  // 木曜
            let d = cal.date(from: comp)!
            let range = WeekMath.weekRange(of: d, calendar: cal)
            let span = range.upperBound.timeIntervalSince(range.lowerBound)
            assert(span == 7 * 24 * 3600, "weekRange is 7 days (got \(span))")
        }

        // Test 4: 年境界（1月1日を含む週）でも矛盾しない
        do {
            // 2026-01-01 (木) → 2025-12-29 (月) から始まる週
            var comp = DateComponents(); comp.year = 2026; comp.month = 1; comp.day = 1
            let d = cal.date(from: comp)!
            let start = WeekMath.weekStart(of: d, calendar: cal)
            var expectedComp = DateComponents(); expectedComp.year = 2025; expectedComp.month = 12; expectedComp.day = 29
            let expected = cal.date(from: expectedComp)!
            assert(start == expected, "year boundary monday (got \(start), expected \(expected))")
        }

        // Test 5: 週境界の点（月曜 00:00 ちょうど）
        do {
            var comp = DateComponents(); comp.year = 2026; comp.month = 7; comp.day = 6  // 月曜 00:00
            let d = cal.date(from: comp)!
            let start = WeekMath.weekStart(of: d, calendar: cal)
            assert(start == d, "monday 00:00 -> same (got \(start), expected \(d))")
        }

        print("P13 self-check: ALL PASS")
    }
}
