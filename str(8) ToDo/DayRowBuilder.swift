//
//  DayRowBuilder.swift
//  str(8) ToDo
//
//  日ビューの行構築（枠見出し・タスク・空き・「今」の分単位マージ）。
//  SwiftUI 非依存の純粋ロジック。p1-selfcheck.swift で検証する。
//

import Foundation

/// 日ビューの1行。travel ケースは P7 で追加。
enum DayRow: Identifiable {
    case bandHeading(Band)
    case task(TaskItem)
    case gap(start: Date, duration: TimeInterval)
    case nowSeparator

    var id: String {
        switch self {
        case .bandHeading(let band):
            return "band-\(band.id.uuidString)"
        case .task(let task):
            return "task-\(task.id.uuidString)"
        case .gap(let start, _):
            return "gap-\(Int(start.timeIntervalSince1970))"
        case .nowSeparator:
            return "now"
        }
    }
}

enum DayRowBuilder {
    /// 終日タスク（先頭固定）＋ 枠見出し/時刻付きタスク/空き/「今」を
    /// 0:00 からの経過分で安定ソートしてマージした行列を返す。
    /// 同分のタイブレーク: 見出し(0) → 空き(1) → 今(2) → タスク(3)。
    static func buildRows(allDayTasks: [TaskItem], timedTasks: [TaskItem], bands: [Band],
                          now: Date?, calendar: Calendar = .current) -> [DayRow] {
        let timed = timedTasks.sorted { ($0.startDate ?? .distantPast) < ($1.startDate ?? .distantPast) }

        var entries: [(minute: Int, priority: Int, row: DayRow)] = []

        for band in bands {
            entries.append((band.startMinutes, 0, .bandHeading(band)))
        }

        // ponytail: 空きはタスク間のみ・閾値30分固定。先頭末尾や枠基準の空きが欲しくなったら拡張
        for (index, task) in timed.enumerated() {
            if index > 0,
               let prevEnd = timed[index - 1].endDate,
               let start = task.startDate {
                let gapDuration = start.timeIntervalSince(prevEnd)
                if gapDuration >= 30 * 60 {
                    entries.append((minuteOfDay(prevEnd, calendar), 1, .gap(start: prevEnd, duration: gapDuration)))
                }
            }
            if let start = task.startDate {
                entries.append((minuteOfDay(start, calendar), 3, .task(task)))
            }
        }

        if let now {
            entries.append((minuteOfDay(now, calendar), 2, .nowSeparator))
        }

        // 同 (分, 優先度) は挿入順を維持（offset を最終タイブレークに）
        let merged = entries.enumerated()
            .sorted { a, b in
                (a.element.minute, a.element.priority, a.offset) < (b.element.minute, b.element.priority, b.offset)
            }
            .map(\.element.row)

        return allDayTasks.map(DayRow.task) + merged
    }

    /// その日の 0:00 からの経過分。
    private static func minuteOfDay(_ date: Date, _ calendar: Calendar) -> Int {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }
}
