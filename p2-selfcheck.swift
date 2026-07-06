//
//  p2-selfcheck.swift — Phase 2 の自己チェック（WeekLayout と TaskItem.occurs）
//
//  実行方法（macOS、リポジトリルートで）:
//    DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swiftc -parse-as-library \
//      "str(8) ToDo/Enums.swift" "str(8) ToDo/TaskItem.swift" \
//      "str(8) ToDo/SupportingModels.swift" "str(8) ToDo/BandModels.swift" \
//      "str(8) ToDo/Color+Hex.swift" "str(8) ToDo/WeekLayout.swift" \
//      p2-selfcheck.swift -o /tmp/p2check && /tmp/p2check
//
//  アプリターゲットには含めない（pbxproj 未登録）。ロジックが壊れたら assert で落ちる。
//

import Foundation

@main
struct P2SelfCheck {
    static func main() {
        let cal = Calendar.current

        // --- bandRowHeights: 行ごとに全日の最大チップ数、クランプ、列間行数不一致 ---
        // 列0=[1,3]、列1=[2]（行1が欠け=0扱い）→ 行0: max2 → 30+40=70、行1: max3 → 30+60=90
        var heights = bandRowHeights(chipCounts: [[1, 3], [2]])
        assert(heights == [70, 90], "最大チップ数選択+行数不一致の 0 扱い: \(heights)")
        // クランプ: 0チップ → 30 < 44 → 44、10チップ → 230 > 140 → 140
        heights = bandRowHeights(chipCounts: [[0, 10]])
        assert(heights == [44, 140], "min/max クランプ: \(heights)")
        assert(bandRowHeights(chipCounts: []).isEmpty, "空入力は空配列")

        // --- capsuleY: 行内補間・行間補間・範囲外クランプ ---
        let rows = [
            BandRowFrame(startMinute: 360, endMinute: 480, minY: 0, maxY: 60),
            BandRowFrame(startMinute: 540, endMinute: 660, minY: 100, maxY: 160)
        ]
        assert(capsuleY(forMinute: 420, rows: rows) == 30, "行内線形補間（中間点）")
        assert(capsuleY(forMinute: 510, rows: rows) == 80, "行間の隙間は前行 maxY と次行 minY の間に線形")
        assert(capsuleY(forMinute: 100, rows: rows) == 0, "全行より前は先頭 minY")
        assert(capsuleY(forMinute: 1000, rows: rows) == 160, "全行より後は末尾 maxY")
        assert(capsuleY(forMinute: 400, rows: []) == 0, "rows 空なら 0")

        // --- bandIndex: 包含・境界・最近傍スナップ ---
        let bands = [(start: 360, end: 540), (start: 540, end: 720)]
        assert(bandIndex(forStartMinute: 400, bands: bands) == 0, "包含判定")
        assert(bandIndex(forStartMinute: 540, bands: bands) == 1, "境界 m==end は次の枠")
        assert(bandIndex(forStartMinute: 100, bands: bands) == 0, "全枠より前は最初")
        assert(bandIndex(forStartMinute: 1000, bands: bands) == 1, "全枠より後は最後")
        let gapped = [(start: 360, end: 480), (start: 600, end: 720)]
        assert(bandIndex(forStartMinute: 500, bands: gapped) == 0, "隙間は近い方（前寄り）")
        assert(bandIndex(forStartMinute: 590, bands: gapped) == 1, "隙間は近い方（後寄り）")
        assert(bandIndex(forStartMinute: 400, bands: []) == nil, "bands 空なら nil")

        // --- hhmmLabel ---
        assert(hhmmLabel(540) == "9:00" && hhmmLabel(1440) == "24:00", "H:mm ラベル")

        // --- occurs: 最小 RRULE 展開 ---
        let monday = cal.date(from: DateComponents(year: 2026, month: 7, day: 6, hour: 9))!  // 月曜 9:00
        func addDays(_ n: Int) -> Date { cal.date(byAdding: .day, value: n, to: monday)! }

        // rrule なし: 同日のみ
        let plain = TaskItem(title: "plain", startDate: monday)
        assert(plain.occurs(on: monday, calendar: cal), "rrule なし: 当日 true")
        assert(!plain.occurs(on: addDays(1), calendar: cal), "rrule なし: 翌日 false")

        // DAILY
        let daily = TaskItem(title: "daily", startDate: monday, rrule: "FREQ=DAILY")
        assert(daily.occurs(on: addDays(1), calendar: cal) && daily.occurs(on: addDays(10), calendar: cal), "DAILY は毎日")
        assert(!daily.occurs(on: addDays(-1), calendar: cal), "開始日より前は false")

        // WEEKLY（同曜日）
        let weekly = TaskItem(title: "weekly", startDate: monday, rrule: "FREQ=WEEKLY")
        assert(weekly.occurs(on: addDays(7), calendar: cal), "WEEKLY: 翌週同曜日 true")
        assert(!weekly.occurs(on: addDays(3), calendar: cal), "WEEKLY: 他曜日 false")

        // WEEKLY;BYDAY 複数曜日
        let byday = TaskItem(title: "byday", startDate: monday, rrule: "FREQ=WEEKLY;BYDAY=MO,WE,FR")
        assert(byday.occurs(on: addDays(2), calendar: cal), "BYDAY: 水曜 true")
        assert(byday.occurs(on: addDays(4), calendar: cal), "BYDAY: 金曜 true")
        assert(!byday.occurs(on: addDays(1), calendar: cal), "BYDAY: 火曜 false")

        // MONTHLY（同「日」）
        let monthly = TaskItem(title: "monthly", startDate: monday, rrule: "FREQ=MONTHLY")
        let nextMonth6 = cal.date(from: DateComponents(year: 2026, month: 8, day: 6))!
        let nextMonth7 = cal.date(from: DateComponents(year: 2026, month: 8, day: 7))!
        assert(monthly.occurs(on: nextMonth6, calendar: cal), "MONTHLY: 翌月同日 true")
        assert(!monthly.occurs(on: nextMonth7, calendar: cal), "MONTHLY: 他日 false")

        // 未対応 RRULE は同日のみ
        let unknown = TaskItem(title: "unknown", startDate: monday, rrule: "FREQ=YEARLY")
        assert(unknown.occurs(on: monday, calendar: cal) && !unknown.occurs(on: addDays(1), calendar: cal),
               "未対応 RRULE は startDate 同日のみ")

        // --- orderedBands: 逆時刻順で insert しても startMinutes 昇順 ---
        let template = BandTemplate(name: "順序確認", bands: [
            Band(name: "夜", startMinutes: 18 * 60, endMinutes: 24 * 60),
            Band(name: "昼", startMinutes: 12 * 60, endMinutes: 13 * 60),
            Band(name: "朝", startMinutes: 6 * 60, endMinutes: 9 * 60)
        ])
        assert(template.orderedBands.map(\.name) == ["朝", "昼", "夜"],
               "orderedBands は startMinutes 昇順")

        print("P2 self-check: ALL PASS")
    }
}
