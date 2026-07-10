//
//  MoneyStats.swift
//  str(8) ToDo
//
//  月次支出の集計キャッシュと内訳表示ビュー（P8）。
//

import Foundation
import SwiftData
import SwiftUI

/// 月別支出統計のキャッシュ。
@Model
final class MonthMoneyStat {
    /// その月の開始日（startOfMonth）をキーにする。
    @Attribute(.unique) var month: Date
    /// その月の総支出。
    var totalSpend: Decimal
    /// その月のサブスク支出。
    var subscriptionSpend: Decimal

    init(month: Date, totalSpend: Decimal = 0, subscriptionSpend: Decimal = 0) {
        self.month = month
        self.totalSpend = totalSpend
        self.subscriptionSpend = subscriptionSpend
    }
}

enum MoneyStats {
    /// 金額付きタスクの月内発生を1箇所で反復する共通プリミティブ。
    /// amount > 0 のタスクだけを対象に、月内の各発生日（毎週×4回なら4回）で body を呼ぶ。
    static func forEachOccurrence(tasks: [TaskItem], month: Date, _ body: (Date, TaskItem) -> Void) {
        let cal = Calendar.current
        // 注意: date(bySetting: .day, value: 1) は前方検索で翌月に飛ぶため dateInterval を使う
        let monthStart = cal.dateInterval(of: .month, for: month)?.start ?? cal.startOfDay(for: month)
        let monthEnd = cal.date(byAdding: .month, value: 1, to: monthStart)!

        for task in tasks {
            guard (task.amount ?? 0) > 0 else { continue }
            var cursor = monthStart
            while cursor < monthEnd {
                if task.occurs(on: cursor) {
                    body(cursor, task)
                }
                cursor = cal.date(byAdding: .day, value: 1, to: cursor)!
            }
        }
    }

    /// 指定月の支出を再計算し、MonthMoneyStat に upsert する。
    /// - Parameters:
    ///   - month: startOfMonth のその月
    ///   - context: ModelContext
    static func recompute(month: Date, context: ModelContext) {
        let cal = Calendar.current
        let monthStart = cal.dateInterval(of: .month, for: month)?.start ?? cal.startOfDay(for: month)

        // ponytail: Decimal? の nil 比較は #Predicate で避けるため、fetch 後に Swift 側で フィルタ
        let descriptor = FetchDescriptor<TaskItem>(
            predicate: #Predicate { $0.startDate != nil }
        )
        guard let allTasks = try? context.fetch(descriptor) else { return }

        var totalSpend: Decimal = 0
        var subscriptionSpend: Decimal = 0

        forEachOccurrence(tasks: allTasks, month: monthStart) { _, task in
            let amount = task.amount ?? 0
            totalSpend += amount
            if task.category?.name == "サブスク" {
                subscriptionSpend += amount
            }
        }

        // upsert: 既存の MonthMoneyStat を fetch して update、無ければ insert
        let descriptor2 = FetchDescriptor<MonthMoneyStat>(predicate: #Predicate { $0.month == monthStart })
        do {
            if let existing = try context.fetch(descriptor2).first {
                existing.totalSpend = totalSpend
                existing.subscriptionSpend = subscriptionSpend
            } else {
                context.insert(MonthMoneyStat(month: monthStart, totalSpend: totalSpend, subscriptionSpend: subscriptionSpend))
            }
            try context.save()
        } catch {
            assertionFailure("MonthMoneyStat upsert failed: \(error)")
        }
    }
}

/// 月別支出の内訳ビュー（カテゴリ別・支払方法別）。
struct MoneyBreakdownView: View {
    let month: Date
    @Environment(\.modelContext) var modelContext
    @Query private var tasks: [TaskItem]

    var body: some View {
        NavigationStack {
            Form {
                // カテゴリ別内訳
                Section("カテゴリ別") {
                    let byCategory = categoryBreakdown()
                    let totalByCategory = byCategory.values.reduce(0, +)

                    ForEach(byCategory.sorted(by: { $0.value > $1.value }), id: \.key) { name, amount in
                        HStack {
                            Text(name.isEmpty ? "未分類" : name)
                            Spacer()
                            Text(currencyText(amount))
                                .fontWeight(.semibold)
                        }
                    }

                    Divider()
                    HStack {
                        Text("合計")
                            .fontWeight(.bold)
                        Spacer()
                        Text(currencyText(totalByCategory))
                            .fontWeight(.bold)
                            .foregroundColor(.accentColor)
                    }
                }

                // 支払方法別内訳
                Section("支払方法別") {
                    let byPayment = paymentBreakdown()
                    let totalByPayment = byPayment.values.reduce(0, +)

                    ForEach(byPayment.sorted(by: { $0.value > $1.value }), id: \.key) { method, amount in
                        HStack {
                            Text(method.isEmpty ? "未設定" : method)
                            Spacer()
                            Text(currencyText(amount))
                                .fontWeight(.semibold)
                        }
                    }

                    Divider()
                    HStack {
                        Text("合計")
                            .fontWeight(.bold)
                        Spacer()
                        Text(currencyText(totalByPayment))
                            .fontWeight(.bold)
                            .foregroundColor(.accentColor)
                    }
                }
            }
            .navigationTitle(monthTitle)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
        }
    }

    private var monthTitle: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ja_JP")
        f.dateFormat = "M月の内訳"
        return f.string(from: month)
    }

    private func categoryBreakdown() -> [String: Decimal] {
        breakdown { $0.category?.name ?? "" }
    }

    private func paymentBreakdown() -> [String: Decimal] {
        breakdown { $0.paymentMethod ?? "" }
    }

    /// 月内の発生日ごとに amount を key 別に合算。
    private func breakdown(_ key: (TaskItem) -> String) -> [String: Decimal] {
        var result: [String: Decimal] = [:]
        MoneyStats.forEachOccurrence(tasks: tasks, month: month) { _, task in
            result[key(task), default: 0] += task.amount ?? 0
        }
        return result
    }
}
