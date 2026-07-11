//
//  TaskCardView.swift
//  str8ToDo
//
//  タスクカード。DayAgendaView 用の共有コンポーネント。
//

import SwiftUI

struct TaskCardView: View {
    let task: TaskItem
    var collapsed: Bool = false
    /// true の場合、外側のコンテナ（S8Row 等）が既に hairline/padding を
    /// 提供しているので、自前の縁取りを重ねない（二重罫線防止）。
    var chromeless: Bool = false

    @Environment(\.colorScheme) private var scheme
    private var c: S8Palette { S8Palette.of(scheme) }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

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
                    .foregroundStyle(task.isDone ? c.fg3 : c.fg1)
                    .lineLimit(1)

                // 時刻範囲
                if let timeRangeText = timeRangeString() {
                    Text(timeRangeText)
                        .font(S8Font.mono(13.5))
                        .foregroundStyle(c.fg3)
                }
            }

            Spacer()

            // 右側アイコン群
            VStack(spacing: 4) {
                if task.isImportant {
                    Image(systemName: "star.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(c.accent)
                }
                if task.place != nil {
                    Image(systemName: "figure.walk")
                        .font(.system(size: 12))
                        .foregroundStyle(c.fg3)
                }
                if task.isTimePinned {
                    Text("時刻厳守")
                        .font(S8Font.mono(11)).tracking(1.5)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .foregroundStyle(c.accent)
                        .overlay(RoundedRectangle(cornerRadius: S8Radius.sm).stroke(c.accent, lineWidth: 0.5))
                        .accessibilityLabel("時刻厳守")
                }
            }
        }
        .padding(.horizontal, chromeless ? 0 : S8Space.s3)
        .padding(.vertical, chromeless ? 0 : S8Space.s5)
        .background(alignment: .top) {
            if !chromeless {
                c.line.frame(height: 1)
            }
        }
        .opacity(task.isDone ? 0.6 : 1.0)
        .accessibilityElement(children: .combine)
        .accessibilityHint("タップで詳細を表示")
    }

    private var collapsedView: some View {
        HStack(spacing: 8) {
            Text(task.title)
                .font(.caption)
                .lineLimit(1)
                .foregroundStyle(c.fg3)

            Spacer()

            if task.isDone {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(c.fg3)
            }

            Image(systemName: "chevron.down")
                .font(.system(size: 9))
                .foregroundStyle(c.fg3)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .opacity(0.45)
        .accessibilityElement(children: .combine)
        .accessibilityHint("タップで展開")
    }

    private func timeRangeString() -> String? {
        if !task.isAllDay, let startDate = task.startDate {
            let startText = Self.timeFormatter.string(from: startDate)
            if task.duration > 0 {
                let endDate = startDate.addingTimeInterval(task.duration)
                let endText = Self.timeFormatter.string(from: endDate)
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
