//
//  WeekReview.swift
//  str8ToDo
//
//  週次締めの記録。集計値のスナップショット（DayStat / FocusSession / MonthMoneyStat から
//  読み取った時点の値）を1週1件だけ保存する。値の再計算はしない（読むだけ）。
//

import Foundation
import SwiftData

@Model
final class WeekReview {
    @Attribute(.unique) var id: UUID
    /// 対象週の開始（月曜 00:00）
    var weekStart: Date
    /// 締めボタンを押した瞬間
    var closedAt: Date
    /// 対象週の集中セッション合計（秒）
    var focusTotalSec: TimeInterval
    /// 対象週の収支合計（JPY）
    var moneyTotal: Decimal
    /// 対象週の完了タスク数
    var doneCount: Int

    init(id: UUID = UUID(), weekStart: Date, closedAt: Date, focusTotalSec: TimeInterval, moneyTotal: Decimal, doneCount: Int) {
        self.id = id
        self.weekStart = weekStart
        self.closedAt = closedAt
        self.focusTotalSec = focusTotalSec
        self.moneyTotal = moneyTotal
        self.doneCount = doneCount
    }
}
