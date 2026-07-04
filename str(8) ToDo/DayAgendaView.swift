//
//  DayAgendaView.swift
//  str(8) ToDo
//
//  カード式アジェンダ。行の並べ替えロジックは DayRowBuilder（純粋関数）に集約し、
//  ここは SwiftData からのタスク取得と表示だけを担う。
//

import SwiftUI
import SwiftData

struct DayAgendaView: View {
    let date: Date
    var morph: Namespace.ID? = nil
    var categoryFilter: Set<UUID>? = nil
    var onSelectTask: ((TaskItem) -> Void)? = nil
    var onTapGap: ((Date, TimeInterval) -> Void)? = nil

    @Environment(\.modelContext) private var context
    @Query private var allTasks: [TaskItem]
    @State private var expandedIDs: Set<UUID> = []

    private let cal = Calendar.current

    var body: some View {
        let isToday = cal.isDateInToday(date)
        let rows = buildRows(isToday: isToday)

        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(rows) { row in
                        switch row {
                        case .bandHeading(let band):
                            bandHeadingRow(band)
                                .id(row.id)

                        case .task(let task):
                            let isPast = isPastTask(task)
                            let isCollapsed = isPast && !expandedIDs.contains(task.id)

                            taskRow(task, collapsed: isCollapsed)
                                .id(row.id)
                                .onTapGesture {
                                    if isCollapsed {
                                        expandedIDs.insert(task.id)
                                    } else {
                                        onSelectTask?(task)
                                    }
                                }

                        case .gap(let start, let duration):
                            gapRow(start: start, duration: duration)
                                .id(row.id)
                                .onTapGesture {
                                    onTapGap?(start, duration)
                                }

                        case .nowSeparator:
                            nowSeparatorRow()
                                .id(row.id)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
            }
            .onAppear {
                if isToday {
                    proxy.scrollTo("now", anchor: .center)
                }
            }
        }
    }

    // MARK: - 行構築（マージは DayRowBuilder に委譲）

    private func buildRows(isToday: Bool) -> [DayRow] {
        let tasks = dayTasks()
        let bands = BandAssignment.resolveTemplate(for: date, context: context, calendar: cal)?.orderedBands ?? []
        return DayRowBuilder.buildRows(
            allDayTasks: tasks.filter { $0.isAllDay },
            timedTasks: tasks.filter { !$0.isAllDay && $0.startDate != nil },
            bands: bands,
            now: isToday ? .now : nil,
            calendar: cal
        )
    }

    /// その日のタスク（startDate が同日、カテゴリフィルタ通過。category nil のタスクはフィルタ時除外）。
    private func dayTasks() -> [TaskItem] {
        allTasks.filter { task in
            guard let start = task.startDate, cal.isDate(start, inSameDayAs: date) else { return false }
            if let filter = categoryFilter {
                guard let catID = task.category?.id, filter.contains(catID) else { return false }
            }
            return true
        }
    }

    /// 当日で、終了予定（なければ開始）が現在より過去のタスク。
    private func isPastTask(_ task: TaskItem) -> Bool {
        guard cal.isDateInToday(date) else { return false }
        let endDate = task.endDate ?? task.startDate ?? date
        return endDate < Date.now
    }

    /// 当日の時刻付き未来タスクのうち最初のもの（「次の予定まであと◯分」用）。
    private func nextFutureTask() -> TaskItem? {
        dayTasks()
            .filter { !$0.isAllDay && $0.startDate != nil }
            .sorted { ($0.startDate ?? .distantPast) < ($1.startDate ?? .distantPast) }
            .first { ($0.startDate ?? date) > Date.now }
    }

    // MARK: - 行表示

    private func bandHeadingRow(_ band: Band) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(band.name)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)

                Text(formatTimeRange(from: band.startMinutes, to: band.endMinutes))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()
            }

            Divider()
        }
        .padding(.horizontal, 8)
    }

    private func taskRow(_ task: TaskItem, collapsed: Bool) -> some View {
        let card = TaskCardView(task: task, collapsed: collapsed)

        if let morph = morph {
            return AnyView(
                card.matchedGeometryEffect(id: "evt-\(task.id.uuidString)", in: morph, isSource: true)
            )
        } else {
            return AnyView(card)
        }
    }

    private func gapRow(start: Date, duration: TimeInterval) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("空き")
                    .font(.caption)
                    .fontWeight(.semibold)

                Text(formatDurationShort(duration))
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Text("+ タスクを置く")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [2]))
        )
        .background(Color(.systemBackground))
        .cornerRadius(8)
    }

    private func nowSeparatorRow() -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Rectangle()
                    .fill(Color.accentColor)
                    .frame(height: 1)

                Text("今")
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.accentColor)

                Rectangle()
                    .fill(Color.accentColor)
                    .frame(height: 1)
            }

            if let nextTask = nextFutureTask() {
                let mins = Int((nextTask.startDate ?? date).timeIntervalSince(.now) / 60)
                if mins > 0 {
                    Text("次の予定まであと\(mins)分")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - ヘルパー

    private func formatTimeRange(from startMin: Int, to endMin: Int) -> String {
        String(format: "%02d:%02d–%02d:%02d", startMin / 60, startMin % 60, endMin / 60, endMin % 60)
    }

    private func formatDurationShort(_ duration: TimeInterval) -> String {
        let totalMinutes = Int(duration / 60)
        if totalMinutes >= 60 {
            return String(format: "%.1fh", Double(totalMinutes) / 60)
        }
        return "\(totalMinutes)分"
    }
}

#Preview {
    DayAgendaView(date: Calendar.current.startOfDay(for: .now))
        .modelContainer(PreviewData.container)
}
