//
//  WeekReportSource.swift
//  str8ToDo
//
//  週次締めの週報が使う「読み取り専用」データソース。DayStat / FocusSession / TaskItem を
//  そのまま合計するだけで、新規の集計ロジックは書かない（Phase 13 受け入れ基準）。
//

import Foundation
import SwiftData

enum WeekReportSource {

    /// 対象週の集中セッション合計秒。FocusSession.end が週内のものを合算（`end - start` を使う）。
    static func focusTotalSec(in range: Range<Date>, context: ModelContext) -> TimeInterval {
        let descriptor = FetchDescriptor<FocusSession>(predicate: #Predicate { $0.end >= range.lowerBound && $0.end < range.upperBound })
        let sessions = (try? context.fetch(descriptor)) ?? []
        return sessions.reduce(0) { $0 + $1.end.timeIntervalSince($1.start) }
    }

    /// 対象週の完了タスク数。TaskItem.completedAt が週内のもの（completedAt は完了時にのみ設定される）。
    static func doneCount(in range: Range<Date>, context: ModelContext) -> Int {
        let descriptor = FetchDescriptor<TaskItem>(predicate: #Predicate { task in
            task.completedAt != nil && task.completedAt! >= range.lowerBound && task.completedAt! < range.upperBound
        })
        let tasks = (try? context.fetch(descriptor)) ?? []
        return tasks.count
    }

    /// 対象週の収支合計（JPY, Decimal）。amount > 0 のタスクを対象に、rrule 展開しつつ週内の各発生日で amount を合算する（既存 MoneyStats.recompute と同じ発生カウント方式）。
    static func moneyTotal(in range: Range<Date>, context: ModelContext) -> Decimal {
        let descriptor = FetchDescriptor<TaskItem>(predicate: #Predicate { $0.startDate != nil })
        guard let tasks = try? context.fetch(descriptor) else { return 0 }
        let cal = Calendar.current
        var total: Decimal = 0
        for task in tasks {
            guard let amount = task.amount, amount > 0 else { continue }
            var cursor = range.lowerBound
            while cursor < range.upperBound {
                if task.occurs(on: cursor) { total += amount }
                cursor = cal.date(byAdding: .day, value: 1, to: cursor)!
            }
        }
        return total
    }

    /// 対象週の時刻付きタスクを昇順で返す（来週プレビュー用）。
    static func timedTasks(in range: Range<Date>, context: ModelContext) -> [TaskItem] {
        let descriptor = FetchDescriptor<TaskItem>(
            predicate: #Predicate { task in
                task.startDate != nil && task.startDate! >= range.lowerBound && task.startDate! < range.upperBound
            },
            sortBy: [SortDescriptor(\.startDate)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }
}
