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

    /// 対象週の承認済みタスク数。approvedAt が週内のもの（approvedAt は TaskItem.approve() で
    /// status が .approved になった時にしか設定されないため、これ自体が承認済みの判定になる）。
    /// （P13 残タスク: 承認漏れがあっても締められる／「一掃してから」の儀式指示を数字に反映するため completedAt 基準から変更。
    /// ※ #Predicate は enum ケースへの keyPath 比較（`task.status == .approved`）をサポートしないため、approvedAt のみで判定）。
    static func approvedCount(in range: Range<Date>, context: ModelContext) -> Int {
        let descriptor = FetchDescriptor<TaskItem>(predicate: #Predicate { task in
            task.approvedAt != nil && task.approvedAt! >= range.lowerBound && task.approvedAt! < range.upperBound
        })
        let tasks = (try? context.fetch(descriptor)) ?? []
        return tasks.count
    }

    /// 対象週の収支合計（JPY, Decimal）。amount > 0 のタスクを対象に、rrule 展開しつつ週内の各発生日で amount を合算する（既存 MoneyStats.recompute と同じ発生カウント方式）。
    /// オーナー判断（2026-07-11）: MonthMoneyStat 参照への切り替えは見送り、都度計算のままで OK（週単位の按分ロジックを追加するコストに対してリターンが薄いため）。
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

    /// 週報の3値をまとめて1回で読む（WeekReviewView の reportSection/commitAndClose/exportImage が
    /// 個別に fetch していた重複をなくすための集約 load。新規集計は書かない：既存3関数を束ねるだけ）。
    struct WeekReport {
        var focusTotalSec: TimeInterval
        var moneyTotal: Decimal
        var approvedCount: Int
    }

    static func load(in range: Range<Date>, context: ModelContext) -> WeekReport {
        WeekReport(
            focusTotalSec: focusTotalSec(in: range, context: context),
            moneyTotal: moneyTotal(in: range, context: context),
            approvedCount: approvedCount(in: range, context: context)
        )
    }
}
