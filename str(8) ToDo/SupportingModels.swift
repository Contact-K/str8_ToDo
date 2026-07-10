//
//  SupportingModels.swift
//  str8ToDo
//
//  カテゴリ・場所タグ・日次集計キャッシュ。
//

import Foundation
import SwiftData

/// タスクの分類。年ビューの積み上げ棒や色分けに使う。
@Model
final class Category {
    @Attribute(.unique) var id: UUID
    var name: String
    /// "#RRGGBB" 形式のカラー。
    var colorHex: String
    var symbolName: String

    @Relationship(deleteRule: .nullify)
    var tasks: [TaskItem]

    init(
        id: UUID = UUID(),
        name: String,
        colorHex: String = "#4F8DFD",
        symbolName: String = "tag.fill",
        tasks: [TaskItem] = []
    ) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
        self.symbolName = symbolName
        self.tasks = tasks
    }
}

/// 場所タグ。出発時刻の逆算（後続フェーズ）で座標を使う。
@Model
final class PlaceTag {
    @Attribute(.unique) var id: UUID
    var name: String
    var latitude: Double?
    var longitude: Double?

    @Relationship(deleteRule: .nullify)
    var tasks: [TaskItem]

    init(id: UUID = UUID(), name: String, latitude: Double? = nil, longitude: Double? = nil, tasks: [TaskItem] = []) {
        self.id = id
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
        self.tasks = tasks
    }
}

/// 日次の事前集計キャッシュ。年ビューの草グラフを高速描画するため。
@Model
final class DayStat {
    /// その日の 00:00（startOfDay）をキーにする。
    @Attribute(.unique) var day: Date
    /// 承認済みタスク数。
    var completedCount: Int
    /// 集中時間の合計（秒）。
    var focusSeconds: Int

    init(day: Date, completedCount: Int = 0, focusSeconds: Int = 0) {
        self.day = day
        self.completedCount = completedCount
        self.focusSeconds = focusSeconds
    }
}

// MARK: - 再構築

extension DayStat {
    /// 全 DayStat を削除して approved タスク + FocusSession から再構築する。
    /// 冪等（二重実行で二重カウントなし）。
    @MainActor
    static func rebuildDayStats(context: ModelContext) {
        let cal = Calendar.current

        // 既存 DayStat を全削除
        let allStats = (try? context.fetch(FetchDescriptor<DayStat>())) ?? []
        allStats.forEach { context.delete($0) }

        // approved タスクを日ごと集計
        var dayMap: [Date: (count: Int, focusSeconds: Int)] = [:]

        let allTasks = (try? context.fetch(FetchDescriptor<TaskItem>())) ?? []
        for task in allTasks where task.status == .approved {
            let achieveDate = task.approvedAt ?? task.completedAt ?? task.startDate
            if let date = achieveDate {
                let dayStart = cal.startOfDay(for: date)
                if dayMap[dayStart] == nil {
                    dayMap[dayStart] = (count: 0, focusSeconds: 0)
                }
                dayMap[dayStart]!.count += 1
            }
        }

        // FocusSession の end フィールドから focusSeconds を集計
        let allSessions = (try? context.fetch(FetchDescriptor<FocusSession>())) ?? []
        for session in allSessions {
            let dayStart = cal.startOfDay(for: session.end)
            let duration = Int(session.end.timeIntervalSince(session.start))
            if dayMap[dayStart] == nil {
                dayMap[dayStart] = (count: 0, focusSeconds: 0)
            }
            dayMap[dayStart]!.focusSeconds += duration
        }

        // 全 DayStat は冒頭で delete 済みなので素直に insert（既存行は残っていない）
        for (day, stats) in dayMap {
            context.insert(DayStat(day: day, completedCount: stats.count, focusSeconds: stats.focusSeconds))
        }

        try? context.save()
    }
}
