//
//  DayRowBuilder.swift
//  str8ToDo
//
//  日ビューの行構築（枠見出し・タスク・空き・「今」の分単位マージ）。
//  SwiftUI 非依存の純粋ロジック。p1-selfcheck.swift で検証する。
//

import Foundation

/// 日ビューの1行。
enum DayRow: Identifiable {
    case bandHeading(Band)
    case task(TaskItem)
    case gap(start: Date, duration: TimeInterval)
    case nowSeparator
    case sun(isSunrise: Bool, time: Date)
    case travel(task: TaskItem, departure: Date, eta: TimeInterval)

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
        case .sun(let isSunrise, let time):
            return "sun-\(isSunrise ? "rise" : "set")-\(Int(time.timeIntervalSince1970))"
        case .travel(let task, _, _):
            return "travel-\(task.id.uuidString)"
        }
    }
}

enum DayRowBuilder {
    /// 終日タスク（先頭固定）＋ 枠見出し/時刻付きタスク/空き/「今」/太陽/移動を
    /// 表示日 day の 0:00 からの経過分で安定ソートしてマージした行列を返す。
    /// 前日から跨ぐタスクは分0（0:00）位置にクランプする（時刻表示は実時刻のまま）。
    /// 同分のタイブレーク: 見出し(0) → 空き(1) → 太陽(1) → 移動(2、挿入順で今の前) → 今(2) → タスク(3)。同時刻タスクは id 昇順。
    static func buildRows(
        day: Date,
        allDayTasks: [TaskItem],
        timedTasks: [TaskItem],
        bands: [Band],
        now: Date?,
        calendar: Calendar = .current,
        sunTimes: (sunrise: Date, sunset: Date)? = nil,
        travel: [(task: TaskItem, departure: Date, eta: TimeInterval)] = []
    ) -> [DayRow] {
        let dayStart = calendar.startOfDay(for: day)
        /// day の 0:00 からの経過分（前日は負になる）。
        func minuteOfDay(_ date: Date) -> Int {
            calendar.dateComponents([.minute], from: dayStart, to: date).minute ?? 0
        }

        let timed = timedTasks.sorted {
            ($0.startDate ?? .distantPast, $0.id.uuidString) < ($1.startDate ?? .distantPast, $1.id.uuidString)
        }

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
                    let gapMinute = min(1440, max(0, minuteOfDay(prevEnd)))
                    entries.append((gapMinute, 1, .gap(start: prevEnd, duration: gapDuration)))
                }
            }
            if let start = task.startDate {
                entries.append((max(0, minuteOfDay(start)), 3, .task(task)))
            }
        }

        // 太陽位置（日の出・日の入り）
        if let sunTimes {
            let sunriseMinute = min(1440, max(0, minuteOfDay(sunTimes.sunrise)))
            entries.append((sunriseMinute, 1, .sun(isSunrise: true, time: sunTimes.sunrise)))

            let sunsetMinute = min(1440, max(0, minuteOfDay(sunTimes.sunset)))
            entries.append((sunsetMinute, 1, .sun(isSunrise: false, time: sunTimes.sunset)))
        }

        // 出発逆算（移動）
        for item in travel {
            let departureMinute = min(1440, max(0, minuteOfDay(item.departure)))
            entries.append((departureMinute, 2, .travel(task: item.task, departure: item.departure, eta: item.eta)))
        }

        if let now {
            entries.append((minuteOfDay(now), 2, .nowSeparator))
        }

        // 同 (分, 優先度) は挿入順を維持（offset を最終タイブレークに）
        let merged = entries.enumerated()
            .sorted { a, b in
                (a.element.minute, a.element.priority, a.offset) < (b.element.minute, b.element.priority, b.offset)
            }
            .map(\.element.row)

        return allDayTasks.map(DayRow.task) + merged
    }

    /// travel 再計算のトリガーキー。5分粒度で変わる（TimelineView 毎分再評価 × MKDirections 連打防止の折衷）。
    /// 実ネットワーク要求は DepartureService の30分キャッシュが抑えるので、5分ごとの再評価は実質無料。
    static func travelRefreshKey(date: Date, now: Date, calendar: Calendar = .current) -> String {
        let dayStart = calendar.startOfDay(for: date)
        return "\(dayStart.timeIntervalSinceReferenceDate)-\(Int(now.timeIntervalSinceReferenceDate / 300))"
    }
}
