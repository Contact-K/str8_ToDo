import SwiftUI
import SwiftData

struct DayView: View {
    @Binding var date: Date
    var morph: Namespace.ID? = nil
    var categoryFilter: Set<UUID>? = nil
    var onSelectTask: ((TaskItem) -> Void)? = nil

    @Environment(\.modelContext) private var context
    @Query private var allTasks: [TaskItem]

    @State private var showAddTaskSheet = false

    private let hourHeight: CGFloat = 60
    private let timelineLeftWidth: CGFloat = 44

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                // Navigation header
                HStack {
                    Button(action: { date = Calendar.current.date(byAdding: .day, value: -1, to: date) ?? date }) {
                        Image(systemName: "chevron.left")
                            .font(.body)
                            .foregroundStyle(.primary)
                    }

                    Spacer()

                    Text(dayHeaderText())
                        .font(.headline)

                    Spacer()

                    Button(action: { date = Calendar.current.date(byAdding: .day, value: 1, to: date) ?? date }) {
                        Image(systemName: "chevron.right")
                            .font(.body)
                            .foregroundStyle(.primary)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color(.systemGray6))

                // Weather placeholder bar
                HStack(spacing: 8) {
                    Image(systemName: "cloud.sun")
                        .font(.system(size: 14))
                        .foregroundStyle(.orange)
                    Text("天気（P2で接続）")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color(.systemGray5))
                .cornerRadius(8)
                .padding(12)

                // All-day tasks section
                let allDayTasks = tasksForDay.filter { $0.isAllDay }
                if !allDayTasks.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(allDayTasks, id: \.id) { task in
                            if let morph = morph {
                                DayTaskChip(task: task, onTap: { handleTaskTap(task) })
                                    .matchedGeometryEffect(id: "evt-\(task.id.uuidString)", in: morph, isSource: true)
                            } else {
                                DayTaskChip(task: task, onTap: { handleTaskTap(task) })
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
                }

                // Timeline scroll view
                ScrollView {
                    ZStack(alignment: .topLeading) {
                        // Grid lines and time labels
                        VStack(spacing: 0) {
                            ForEach(0..<24, id: \.self) { hour in
                                VStack(spacing: 0) {
                                    HStack(spacing: 0) {
                                        Text(String(format: "%02d:00", hour))
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                            .frame(width: timelineLeftWidth, alignment: .trailing)
                                            .padding(.trailing, 8)

                                        Divider()
                                            .frame(maxWidth: .infinity)
                                            .foregroundStyle(.separator)
                                    }
                                    .frame(height: hourHeight)
                                }
                            }
                        }

                        // Timed tasks
                        let timedTasks = tasksForDay.filter { !$0.isAllDay && $0.startDate != nil }
                        ForEach(timedTasks, id: \.id) { task in
                            if let morph = morph {
                                DayTaskBlock(
                                    task: task,
                                    hourHeight: hourHeight,
                                    timelineLeftWidth: timelineLeftWidth,
                                    onTap: { handleTaskTap(task) }
                                )
                                .offset(y: calculateTaskOffset(for: task))
                                .matchedGeometryEffect(id: "evt-\(task.id.uuidString)", in: morph, isSource: true)
                            } else {
                                DayTaskBlock(
                                    task: task,
                                    hourHeight: hourHeight,
                                    timelineLeftWidth: timelineLeftWidth,
                                    onTap: { handleTaskTap(task) }
                                )
                                .offset(y: calculateTaskOffset(for: task))
                            }
                        }
                    }
                    .frame(minHeight: hourHeight * 24)
                }
                .frame(maxHeight: .infinity)
            }

            // Floating + button
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    Button(action: { showAddTaskSheet = true }) {
                        Image(systemName: "plus")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 56, height: 56)
                            .background(Color.blue)
                            .clipShape(Circle())
                            .shadow(radius: 4)
                    }
                    .padding(20)
                }
            }
        }
        .sheet(isPresented: $showAddTaskSheet) {
            AddTaskSheet(defaultDate: date)
        }
    }

    // MARK: - Helpers

    private var tasksForDay: [TaskItem] {
        let calendar = Calendar.current
        let targetKey = dayKey(date, calendar)
        return allTasks.filter { task in
            let isSameDay: Bool
            if task.isAllDay {
                if let startDate = task.startDate {
                    isSameDay = dayKey(startDate, calendar) == targetKey
                } else {
                    return false
                }
            } else {
                if let startDate = task.startDate {
                    isSameDay = dayKey(startDate, calendar) == targetKey
                } else {
                    return false
                }
            }

            guard isSameDay else { return false }

            if let filter = categoryFilter {
                let categoryId = task.category?.id ?? UUID()
                return filter.contains(categoryId)
            }
            return true
        }
    }

    private func dayHeaderText() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "M月d日 (E)"
        formatter.locale = Locale(identifier: "ja_JP")
        return formatter.string(from: date)
    }

    private func calculateTaskOffset(for task: TaskItem) -> CGFloat {
        guard let startDate = task.startDate else { return 0 }
        let calendar = Calendar.current
        let components = calendar.dateComponents([.hour, .minute], from: startDate)
        let hour = CGFloat(components.hour ?? 0)
        let minute = CGFloat(components.minute ?? 0)
        return (hour + minute / 60) * hourHeight
    }

    private func handleTaskTap(_ task: TaskItem) {
        onSelectTask?(task)
    }
}

// MARK: - Task Block Component

struct DayTaskBlock: View {
    let task: TaskItem
    let hourHeight: CGFloat
    let timelineLeftWidth: CGFloat
    let onTap: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text(task.title)
                    .font(.caption)
                    .fontWeight(.medium)
                    .lineLimit(1)
                    .strikethrough(task.isDone)

                if task.isImportant {
                    Image(systemName: "star.fill")
                        .font(.system(size: 8))
                        .foregroundStyle(.yellow)
                }

                if task.place != nil {
                    Image(systemName: "figure.walk")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .padding(.horizontal, 6)
            .padding(.top, 4)

            if !task.title.isEmpty {
                HStack(spacing: 6) {
                    Text(timeRangeText())
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    if task.place != nil {
                        HStack(spacing: 2) {
                            Image(systemName: "figure.walk")
                                .font(.system(size: 9))
                            Text("出発(P2)")
                                .font(.caption2)
                        }
                        .foregroundStyle(.orange)
                    }

                    Spacer()
                }
                .padding(.horizontal, 6)
                .padding(.bottom, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: taskBlockHeight())
        .background(task.effectiveColor.opacity(task.isDone ? 0.4 : 0.8))
        .cornerRadius(6)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(task.effectiveColor, lineWidth: 1)
        )
        .opacity(task.isDone ? 0.6 : 1.0)
        .padding(.horizontal, 12)
        .offset(x: timelineLeftWidth + 12)
        .onTapGesture(perform: onTap)
    }

    private func taskBlockHeight() -> CGFloat {
        let minHeight: CGFloat = 22
        let calculatedHeight = (task.duration / 3600) * hourHeight
        return max(calculatedHeight, minHeight)
    }

    private func timeRangeText() -> String {
        guard let startDate = task.startDate else { return "" }
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        let startText = formatter.string(from: startDate)

        if task.duration > 0 {
            let endDate = startDate.addingTimeInterval(task.duration)
            let endText = formatter.string(from: endDate)
            return "\(startText) - \(endText)"
        }
        return startText
    }
}

// MARK: - All-day Task Chip

struct DayTaskChip: View {
    let task: TaskItem
    let onTap: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            if let category = task.category {
                Circle()
                    .fill(Color(hex: category.colorHex))
                    .frame(width: 10, height: 10)
            }

            Text(task.title)
                .font(.caption)
                .lineLimit(1)
                .strikethrough(task.isDone)

            if task.isImportant {
                Image(systemName: "star.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(.yellow)
            }

            Image(systemName: task.status.systemImage)
                .font(.system(size: 10))

            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color(.systemGray5))
        .cornerRadius(4)
        .opacity(task.isDone ? 0.6 : 1.0)
        .onTapGesture(perform: onTap)
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        DayView(date: .constant(.now))
    }
    .modelContainer(PreviewData.container)
}
