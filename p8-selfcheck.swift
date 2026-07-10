//
//  p8-selfcheck.swift — Phase 8 の自己チェック（月次支出集計 MoneyStats.recompute）
//
//  実行方法（macOS、リポジトリルートで）:
//    cd "/Users/konnotakuto/Swift_PRJS/str(8)_ToDo/str(8) ToDo" && \
//    DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swiftc -parse-as-library \
//      "str(8) ToDo/Enums.swift" "str(8) ToDo/TaskItem.swift" \
//      "str(8) ToDo/SupportingModels.swift" "str(8) ToDo/Color+Hex.swift" \
//      "str(8) ToDo/Formatting.swift" "str(8) ToDo/MoneyStats.swift" \
//      p8-selfcheck.swift -o /tmp/p8check && /tmp/p8check
//
//  アプリターゲットには含めない（pbxproj 未登録）。
//

import Foundation
import SwiftData

// MARK: - 共通ヘルパー

/// コンテナを保持したまま context を返す（コンテナ解放によるクラッシュ防止）。
@MainActor
func makeContext() -> (container: ModelContainer, context: ModelContext) {
    let schema = Schema([TaskItem.self, Category.self, PlaceTag.self, DayStat.self, MonthMoneyStat.self])
    let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: schema, configurations: config)
    return (container, container.mainContext)
}

func day(_ year: Int, _ month: Int, _ day: Int, hour: Int = 10) -> Date {
    Calendar.current.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
}

@MainActor
func fetchStat(month: Date, context: ModelContext) -> MonthMoneyStat? {
    let monthStart = Calendar.current.dateInterval(of: .month, for: month)!.start
    let descriptor = FetchDescriptor<MonthMoneyStat>(predicate: #Predicate { $0.month == monthStart })
    return try! context.fetch(descriptor).first
}

// MARK: - Test 1: 月内合算（単発 + FREQ=MONTHLY サブスク + FREQ=WEEKLY、月境界の除外）

@MainActor
func testMonthlyTotals() {
    let (container, context) = makeContext()
    _ = container

    let subs = Category(name: "サブスク")
    let life = Category(name: "生活")
    context.insert(subs)
    context.insert(life)

    // 5/15 開始の毎月サブスク → 7月は 7/15 に1回計上
    context.insert(TaskItem(title: "Netflix", category: subs,
                            startDate: day(2026, 5, 15), rrule: "FREQ=MONTHLY",
                            amount: 1490, paymentMethod: "クレジットカード"))
    // 7/10 の単発支出
    context.insert(TaskItem(title: "ランチ", category: life,
                            startDate: day(2026, 7, 10), amount: 1200, paymentMethod: "現金"))
    // 7/1(水)開始の毎週 → 7月は 7/1,8,15,22,29 の5回 = 500
    context.insert(TaskItem(title: "ジム", category: life,
                            startDate: day(2026, 7, 1), rrule: "FREQ=WEEKLY", amount: 100))
    // 月境界: 6/30 と 8/1 は7月に入らない
    context.insert(TaskItem(title: "6月末の支出", startDate: day(2026, 6, 30), amount: 9999))
    context.insert(TaskItem(title: "8月頭の支出", startDate: day(2026, 8, 1), amount: 5555))
    // 金額なしタスクは無視される
    context.insert(TaskItem(title: "金額なし", startDate: day(2026, 7, 10)))
    try! context.save()

    // 月半ばの日付を渡しても startOfMonth に正規化されること（bySetting の翌月飛びバグの回帰確認）
    MoneyStats.recompute(month: day(2026, 7, 20), context: context)

    guard let july = fetchStat(month: day(2026, 7, 1), context: context) else {
        assertionFailure("7月の MonthMoneyStat が作成されるべき")
        return
    }
    assert(july.totalSpend == Decimal(1490 + 1200 + 500),
           "7月合計 期待3190 実際\(july.totalSpend)")
    assert(july.subscriptionSpend == Decimal(1490),
           "7月サブスク 期待1490 実際\(july.subscriptionSpend)")

    // 6月: Netflix(6/15) + 6/30 の単発
    MoneyStats.recompute(month: day(2026, 6, 5), context: context)
    guard let june = fetchStat(month: day(2026, 6, 1), context: context) else {
        assertionFailure("6月の MonthMoneyStat が作成されるべき")
        return
    }
    assert(june.totalSpend == Decimal(1490 + 9999),
           "6月合計 期待11489 実際\(june.totalSpend)")
    assert(june.subscriptionSpend == Decimal(1490),
           "6月サブスク 期待1490 実際\(june.subscriptionSpend)")

    print("testMonthlyTotals: passed（月内合算・rrule・月境界）")
}

// MARK: - Test 2: upsert（再計算で二重挿入せず、値が更新される）

@MainActor
func testUpsert() {
    let (container, context) = makeContext()
    _ = container
    let subs = Category(name: "サブスク")
    context.insert(subs)
    context.insert(TaskItem(title: "Netflix", category: subs,
                            startDate: day(2026, 7, 15), amount: 1490))
    try! context.save()

    MoneyStats.recompute(month: day(2026, 7, 1), context: context)
    MoneyStats.recompute(month: day(2026, 7, 28), context: context)

    let all = try! context.fetch(FetchDescriptor<MonthMoneyStat>())
    assert(all.count == 1, "再計算で MonthMoneyStat は1件のまま 実際\(all.count)件")
    assert(all[0].totalSpend == Decimal(1490), "upsert 後の合計 期待1490 実際\(all[0].totalSpend)")

    // タスク追加 → 再計算で既存レコードが更新される
    context.insert(TaskItem(title: "追加支出", startDate: day(2026, 7, 20), amount: 510))
    try! context.save()
    MoneyStats.recompute(month: day(2026, 7, 1), context: context)

    let updated = try! context.fetch(FetchDescriptor<MonthMoneyStat>())
    assert(updated.count == 1, "更新後も1件 実際\(updated.count)件")
    assert(updated[0].totalSpend == Decimal(2000), "更新後の合計 期待2000 実際\(updated[0].totalSpend)")
    assert(updated[0].subscriptionSpend == Decimal(1490), "サブスク計は不変 期待1490 実際\(updated[0].subscriptionSpend)")

    print("testUpsert: passed（二重挿入なし・値更新）")
}

// MARK: - Test 3: FREQ=MONTHLY の月末クランプ（1/31 開始 → 2月は月末日に計上）

@MainActor
func testMonthEndClamp() {
    let (container, context) = makeContext()
    _ = container
    let subs = Category(name: "サブスク")
    context.insert(subs)
    context.insert(TaskItem(title: "月末サブスク", category: subs,
                            startDate: day(2026, 1, 31), rrule: "FREQ=MONTHLY", amount: 980))
    try! context.save()

    // occurs 単体: 2026年2月は28日まで → 2/28 に発生、2/27 には発生しない
    let task = try! context.fetch(FetchDescriptor<TaskItem>()).first!
    assert(task.occurs(on: day(2026, 2, 28)), "1/31 開始 FREQ=MONTHLY は 2/28 に発生すべき")
    assert(!task.occurs(on: day(2026, 2, 27)), "2/27 には発生しない")
    // 31日がある月は通常どおり31日
    assert(task.occurs(on: day(2026, 3, 31)), "3月は 3/31 に発生すべき")
    assert(!task.occurs(on: day(2026, 3, 28)), "3/28 には発生しない")

    // 集計: 2月に1回分計上される
    MoneyStats.recompute(month: day(2026, 2, 10), context: context)
    guard let feb = fetchStat(month: day(2026, 2, 1), context: context) else {
        assertionFailure("2月の MonthMoneyStat が作成されるべき")
        return
    }
    assert(feb.totalSpend == Decimal(980), "2月合計 期待980 実際\(feb.totalSpend)")
    assert(feb.subscriptionSpend == Decimal(980), "2月サブスク 期待980 実際\(feb.subscriptionSpend)")

    print("testMonthEndClamp: passed（月末クランプ）")
}

// MARK: - Test 4: currencyText（ja_JP 通貨表記）

func testCurrencyText() {
    assert(currencyText(Decimal(1490)).contains("1,490"), "桁区切り 実際\(currencyText(Decimal(1490)))")
    assert(currencyText(Decimal(1490)).contains("¥") || currencyText(Decimal(1490)).contains("￥"),
           "円記号 実際\(currencyText(Decimal(1490)))")
    assert(currencyText(0).contains("0"), "ゼロ 実際\(currencyText(0))")

    print("testCurrencyText: passed（ja_JP 通貨表記）")
}

// MARK: - Main

@main
@MainActor
struct P8SelfCheck {
    static func main() {
        testMonthlyTotals()
        testUpsert()
        testMonthEndClamp()
        testCurrencyText()

        print("p8-selfcheck: all passed")
    }
}
