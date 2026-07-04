//
//  TaskCardView.swift
//  str(8) ToDo
//
//  タスクカード。DayAgendaView 用の共有コンポーネント。
//

import SwiftUI

struct TaskCardView: View {
    let task: TaskItem
    var collapsed: Bool = false

    var body: some View {
        if collapsed {
            collapsedView
        } else {
            normalView
        }
    }

    private var normalView: some View {
        HStack(spacing: 12) {
            // 左側カラーバー
            Rectangle()
                .fill(task.effectiveColor)
                .frame(width: 4)

            VStack(alignment: .leading, spacing: 4) {
                // タイトル
                Text(task.title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .strikethrough(task.isDone)
                    .lineLimit(1)

                // 時刻範囲
                if let timeRangeText = timeRangeString() {
                    Text(timeRangeText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            // 右側アイコン群
            VStack(spacing: 4) {
                if task.isImportant {
                    Image(systemName: "star.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.yellow)
                }
                if task.place != nil {
                    Image(systemName: "figure.walk")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                if task.isTimePinned {
                    Text("時刻厳守")
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .border(Color.secondary, width: 0.5)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
        .opacity(task.isDone ? 0.6 : 1.0)
    }

    private var collapsedView: some View {
        HStack(spacing: 8) {
            Text(task.title)
                .font(.caption)
                .lineLimit(1)
                .foregroundStyle(.secondary)

            Spacer()

            if task.isDone {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .opacity(0.45)
    }

    private func timeRangeString() -> String? {
        if !task.isAllDay, let startDate = task.startDate {
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm"
            let startText = formatter.string(from: startDate)
            if task.duration > 0 {
                let endDate = startDate.addingTimeInterval(task.duration)
                let endText = formatter.string(from: endDate)
                return "\(startText) - \(endText)"
            } else {
                return startText
            }
        } else if task.isAllDay {
            return "終日"
        }
        return nil
    }
}

#Preview {
    VStack(spacing: 12) {
        TaskCardView(task: PreviewData.sampleTask1())
        TaskCardView(task: PreviewData.sampleTask2(), collapsed: false)
        TaskCardView(task: PreviewData.sampleTask3(), collapsed: true)
    }
    .padding()
    .modelContainer(PreviewData.container)
}

extension PreviewData {
    static func sampleTask1() -> TaskItem {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        let start = cal.date(bySettingHour: 10, minute: 0, second: 0, of: today)!
        return TaskItem(
            title: "線形代数の課題",
            category: nil,
            startDate: start,
            duration: 3600,
            phase: .today,
            status: .active
        )
    }

    static func sampleTask2() -> TaskItem {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        let start = cal.date(bySettingHour: 14, minute: 0, second: 0, of: today)!
        return TaskItem(
            title: "会議",
            category: nil,
            startDate: start,
            duration: 1800,
            phase: .today,
            status: .active,
            isImportant: true,
            isTimePinned: true
        )
    }

    static func sampleTask3() -> TaskItem {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        let start = cal.date(bySettingHour: 15, minute: 30, second: 0, of: today)!
        return TaskItem(
            title: "完了済みタスク",
            category: nil,
            startDate: start,
            duration: 900,
            phase: .today,
            status: .done,
            completedAt: .now
        )
    }
}
