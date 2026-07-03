//
//  PreviewData.swift
//  str8ToDo
//
//  SwiftUI プレビュー用のインメモリ・コンテナとサンプルデータ。
//

import Foundation
import SwiftData

enum PreviewData {
    /// インメモリの ModelContainer。サンプルタスクを数件投入済み。
    @MainActor static let container: ModelContainer = {
        let schema = Schema([
            TaskItem.self, Category.self, FixedSchedule.self, PlaceTag.self, DayStat.self
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: schema, configurations: config)
        let context = container.mainContext

        let study = Category(name: "勉強", colorHex: "#4F8DFD", symbolName: "book.fill")
        let life = Category(name: "生活", colorHex: "#34C759", symbolName: "house.fill")
        context.insert(study)
        context.insert(life)

        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)

        func at(_ hour: Int, _ minute: Int = 0) -> Date {
            cal.date(bySettingHour: hour, minute: minute, second: 0, of: today)!
        }

        let samples: [TaskItem] = [
            TaskItem(title: "線形代数の課題", category: study,
                     startDate: at(10), duration: 3600, phase: .today, status: .incomplete),
            TaskItem(title: "ポモドーロ：統計レポート", category: study,
                     startDate: at(14), duration: 25 * 60, phase: .now, status: .pending,
                     completedAt: .now, unlockDate: TaskItem.nextMidnight()),
            TaskItem(title: "買い出し", category: life,
                     startDate: at(18, 30), duration: 1800, phase: .today, status: .approved,
                     completedAt: .now, approvedAt: .now, approverID: "self-future"),
            TaskItem(title: "読みたい論文を探す", category: study, phase: .someday)
        ]
        samples.forEach { context.insert($0) }
        return container
    }()
}
