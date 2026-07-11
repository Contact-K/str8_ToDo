//
//  p9-selfcheck.swift — Phase 9 の自己チェック（rebuildDayStats + resolveTemplate の date 優先）
//
//  実行方法（macOS、リポジトリルートで）:
//    cd "/Users/konnotakuto/Swift_PRJS/str(8)_ToDo/str(8) ToDo" && \
//    DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swiftc -parse-as-library \
//      "str(8) ToDo/Enums.swift" "str(8) ToDo/TaskItem.swift" \
//      "str(8) ToDo/SupportingModels.swift" "str(8) ToDo/BandModels.swift" \
//      "str(8) ToDo/FocusSession.swift" "str(8) ToDo/Color+Hex.swift" \
//      "str(8) ToDo/Subject.swift" \
//      p9-selfcheck.swift -o /tmp/p9check && /tmp/p9check
//
//  アプリターゲットには含めない（pbxproj 未登録）。
//

import Foundation
import SwiftData

// MARK: - 共通ヘルパー

/// コンテナを保持したまま context を返す（コンテナ解放によるクラッシュ防止）。
@MainActor
func makeContext() -> (container: ModelContainer, context: ModelContext) {
    let schema = Schema([TaskItem.self, Category.self, PlaceTag.self, DayStat.self, Band.self, BandTemplate.self, BandAssignment.self, FocusSession.self])
    let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: schema, configurations: config)
    return (container, container.mainContext)
}

func day(_ year: Int, _ month: Int, _ day: Int, hour: Int = 10) -> Date {
    Calendar.current.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
}

@MainActor
func fetchDayStat(day: Date, context: ModelContext) -> DayStat? {
    let dayKey = Calendar.current.startOfDay(for: day)
    let descriptor = FetchDescriptor<DayStat>(predicate: #Predicate { $0.day == dayKey })
    return try! context.fetch(descriptor).first
}

// MARK: - Test 1: rebuildDayStats の approved タスク件数計上

@MainActor
func testRebuildDayStats_ApprovedCount() {
    let (container, context) = makeContext()
    _ = container

    let study = Category(name: "勉強")
    context.insert(study)

    let d1 = day(2026, 7, 10)
    let d2 = day(2026, 7, 11)

    // 7/10 に approved タスク2件（approvedAt で計上）
    context.insert(TaskItem(title: "Task1", category: study, startDate: d1,
                            status: .approved, approvedAt: d1))
    context.insert(TaskItem(title: "Task2", category: study, startDate: d1,
                            status: .approved, approvedAt: d1))

    // 7/11 に approved タスク1件
    context.insert(TaskItem(title: "Task3", category: study, startDate: d2,
                            status: .approved, approvedAt: d2))

    // active / done タスクは計上されない
    context.insert(TaskItem(title: "Active", startDate: d1, status: .active))
    context.insert(TaskItem(title: "Done", startDate: d1, status: .done, completedAt: d1))

    try! context.save()

    DayStat.rebuildDayStats(context: context)

    let stat1 = fetchDayStat(day: d1, context: context)
    assert(stat1?.completedCount == 2, "7/10 の approved 件数 期待2 実際\(stat1?.completedCount ?? -1)")

    let stat2 = fetchDayStat(day: d2, context: context)
    assert(stat2?.completedCount == 1, "7/11 の approved 件数 期待1 実際\(stat2?.completedCount ?? -1)")

    print("testRebuildDayStats_ApprovedCount: passed（approved 件数計上）")
}

// MARK: - Test 3: rebuildDayStats の冪等性（二重実行で二重カウントなし）

@MainActor
func testRebuildDayStats_Idempotent() {
    let (container, context) = makeContext()
    _ = container

    let study = Category(name: "勉強")
    context.insert(study)

    let d1 = day(2026, 7, 10)

    context.insert(TaskItem(title: "Task1", category: study, status: .approved, approvedAt: d1))
    context.insert(TaskItem(title: "Task2", category: study, status: .approved, approvedAt: d1))

    try! context.save()

    // 1回目の rebuild
    DayStat.rebuildDayStats(context: context)
    let stat1 = fetchDayStat(day: d1, context: context)
    assert(stat1?.completedCount == 2, "1回目 期待2 実際\(stat1?.completedCount ?? -1)")

    // 2回目の rebuild（二重実行）
    DayStat.rebuildDayStats(context: context)
    let stat2 = fetchDayStat(day: d1, context: context)
    assert(stat2?.completedCount == 2, "2回目 期待2（二重カウントなし）実際\(stat2?.completedCount ?? -1)")

    print("testRebuildDayStats_Idempotent: passed（冪等性確認）")
}

// MARK: - Test 5: resolveTemplate の date 優先（date > weekday）

@MainActor
func testResolveTemplate_DatePriority() {
    let (container, context) = makeContext()
    _ = container

    let weekdayTemplate = BandTemplate(name: "平日")
    let dateTemplate = BandTemplate(name: "特別日")
    context.insert(weekdayTemplate)
    context.insert(dateTemplate)

    let targetDate = day(2026, 7, 10)  // 金曜日と仮定
    let weekday = Calendar.current.component(.weekday, from: targetDate)

    // 金曜日（weekday）には weekdayTemplate を割り当て
    context.insert(BandAssignment(weekday: weekday, template: weekdayTemplate))

    // 同じ 7/10 には dateTemplate を差し替え
    context.insert(BandAssignment(date: targetDate, template: dateTemplate))

    try! context.save()

    // resolveTemplate で date 指定が weekday より優先されることを確認
    let resolved = BandAssignment.resolveTemplate(for: targetDate, context: context)
    assert(resolved?.id == dateTemplate.id, "date 指定が weekday より優先されるべき（期待：\(dateTemplate.id) 実際：\(resolved?.id ?? UUID())）")

    print("testResolveTemplate_DatePriority: passed（date > weekday 優先）")
}

// MARK: - Main

@main
@MainActor
struct P9SelfCheck {
    static func main() {
        testRebuildDayStats_ApprovedCount()
        testRebuildDayStats_Idempotent()
        testResolveTemplate_DatePriority()

        print("p9-selfcheck: all passed")
    }
}
