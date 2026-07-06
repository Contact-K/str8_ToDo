//
//  p3-selfcheck.swift — Phase 3 の自己チェック（SortDeckEngine の仕分けロジック）
//
//  実行方法（macOS、リポジトリルートで）:
//    DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swiftc -parse-as-library \
//      "str(8) ToDo/Enums.swift" "str(8) ToDo/TaskItem.swift" \
//      "str(8) ToDo/SupportingModels.swift" "str(8) ToDo/BandModels.swift" \
//      "str(8) ToDo/Color+Hex.swift" "str(8) ToDo/SortDeckEngine.swift" \
//      p3-selfcheck.swift -o /tmp/p3check && /tmp/p3check
//
//  アプリターゲットには含めない（pbxproj 未登録）。ロジックが壊れたら assert で落ちる。
//

import Foundation
import SwiftData

@main
@MainActor
struct P3SelfCheck {
    static func main() throws {
        let schema = Schema([TaskItem.self, Category.self, PlaceTag.self, DayStat.self,
                             Band.self, BandTemplate.self, BandAssignment.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: config)
        let ctx = container.mainContext

        let cal = Calendar.current
        let today = cal.date(from: DateComponents(year: 2026, month: 7, day: 7, hour: 8))!
        let todayStart = cal.startOfDay(for: today)
        let yesterday = cal.date(byAdding: .day, value: -1, to: todayStart)!
        let tomorrow = cal.date(byAdding: .day, value: 1, to: todayStart)!

        // --- deckTasks フィルタ ---
        let plain = TaskItem(title: "未仕分け", sortIndex: 2)
        let sortedToday = TaskItem(title: "今日仕分け済み", sortIndex: 0, lastSortedDay: todayStart)
        let sortedYesterday = TaskItem(title: "昨日仕分け", sortIndex: 1, lastSortedDay: yesterday)
        let snoozedFuture = TaskItem(title: "snooze中", sortIndex: 3, snoozeUntil: tomorrow)
        let snoozeExpired = TaskItem(title: "snooze切れ", sortIndex: 4, snoozeUntil: todayStart)
        let scheduled = TaskItem(title: "日付あり", startDate: today, sortIndex: 5)
        let done = TaskItem(title: "完了済み", status: .done, sortIndex: 6)
        let all = [plain, sortedToday, sortedYesterday, snoozedFuture, snoozeExpired, scheduled, done]
        all.forEach { ctx.insert($0) }

        let deck = SortDeckEngine.deckTasks(from: all, today: today, calendar: cal)
        assert(deck.map(\.title) == ["昨日仕分け", "未仕分け", "snooze切れ"],
               "フィルタ+sortIndex 順: \(deck.map(\.title))")

        // --- doneGate 右: markDone+スタンプ+次カードへ ---
        var engine = SortDeckEngine(tasks: all, today: today, calendar: cal)
        assert(engine.current === sortedYesterday && engine.stage == .doneGate)
        engine.answerRight(today: today, calendar: cal)
        assert(sortedYesterday.status == .done && sortedYesterday.completedAt != nil,
               "doneGate 右で markDone")
        assert(sortedYesterday.lastSortedDay == todayStart, "スタンプ=今日の startOfDay")
        assert(engine.current === plain && engine.stage == .doneGate, "次カードへ（doneGate 継続）")

        // --- doneGate 左: 同カードのまま todayGate へ ---
        engine.answerLeft(today: today, calendar: cal)
        assert(engine.current === plain && engine.stage == .todayGate, "doneGate 左で第2問へ")

        // --- todayGate 右: phase=.today+スタンプ+次カード（doneGate に戻る）---
        engine.answerRight(today: today, calendar: cal)
        assert(plain.phase == .today && plain.status == .active, "todayGate 右で phase=.today")
        assert(plain.lastSortedDay == todayStart, "todayGate 右でスタンプ")
        assert(engine.current === snoozeExpired && engine.stage == .doneGate)

        // --- todayGate 左: snoozeUntil=+7日+phase=.someday+スタンプ ---
        let phaseBeforeSnooze = snoozeExpired.phase
        engine.answerLeft(today: today, calendar: cal)   // doneGate 左 → todayGate
        engine.answerLeft(today: today, calendar: cal)   // todayGate 左 → 先送り
        let expectedSnooze = cal.date(byAdding: .day, value: 7, to: todayStart)!
        assert(snoozeExpired.snoozeUntil == expectedSnooze, "todayGate 左で snoozeUntil=+7日")
        assert(snoozeExpired.phase == .someday, "todayGate 左で phase=.someday")
        assert(snoozeExpired.lastSortedDay == todayStart, "todayGate 左でスタンプ")

        // --- 完走 ---
        assert(engine.isFinished, "全カード処理後 isFinished")

        // --- undo: 直前の回答（todayGate 左）が完全に巻き戻る ---
        assert(engine.canUndo)
        engine.undo()
        assert(snoozeExpired.snoozeUntil == todayStart && snoozeExpired.lastSortedDay == nil,
               "undo で snooze/スタンプが元に戻る")
        assert(snoozeExpired.phase == phaseBeforeSnooze, "undo で phase が元に戻る")
        assert(engine.current === snoozeExpired && engine.stage == .todayGate,
               "undo でカードが戻り stage も復元")

        // --- redo: 再適用 ---
        assert(engine.canRedo)
        engine.redo()
        assert(snoozeExpired.snoozeUntil == expectedSnooze && snoozeExpired.lastSortedDay == todayStart,
               "redo で再適用")
        assert(engine.isFinished && !engine.canRedo)

        // --- undo 連鎖: markDone の巻き戻し + 新規回答で redo 破棄 ---
        engine = SortDeckEngine(tasks: [TaskItem(title: "u1"), TaskItem(title: "u2")],
                                today: today, calendar: cal)
        let u1 = engine.current!
        engine.answerRight(today: today, calendar: cal)   // u1 done
        engine.undo()
        assert(u1.status == .active && u1.completedAt == nil && u1.unlockDate == nil &&
               u1.lastSortedDay == nil, "undo で markDone が完全に巻き戻る")
        assert(engine.canRedo)
        engine.answerLeft(today: today, calendar: cal)    // 新規回答
        assert(!engine.canRedo, "新規回答で redo 破棄")

        print("P3 self-check: ALL PASS")
    }
}
