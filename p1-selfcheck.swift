//
//  p1-selfcheck.swift — Phase 1 の自己チェック（DayRowBuilder の分単位マージ）
//
//  実行方法（macOS、リポジトリルートで）:
//    DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swiftc -parse-as-library \
//      "str(8) ToDo/Enums.swift" "str(8) ToDo/TaskItem.swift" \
//      "str(8) ToDo/SupportingModels.swift" "str(8) ToDo/BandModels.swift" \
//      "str(8) ToDo/Color+Hex.swift" "str(8) ToDo/DayRowBuilder.swift" \
//      p1-selfcheck.swift -o /tmp/p1check && /tmp/p1check
//
//  アプリターゲットには含めない（pbxproj 未登録）。ロジックが壊れたら assert で落ちる。
//

import Foundation

@main
struct P1SelfCheck {
    static func main() {
        let cal = Calendar.current
        let day = cal.date(from: DateComponents(year: 2026, month: 7, day: 6))!  // 月曜
        func at(_ hour: Int, _ minute: Int = 0) -> Date {
            cal.date(bySettingHour: hour, minute: minute, second: 0, of: day)!
        }

        // デフォルト平日テンプレと同じ5枠
        let bands = [
            Band(name: "朝",   startMinutes: 6 * 60,  endMinutes: 9 * 60,  order: 0),
            Band(name: "午前", startMinutes: 9 * 60,  endMinutes: 12 * 60, order: 1),
            Band(name: "昼",   startMinutes: 12 * 60, endMinutes: 13 * 60, order: 2),
            Band(name: "午後", startMinutes: 13 * 60, endMinutes: 18 * 60, order: 3),
            Band(name: "夜",   startMinutes: 18 * 60, endMinutes: 24 * 60, order: 4)
        ]

        func index(of id: String, in rows: [DayRow]) -> Int {
            guard let i = rows.firstIndex(where: { $0.id == id }) else {
                fatalError("row not found: \(id)")
            }
            return i
        }

        // --- 1) 5枠＋タスク2件が分順に交互配置される ---
        let t7 = TaskItem(title: "朝ラン", startDate: at(7), duration: 3600)   // 420–480
        let t10 = TaskItem(title: "課題",  startDate: at(10), duration: 3600)  // 600–660
        var rows = DayRowBuilder.buildRows(allDayTasks: [], timedTasks: [t7, t10],
                                           bands: bands, now: nil, calendar: cal)
        let iAsa    = index(of: "band-\(bands[0].id.uuidString)", in: rows)   // 朝 360
        let iT7     = index(of: "task-\(t7.id.uuidString)", in: rows)         // 420
        let iGozen  = index(of: "band-\(bands[1].id.uuidString)", in: rows)   // 午前 540
        let iT10    = index(of: "task-\(t10.id.uuidString)", in: rows)        // 600
        let iHiru   = index(of: "band-\(bands[2].id.uuidString)", in: rows)   // 昼 720
        assert(iAsa < iT7 && iT7 < iGozen && iGozen < iT10 && iT10 < iHiru,
               "朝(360)→7時タスク(420)→午前(540)→10時タスク(600)→昼(720) の分順マージ")
        // 8:00–10:00 の空き（480 分の位置、午前見出しより前）
        let iGap = rows.firstIndex { if case .gap = $0 { return true }; return false }!
        assert(iT7 < iGap && iGap < iGozen, "gap(480) は7時タスクと午前見出しの間")

        // --- 2) 同分タイブレーク: 9:00 タスクと 午前(540) は見出しが先 ---
        let t9 = TaskItem(title: "歯医者", startDate: at(9), duration: 1800)
        rows = DayRowBuilder.buildRows(allDayTasks: [], timedTasks: [t9],
                                       bands: bands, now: nil, calendar: cal)
        assert(index(of: "band-\(bands[1].id.uuidString)", in: rows) <
               index(of: "task-\(t9.id.uuidString)", in: rows),
               "同分なら見出し→タスク")

        // --- 3) gap 閾値: 29分差はなし、30分差はあり（start/duration 検証）---
        let a = TaskItem(title: "A", startDate: at(9), duration: 3600)  // 終了 10:00
        let b29 = TaskItem(title: "B", startDate: at(10, 29), duration: 600)
        rows = DayRowBuilder.buildRows(allDayTasks: [], timedTasks: [a, b29],
                                       bands: [], now: nil, calendar: cal)
        assert(!rows.contains { if case .gap = $0 { return true }; return false }, "29分差は gap なし")

        let b30 = TaskItem(title: "B", startDate: at(10, 30), duration: 600)
        rows = DayRowBuilder.buildRows(allDayTasks: [], timedTasks: [a, b30],
                                       bands: [], now: nil, calendar: cal)
        let gaps = rows.compactMap { row -> (start: Date, duration: TimeInterval)? in
            if case .gap(let s, let d) = row { return (s, d) }
            return nil
        }
        assert(gaps.count == 1, "30分差は gap 1件")
        assert(gaps[0].start == a.endDate!, "gap の start は前タスクの終了時刻")
        assert(gaps[0].duration == 30 * 60, "gap の duration は30分")

        // --- 4) now 挿入位置: 2タスクの間、now=nil なら行なし ---
        let t12 = TaskItem(title: "昼会", startDate: at(12), duration: 3600)
        rows = DayRowBuilder.buildRows(allDayTasks: [], timedTasks: [a, t12],
                                       bands: [], now: at(11), calendar: cal)
        let iNow = index(of: "now", in: rows)
        assert(index(of: "task-\(a.id.uuidString)", in: rows) < iNow &&
               iNow < index(of: "task-\(t12.id.uuidString)", in: rows),
               "now(11:00) は9時タスクと12時タスクの間")
        rows = DayRowBuilder.buildRows(allDayTasks: [], timedTasks: [a, t12],
                                       bands: [], now: nil, calendar: cal)
        assert(!rows.contains { if case .nowSeparator = $0 { return true }; return false },
               "now=nil なら「今」行なし")

        // --- 5) 終日タスクは常に先頭 ---
        let allDay = TaskItem(title: "終日", startDate: at(0), isAllDay: true)
        rows = DayRowBuilder.buildRows(allDayTasks: [allDay], timedTasks: [a],
                                       bands: bands, now: nil, calendar: cal)
        assert(rows.first?.id == "task-\(allDay.id.uuidString)", "終日タスクが先頭")

        print("P1 self-check: ALL PASS")
    }
}
