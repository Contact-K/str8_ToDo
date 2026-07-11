//
//  WidgetSnapshotService.swift
//  str(8) ToDo
//
//  アプリ側のスナップショット生成器。
//

import Foundation
import SwiftData
import WidgetKit

@MainActor
enum WidgetSnapshotService {
    static func refresh(_ context: ModelContext) {
        // 1. now/today を用意
        let now = Date.now
        let today = Calendar.current.startOfDay(for: now)

        // 2. upcoming: TaskItem を fetch し Swift 側で filter
        let allTasks: [TaskItem]
        do {
            allTasks = try context.fetch(FetchDescriptor<TaskItem>())
        } catch {
            // fetch 失敗時は write をスキップし、既存の良いキャッシュを残す
            return
        }
        // 当日の RRULE インスタンスも展開（DayAgendaView と同一ルール）
        let cal = Calendar.current
        let upcoming = allTasks
            .compactMap { task -> WidgetSnapshot.Card? in
                guard task.status == .active, !task.isAllDay else { return nil }
                guard let start = task.startDate else { return nil }
                guard task.occurs(on: today, calendar: cal) else { return nil }
                // 反復タスクは today の同時刻に投影
                let projectedStart = cal.date(
                    bySettingHour: cal.component(.hour, from: start),
                    minute: cal.component(.minute, from: start),
                    second: 0,
                    of: today
                ) ?? start
                let projectedEnd = projectedStart.addingTimeInterval(task.duration)
                guard projectedEnd > now else { return nil }
                return WidgetSnapshot.Card(
                    title: task.title,
                    start: projectedStart,
                    end: projectedEnd,
                    colorHex: task.colorHex ?? task.category?.colorHex,
                    isTimePinned: task.isTimePinned
                )
            }
            .sorted { $0.start < $1.start }
            .prefix(20)   // Widget メモリ制約下のデコード上限
            .map { $0 }

        // 3. bands: BandAssignment.resolveTemplate(for: today, context: context)?.orderedBands ?? []
        let bands: [WidgetSnapshot.BandInfo] = (BandAssignment.resolveTemplate(for: today, context: context)?.orderedBands ?? [])
            .map { band in
                WidgetSnapshot.BandInfo(
                    name: band.name,
                    startMinutes: band.startMinutes,
                    endMinutes: band.endMinutes
                )
            }

        // 4. achievementCount: DayStat を fetch し day == today の completedCount
        let allStats: [DayStat]
        do {
            allStats = try context.fetch(FetchDescriptor<DayStat>())
        } catch {
            // DayStat fetch 失敗時は write せず既存の良いキャッシュを残す（達成数0の偽スナップショット防止）
            return
        }
        let achievementCount = allStats.first(where: { $0.day == today })?.completedCount ?? 0

        // 5. unconfirmedCount: TaskItem を fetch し status == .done の件数
        let unconfirmedCount = allTasks.filter { $0.status == .done }.count

        // 6. WidgetSnapshot を組み立て
        let snapshot = WidgetSnapshot(
            generatedAt: now,
            upcoming: upcoming,
            bands: bands,
            achievementCount: achievementCount,
            unconfirmedCount: unconfirmedCount
        )

        // 7. ウィジェットセンターに通知
        WidgetSnapshotStore.write(snapshot)
        WidgetCenter.shared.reloadAllTimelines()
    }
}
