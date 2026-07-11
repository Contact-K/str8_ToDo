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
            TaskItem.self, Category.self, PlaceTag.self, DayStat.self, MonthMoneyStat.self,
            Band.self, BandTemplate.self, BandAssignment.self, FocusSession.self, Subject.self,
            Profile.self, PhraseAlias.self
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: schema, configurations: config)
        let context = container.mainContext

        let study = Category(name: "勉強", colorHex: "#4F8DFD", symbolName: "book.fill")
        let life = Category(name: "生活", colorHex: "#34C759", symbolName: "house.fill")
        let subscription = Category(name: "サブスク", colorHex: "#FF9500", symbolName: "repeat.circle.fill")
        context.insert(study)
        context.insert(life)
        context.insert(subscription)

        // 科目サンプル
        let mathSubject = Subject(name: "数学", colorHex: "#4F8DFD")
        let englishSubject = Subject(name: "英語", colorHex: "#34C759")
        let exerciseSubject = Subject(name: "運動", colorHex: "#FF9500")
        context.insert(mathSubject)
        context.insert(englishSubject)
        context.insert(exerciseSubject)

        // プロフィールサンプル（P15 which）
        let workProfile = Profile(name: "会社", iconName: "briefcase.fill")
        let personalProfile = Profile(name: "個人", iconName: "person.fill")
        context.insert(workProfile)
        context.insert(personalProfile)

        // 辞書サンプル（P15 モデルのみ、UI は P17）
        [
            PhraseAlias(keyword: "ポモ", whCategory: .how, replacement: "25分", isBuiltIn: true),
            PhraseAlias(keyword: "今日", whCategory: .when, replacement: "今日", isBuiltIn: true),
            PhraseAlias(keyword: "大学", whCategory: .where_, replacement: "大学図書館", isBuiltIn: true),
            PhraseAlias(keyword: "会社", whCategory: .which, replacement: "会社", isBuiltIn: true)
        ].forEach { context.insert($0) }

        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)

        func at(_ hour: Int, _ minute: Int = 0) -> Date {
            cal.date(bySettingHour: hour, minute: minute, second: 0, of: today)!
        }

        let samples: [TaskItem] = [
            TaskItem(title: "線形代数の課題", category: study,
                     startDate: at(10), duration: 3600, phase: .today, status: .active, subjectID: mathSubject.id,
                     profile: workProfile),
            TaskItem(title: "ポモドーロ：統計レポート", category: study,
                     startDate: at(14), duration: 25 * 60, phase: .now, status: .done,
                     completedAt: .now, unlockDate: TaskItem.nextMidnight(), subjectID: mathSubject.id),
            TaskItem(title: "買い出し", category: life,
                     startDate: at(18, 30), duration: 1800, phase: .today, status: .approved,
                     completedAt: .now, approvedAt: .now, approverID: "self-future"),
            TaskItem(title: "読みたい論文を探す", category: study, phase: .someday, subjectID: englishSubject.id),
            // 浮遊タスク: 未仕分け2件 + snooze 中1件
            TaskItem(title: "部屋の掃除", category: life, phase: .today, sortIndex: 1),
            TaskItem(title: "参考書を注文", category: study, phase: .someday, sortIndex: 2, subjectID: mathSubject.id),
            TaskItem(title: "美容院を予約", category: life, phase: .someday, sortIndex: 3,
                     snoozeUntil: cal.date(byAdding: .day, value: 2, to: today)),
            TaskItem(title: "朝ラン", category: life,
                     startDate: Date.now.addingTimeInterval(-2 * 3600), duration: 1800,
                     phase: .today, status: .done, completedAt: .now,
                     unlockDate: cal.date(byAdding: .day, value: -1, to: today), subjectID: exerciseSubject.id),
            TaskItem(title: "歯医者", category: life,
                     startDate: at(9), duration: 1800, phase: .today, status: .active,
                     isTimePinned: true)
        ]
        samples.forEach { context.insert($0) }

        BandTemplate.seedDefaultIfNeeded(context)

        // RRULE ルーティーンサンプル（月水金の朝ジョギング）
        context.insert(TaskItem(title: "朝のジョギング", category: life,
                                startDate: at(6, 30), duration: 1800, phase: .today, status: .active,
                                rrule: "FREQ=WEEKLY;BYDAY=MO,WE,FR", subjectID: exerciseSubject.id))

        // お金関連サンプル（P8）
        context.insert(TaskItem(title: "Netflix", category: subscription,
                                startDate: at(0), duration: 0, phase: .today, status: .active,
                                rrule: "FREQ=MONTHLY", amount: Decimal(1490), paymentMethod: "クレジットカード"))
        context.insert(TaskItem(title: "Spotify", category: subscription,
                                startDate: at(0), duration: 0, phase: .today, status: .active,
                                rrule: "FREQ=MONTHLY", amount: Decimal(1080), paymentMethod: "クレジットカード"))
        context.insert(TaskItem(title: "ランチ代", category: life,
                                startDate: at(12), duration: 0, phase: .today, status: .active,
                                amount: Decimal(1200), paymentMethod: "現金"))
        context.insert(TaskItem(title: "書籍購入", category: study,
                                startDate: at(14), duration: 0, phase: .today, status: .active,
                                amount: Decimal(2980), paymentMethod: "クレジットカード"))

        // 特定日差し替えサンプル: 今週の木曜を「特別日」テンプレに
        let special = BandTemplate(name: "特別日", bands: [
            Band(name: "集中", startMinutes: 9 * 60, endMinutes: 13 * 60),
            Band(name: "自由", startMinutes: 13 * 60, endMinutes: 18 * 60)
        ])
        context.insert(special)
        let weekday = cal.component(.weekday, from: today)
        if let thursday = cal.date(byAdding: .day, value: 5 - weekday, to: today) {
            context.insert(BandAssignment(date: thursday, template: special))
        }

        // 集中セッションサンプル（昨日の25分ポモドーロ：数学）
        context.insert(FocusSession(start: today.addingTimeInterval(-15 * 3600),
                                    end: today.addingTimeInterval(-15 * 3600 + 25 * 60),
                                    subjectID: mathSubject.id))

        // 2日前の英語セッション（30分）
        context.insert(FocusSession(start: today.addingTimeInterval(-39 * 3600),
                                    end: today.addingTimeInterval(-39 * 3600 + 30 * 60),
                                    subjectID: englishSubject.id))

        // 3日前の運動セッション（1時間）
        context.insert(FocusSession(start: today.addingTimeInterval(-63 * 3600),
                                    end: today.addingTimeInterval(-63 * 3600 + 60 * 60),
                                    subjectID: exerciseSubject.id))

        // 合成 DayStat（過去365日）
        let counts = [1, 2, 0, 3, 1, 2, 0, 1]
        for i in 0..<365 {
            let dayOffset = -i
            let dayKey = cal.date(byAdding: .day, value: dayOffset, to: today) ?? today
            let completedCount = counts[i % counts.count]
            if completedCount > 0 {
                context.insert(DayStat(day: dayKey, completedCount: completedCount))
            }
        }

        return container
    }()
}

// MARK: - 単体サンプル（TaskCardView プレビュー用、コンテナ未挿入）

extension PreviewData {
    static func sampleTask1() -> TaskItem {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        let start = cal.date(bySettingHour: 10, minute: 0, second: 0, of: today)!
        return TaskItem(
            title: "線形代数の課題",
            category: nil,
            startDate: start,
            duration: 3600,
            phase: .today,
            status: .active
        )
    }

    static func sampleTask2() -> TaskItem {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        let start = cal.date(bySettingHour: 14, minute: 0, second: 0, of: today)!
        return TaskItem(
            title: "会議",
            category: nil,
            startDate: start,
            duration: 1800,
            phase: .today,
            status: .active,
            isImportant: true,
            isTimePinned: true
        )
    }

    static func sampleTask3() -> TaskItem {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        let start = cal.date(bySettingHour: 15, minute: 30, second: 0, of: today)!
        return TaskItem(
            title: "完了済みタスク",
            category: nil,
            startDate: start,
            duration: 900,
            phase: .today,
            status: .done,
            completedAt: .now
        )
    }
}
