//
//  YearView.swift
//  str(8) ToDo
//
//  1年ビュー（振り返り専用・操作しない）。
//  年スライダー、GitHub風草ヒートマップ、カテゴリ別積み上げ横バー、サマリーカード。
//

import SwiftUI
import SwiftData

@MainActor
struct YearView: View {
    var year: Int = Calendar.current.component(.year, from: .now)

    @Query private var tasks: [TaskItem]
    @Query private var dayStats: [DayStat]
    @State private var selectedYear: Int = 0

    private let cal = Calendar.current

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // MARK: - 年スライダー
                yearSlider

                // MARK: - サマリーカード
                summaryCards

                // MARK: - コントリビューショングラフ
                contributionGraph

                // MARK: - カテゴリ別積み上げ横バー
                categoryStackBar

                Spacer(minLength: 20)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .navigationTitle("\(selectedYear)年の振り返り")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if selectedYear == 0 {
                selectedYear = year
            }
        }
    }

    // MARK: - 年スライダー

    @ViewBuilder
    private var yearSlider: some View {
        let currentYear = Calendar.current.component(.year, from: .now)
        let minYear = currentYear - 9
        let maxYear = currentYear

        VStack(spacing: 12) {
            Text("\(selectedYear)")
                .font(.system(size: 36, weight: .bold))
                .foregroundStyle(Color.accentColor)

            Slider(
                value: Binding(
                    get: { Double(selectedYear) },
                    set: { selectedYear = Int($0.rounded()) }
                ),
                in: Double(minYear)...Double(maxYear),
                step: 1
            )
            .tint(Color.accentColor)

            Text("\(minYear) - \(maxYear)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }

    // MARK: - サマリーカード

    @ViewBuilder
    private var summaryCards: some View {
        let stats = yearStats()

        HStack(spacing: 12) {
            VStack(spacing: 4) {
                Text("\(stats.totalCount)")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundStyle(Color.accentColor)
                Text("達成タスク")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Color(.secondarySystemBackground))
            .cornerRadius(12)

            VStack(spacing: 4) {
                Text("\(stats.peakMonth)月")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundStyle(Color.accentColor)
                Text("最多月")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Color(.secondarySystemBackground))
            .cornerRadius(12)

            VStack(spacing: 4) {
                Text("\(stats.longestStreak)日")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundStyle(Color.accentColor)
                Text("連続記録")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Color(.secondarySystemBackground))
            .cornerRadius(12)
            .accessibilityLabel("\(stats.longestStreak)日連続")
        }
    }

    // MARK: - コントリビューショングラフ

    @ViewBuilder
    private var contributionGraph: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("達成数の推移")
                .font(.headline)
                .fontWeight(.semibold)
                .lineLimit(1)

            let dailyCount = computeDailyCount()

            if dailyCount.isEmpty {
                HStack {
                    Text("データがありません")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.vertical, 32)
            } else {
                let heatmapValues = Dictionary(uniqueKeysWithValues: dailyCount.map { date, count in
                    (date, Double(count))
                })

                HeatmapView(
                    year: selectedYear,
                    values: heatmapValues,
                    tint: Color.accentColor,
                    intensity: { value in
                        switch Int(value) {
                        case 0: return 0.15
                        case 1: return 0.4
                        case 2: return 0.6
                        case 3: return 0.8
                        default: return 1.0
                        }
                    },
                    labelFor: { date, value in
                        let month = cal.component(.month, from: date)
                        let day = cal.component(.day, from: date)
                        return "\(month)月\(day)日 \(Int(value) > 0 ? "\(Int(value))件承認" : "記録なし")"
                    }
                )
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }

    // MARK: - カテゴリ別積み上げ横バー

    @ViewBuilder
    private var categoryStackBar: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("カテゴリ別達成数")
                .font(.headline)
                .fontWeight(.semibold)
                .lineLimit(1)

            let categoryCounts = computeCategoryCounts()

            if categoryCounts.isEmpty {
                HStack {
                    Text("データがありません")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.vertical, 32)
            } else {
                let total = categoryCounts.reduce(0) { $0 + $1.count }

                HStack(spacing: 0) {
                    ForEach(categoryCounts, id: \.category.id) { item in
                        let width = total > 0 ? (Double(item.count) / Double(total)) * 100 : 0
                        Color(hex: item.category.colorHex)
                            .frame(maxWidth: .infinity)
                            .frame(height: 28)
                            .opacity(width > 0 ? 1 : 0)
                            .accessibilityLabel("\(item.category.name): \(String(format: "%.1f", width))%")
                    }
                }
                .cornerRadius(8)

                // 凡例
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(categoryCounts, id: \.category.id) { item in
                        HStack(spacing: 8) {
                            Circle()
                                .fill(Color(hex: item.category.colorHex))
                                .frame(width: 12, height: 12)
                            Text(item.category.name)
                                .font(.caption)
                                .foregroundStyle(.primary)
                            Spacer()
                            Text("\(item.count)")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundStyle(.secondary)
                        }
                        .accessibilityLabel("\(item.category.name): \(item.count)件")
                    }
                }
                .padding(.top, 8)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }

    // MARK: - ヘルパー: 集計

    private func computeDailyCount() -> [Date: Int] {
        var result: [Date: Int] = [:]

        // focusSeconds のみの日（completedCount == 0）は承認ゼロなのでヒートマップ/ストリークから除外
        for stat in dayStats where stat.completedCount > 0 && cal.component(.year, from: stat.day) == selectedYear {
            result[stat.day] = stat.completedCount
        }

        return result
    }

    private func computeCategoryCounts() -> [(category: Category, count: Int)] {
        var counts: [UUID: (Category, Int)] = [:]

        for task in tasks where task.status == .approved {
            let achieveDate = task.approvedAt ?? task.completedAt ?? task.startDate
            if let date = achieveDate,
               cal.component(.year, from: date) == selectedYear,
               let category = task.category {
                if counts[category.id] == nil {
                    counts[category.id] = (category, 0)
                }
                counts[category.id]!.1 += 1
            }
        }

        return counts.values.sorted { $0.1 > $1.1 }
    }

    private func yearStats() -> (totalCount: Int, peakMonth: Int, longestStreak: Int) {
        let dailyCount = computeDailyCount()

        if dailyCount.isEmpty {
            return (totalCount: 0, peakMonth: 1, longestStreak: 0)
        }

        // 総数
        let total = dailyCount.values.reduce(0, +)

        // 最多月
        var monthCounts: [Int: Int] = [:]
        for (date, count) in dailyCount {
            let month = cal.component(.month, from: date)
            monthCounts[month, default: 0] += count
        }
        let peakMonth = monthCounts.max(by: { $0.value < $1.value })?.key ?? 1

        // 最長連続日数
        let sortedDates = dailyCount.keys.sorted()
        var longestStreak = 0
        var currentStreak = 0
        var prevDate: Date?

        for date in sortedDates {
            if let prev = prevDate,
               cal.dateComponents([.day], from: prev, to: date).day == 1 {
                currentStreak += 1
            } else {
                currentStreak = 1
            }
            longestStreak = max(longestStreak, currentStreak)
            prevDate = date
        }

        return (totalCount: total, peakMonth: peakMonth, longestStreak: longestStreak)
    }
}

#Preview {
    NavigationStack {
        YearView()
    }
    .modelContainer(PreviewData.container)
}
