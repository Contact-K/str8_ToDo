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

    /// タスク単位で影響月を全て再計算する。反復タスクは開始月〜今から12ヶ月先まで。単発は 1 ヶ月。
    /// ponytail: 反復タスクの amount 変更時に翌月以降が更新されない問題（P8 debate-review 繰り越し）の解消。
    /// EventComposerView が UNTIL を書かないため無期限反復として扱う。12 ヶ月先まで再計算し、それ以降は必要に応じ月ビュー閲覧時の自己修復に任せる。
    static func recompute(for task: TaskItem, context: ModelContext) {
        guard let start = task.startDate ?? (task.rrule != nil ? .now : nil) else {
            // 浮遊タスクは今月のみ（既存挙動）
            recompute(month: .now, context: context)
            return
        }
        let cal = Calendar.current
        let cap = cal.date(byAdding: .month, value: 12, to: .now) ?? .now
        var cursor = cal.dateInterval(of: .month, for: start)?.start ?? cal.startOfDay(for: start)
        let endMonth = cal.dateInterval(of: .month, for: cap)?.end ?? cap
        while cursor < endMonth {
            recompute(month: cursor, context: context)
            guard let next = cal.date(byAdding: .month, value: 1, to: cursor) else { break }
            cursor = next
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

/// Handoff donut のセグメント Path。start/end は 0..1 で 12 時から時計回り。
private struct DonutArc: Shape {
    let start: Double
    let end: Double
    let ring: CGFloat

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let radius = min(rect.width, rect.height) / 2 - ring / 2
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let startAngle = Angle.radians(start * 2 * .pi - .pi / 2)
        let endAngle = Angle.radians(end * 2 * .pi - .pi / 2)
        p.addArc(center: center, radius: radius,
                 startAngle: startAngle, endAngle: endAngle, clockwise: false)
        return p
    }
}

/// Handoff 07d: 月別支出の内訳（ドーナツ + カテゴリ別 + 支払方法別）。
struct MoneyBreakdownView: View {
    let month: Date
    @Environment(\.modelContext) var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    private var c: S8Palette { S8Palette.of(scheme) }
    @Query private var tasks: [TaskItem]

    private static let donutPalette: [Color] = [
        Color(s8: 0x2E4A6B),   // info
        Color(s8: 0x3D5A47),   // ok
        Color(s8: 0xDC8B28),   // accent
        Color(s8: 0xB24A33),   // danger
    ]

    var body: some View {
        let byCategory = categoryBreakdown()
        let byPayment = paymentBreakdown()
        let totalCat = byCategory.values.reduce(0, +)
        let totalPay = byPayment.values.reduce(0, +)

        VStack(spacing: 0) {
            // カスタムヘッダ（Handoff: [閉じる][タイトル][spacer]）
            HStack {
                Button("閉じる") { dismiss() }
                    .font(S8Font.jp(14))
                    .foregroundColor(c.fg2)
                Spacer()
                Text(monthTitle).font(S8Font.jp(16, .bold)).foregroundColor(c.fg1)
                Spacer()
                Color.clear.frame(width: 44, height: 1)
            }
            .padding(.horizontal, 24).padding(.top, 10).padding(.bottom, 14)

            ScrollView {
                VStack(spacing: 0) {
                    // ドーナツ
                    donut(byCategory: byCategory.sorted(by: { $0.value > $1.value }), total: totalCat)
                        .padding(.vertical, 6)

                    sectionCap("BY CATEGORY", jp: "カテゴリ別")
                        .padding(.top, 14)

                    ForEach(Array(byCategory.sorted(by: { $0.value > $1.value }).enumerated()), id: \.element.key) { i, entry in
                        breakdownRow(dot: Self.donutPalette[i % Self.donutPalette.count],
                                     name: entry.key.isEmpty ? "未分類" : entry.key,
                                     amount: entry.value)
                    }
                    totalRow(label: "合計", amount: totalCat)

                    sectionCap("BY PAYMENT", jp: "支払方法別")
                        .padding(.top, 20)

                    ForEach(byPayment.sorted(by: { $0.value > $1.value }), id: \.key) { method, amount in
                        breakdownRow(dot: nil, name: method.isEmpty ? "未設定" : method, amount: amount,
                                     nameColor: method.isEmpty ? c.fg3 : c.fg1)
                    }
                    totalRow(label: "合計", amount: totalPay)

                    Color.clear.frame(height: 24)
                }
                .padding(.horizontal, 24)
            }
        }
        .background(c.paper.ignoresSafeArea())
    }

    /// Handoff donut: セグメントを Path で描き、中央に MMM TOTAL テキスト。
    private func donut(byCategory: [(key: String, value: Decimal)], total: Decimal) -> some View {
        let size: CGFloat = 150
        let ring: CGFloat = 13
        let doubleTotal = NSDecimalNumber(decimal: total).doubleValue
        // 累積フラクションと分数の配列（上位4件、その他はまとめない）
        let entries = Array(byCategory.prefix(4))
        var cumulative: [Double] = [0]
        for e in entries {
            let fraction = doubleTotal > 0 ? NSDecimalNumber(decimal: e.value).doubleValue / doubleTotal : 0
            cumulative.append((cumulative.last ?? 0) + fraction)
        }
        return ZStack {
            ForEach(Array(entries.enumerated()), id: \.element.key) { i, _ in
                let start = cumulative[i]
                let end = cumulative[i + 1]
                DonutArc(start: start, end: end, ring: ring)
                    .stroke(Self.donutPalette[i % Self.donutPalette.count],
                            style: StrokeStyle(lineWidth: ring, lineCap: .butt))
                    .frame(width: size, height: size)
            }
            VStack(spacing: 2) {
                Text("\(monthShort()) TOTAL")
                    .font(S8Font.mono(8.5)).tracking(1.6).foregroundColor(c.fg3)
                Text(currencyText(total)).font(S8Font.mono(18, .bold)).foregroundColor(c.fg1)
            }
        }
        .frame(width: size, height: size)
    }

    private func sectionCap(_ tag: String, jp: String) -> some View {
        HStack(spacing: 10) {
            Text(tag).font(S8Font.mono(10)).tracking(1.6).foregroundColor(c.fg3)
            Text(jp).font(S8Font.jp(13, .medium)).foregroundColor(c.fg2)
            S8Rule()
        }
        .padding(.bottom, 8)
    }

    private func breakdownRow(dot: Color?, name: String, amount: Decimal, nameColor: Color? = nil) -> some View {
        HStack(spacing: 10) {
            if let dot { Circle().fill(dot).frame(width: 8, height: 8) }
            Text(name).font(S8Font.jp(13.5)).foregroundColor(nameColor ?? c.fg1)
            Spacer()
            Text(currencyText(amount)).font(S8Font.mono(13, .bold)).foregroundColor(c.fg1)
        }
        .padding(.vertical, 11)
        .overlay(alignment: .top) { S8Rule() }
    }

    private func totalRow(label: String, amount: Decimal) -> some View {
        HStack(spacing: 10) {
            Text(label).font(S8Font.jp(13.5, .bold)).foregroundColor(c.fg1)
            Spacer()
            Text(currencyText(amount)).font(S8Font.mono(13.5, .bold)).foregroundColor(c.accentInk)
        }
        .padding(.vertical, 11)
        .overlay(alignment: .top) { S8Rule(strong: true) }
    }

    private var monthTitle: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ja_JP")
        f.dateFormat = "M月の内訳"
        return f.string(from: month)
    }

    private func monthShort() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US")
        f.dateFormat = "MMM"
        return f.string(from: month).uppercased()
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
