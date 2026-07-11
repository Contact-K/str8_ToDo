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
        // ponytail: アプリ本体の日アジェンダ（DayAgendaView.dayTasks / nextFutureTask）と同じ同日 startDate 判定に合わせる。
        // RRULE の当日インスタンス展開は日ビュー自体が未対応の全体課題で、ここだけ occurs(on:) 展開するとアプリと乖離するため意図的に不採用。
        let upcoming = allTasks
            .filter { task in
                // status == .active
                guard task.status == .active else { return false }
                // startDate != nil && !isAllDay
                guard let startDate = task.startDate, !task.isAllDay else { return false }
                // same day as today
                guard Calendar.current.isDate(startDate, inSameDayAs: today) else { return false }
                // endDate > now
                guard let endDate = task.endDate, endDate > now else { return false }
                return true
            }
            .sorted { ($0.startDate ?? now) < ($1.startDate ?? now) }
            .map { task in
                WidgetSnapshot.Card(
                    title: task.title,
                    start: task.startDate ?? now,
                    end: task.endDate ?? now,
                    colorHex: task.colorHex ?? task.category?.colorHex,
                    isTimePinned: task.isTimePinned
                )
            }

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
        let allStats = (try? context.fetch(FetchDescriptor<DayStat>())) ?? []
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
