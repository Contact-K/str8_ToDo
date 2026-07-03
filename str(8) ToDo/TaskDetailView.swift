//
//  TaskDetailView.swift
//  str8ToDo
//
//  タスク詳細表示・編集画面。承認フロー＋スター切替＋削除操作。
//

import SwiftUI
import SwiftData

struct TaskDetailView: View {
    let task: TaskItem

    @Environment(\.modelContext) var modelContext
    @Environment(\.dismiss) var dismiss

    @State private var showDeleteConfirmation = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // MARK: - ヘッダ
                headerSection

                // MARK: - 時間セクション
                if task.startDate != nil || task.rrule != nil || task.timeZoneIdentifier != nil {
                    timeSection
                }

                // MARK: - カテゴリ・場所
                if task.category != nil || task.place != nil {
                    metadataSection
                }

                // MARK: - 通知
                notificationSection

                // MARK: - メモ
                if !task.notes.isEmpty {
                    notesSection
                }

                // MARK: - 承認フロー & アクション
                approvalSection

                Spacer()
            }
            .padding()
        }
        .navigationTitle("詳細")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: toggleImportant) {
                    Image(systemName: task.isImportant ? "star.fill" : "star")
                        .foregroundColor(task.isImportant ? .yellow : .gray)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button(role: .destructive, action: { showDeleteConfirmation = true }) {
                    Image(systemName: "trash")
                }
            }
        }
        .confirmationDialog(
            "削除確認",
            isPresented: $showDeleteConfirmation,
            actions: {
                Button("削除", role: .destructive) {
                    deleteTask()
                }
            },
            message: {
                Text("\"\(task.title)\" を削除しますか？")
            }
        )
    }

    // MARK: - Header Section
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                // ドットインジケーター
                Circle()
                    .fill(task.effectiveColor)
                    .frame(width: 12, height: 12)
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(task.title)
                            .font(.title2)
                            .fontWeight(.semibold)
                            .lineLimit(2)

                        if task.isImportant {
                            Image(systemName: "star.fill")
                                .foregroundColor(.yellow)
                                .font(.callout)
                        }
                    }

                    statusBadge
                }
                Spacer()
            }
        }
    }

    private var statusBadge: some View {
        HStack(spacing: 6) {
            Image(systemName: task.status.systemImage)
            Text(task.status.label)
        }
        .font(.caption)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(task.status.tint.opacity(0.2))
        .foregroundColor(task.status.tint)
        .cornerRadius(6)
    }

    // MARK: - Time Section
    private var timeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("スケジュール")
                .font(.headline)
                .foregroundColor(.secondary)

            VStack(alignment: .leading, spacing: 6) {
                if task.isAllDay {
                    HStack {
                        Image(systemName: "calendar")
                            .foregroundColor(.blue)
                        Text("終日")
                            .font(.subheadline)
                    }
                } else if let startDate = task.startDate {
                    HStack {
                        Image(systemName: "clock")
                            .foregroundColor(.blue)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("開始: \(formatDate(startDate))")
                                .font(.subheadline)
                            if let endDate = task.endDate {
                                Text("終了: \(formatDate(endDate))")
                                    .font(.subheadline)
                            }
                            Text("所要: \(formatDuration(task.duration))")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                if let rrule = task.rrule, !rrule.isEmpty {
                    HStack {
                        Image(systemName: "repeat")
                            .foregroundColor(.blue)
                        Text(simplifyRRule(rrule))
                            .font(.subheadline)
                    }
                }

                if let tzId = task.timeZoneIdentifier, !tzId.isEmpty {
                    HStack {
                        Image(systemName: "globe")
                            .foregroundColor(.blue)
                        Text(tzId)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }

    // MARK: - Metadata Section
    private var metadataSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let category = task.category {
                HStack {
                    Image(systemName: category.symbolName)
                        .foregroundColor(Color(hex: category.colorHex))
                    Text(category.name)
                        .font(.subheadline)
                    Spacer()
                }
                .padding(.vertical, 4)
            }

            if let place = task.place, !place.name.isEmpty {
                HStack {
                    Image(systemName: "mappin.circle.fill")
                        .foregroundColor(.red)
                    Text(place.name)
                        .font(.subheadline)
                    Spacer()
                }
                .padding(.vertical, 4)
            }
        }
    }

    // MARK: - Notification Section
    private var notificationSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("通知")
                .font(.headline)
                .foregroundColor(.secondary)

            if task.notificationOffsets.isEmpty {
                HStack {
                    Image(systemName: "bell.slash")
                        .foregroundColor(.gray)
                    Text("なし")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(task.notificationOffsets.sorted(), id: \.self) { offset in
                        HStack {
                            Image(systemName: "bell.fill")
                                .foregroundColor(.orange)
                            Text(formatNotificationOffset(offset))
                                .font(.subheadline)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Notes Section
    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("メモ")
                .font(.headline)
                .foregroundColor(.secondary)

            Text(task.notes)
                .font(.subheadline)
                .lineLimit(nil)
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .background(Color(.systemGray6))
                .cornerRadius(8)
        }
    }

    // MARK: - Approval Section
    private var approvalSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("操作")
                .font(.headline)
                .foregroundColor(.secondary)

            if task.isAwaitingFutureSelf {
                HStack {
                    Image(systemName: "hourglass.end")
                        .foregroundColor(.orange)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("未来の自分待ち")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        if let unlockDate = task.unlockDate {
                            Text(formatDate(unlockDate) + " に承認可能")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    Spacer()
                }
                .padding()
                .background(Color.orange.opacity(0.1))
                .cornerRadius(8)
            } else {
                VStack(spacing: 10) {
                    switch task.status {
                    case .incomplete:
                        Button(action: markPending) {
                            HStack {
                                Image(systemName: "checkmark.circle")
                                Text("完了にする")
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(8)
                        }

                    case .pending:
                        Button(action: approve) {
                            HStack {
                                Image(systemName: "checkmark.seal")
                                Text("承認する")
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.green)
                            .foregroundColor(.white)
                            .cornerRadius(8)
                        }

                    case .approved:
                        HStack {
                            Image(systemName: "checkmark.seal.fill")
                                .foregroundColor(.green)
                            Text("承認済み ✓")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                            Spacer()
                        }
                        .padding()
                        .background(Color.green.opacity(0.1))
                        .cornerRadius(8)
                    }
                }
            }
        }
    }

    // MARK: - Actions
    private func toggleImportant() {
        task.isImportant.toggle()
        save()
    }

    private func markPending() {
        task.markPending(soloUnlockDate: TaskItem.nextMidnight())
        save()
    }

    private func approve() {
        task.approve(by: "self-future")
        save()
    }

    private func deleteTask() {
        modelContext.delete(task)
        NotificationService.cancel(for: task)
        save()
        dismiss()
    }

    private func save() {
        do {
            try modelContext.save()
        } catch {
            print("Save error: \(error.localizedDescription)")
        }
    }

    // MARK: - Formatting Helpers
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.locale = Locale(identifier: "ja_JP")
        return formatter.string(from: date)
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds / 60)
        if minutes < 60 {
            return "\(minutes)分"
        }
        let hours = minutes / 60
        let mins = minutes % 60
        if mins == 0 {
            return "\(hours)時間"
        }
        return "\(hours)時間\(mins)分"
    }

    private func simplifyRRule(_ rrule: String) -> String {
        // 簡易実装：FREQ から抽出
        if rrule.contains("FREQ=DAILY") {
            return "毎日"
        } else if rrule.contains("FREQ=WEEKLY") {
            return "毎週"
        } else if rrule.contains("FREQ=MONTHLY") {
            return "毎月"
        } else if rrule.contains("FREQ=YEARLY") {
            return "毎年"
        }
        return rrule
    }

    private func formatNotificationOffset(_ offset: Int) -> String {
        let minutes = offset

        if minutes < 60 {
            return "\(minutes)分前"
        } else if minutes < 1440 {
            let hours = minutes / 60
            return "\(hours)時間前"
        } else if minutes == 1440 {
            return "前日"
        } else {
            let days = minutes / 1440
            return "\(days)日前"
        }
    }
}

// MARK: - Preview
#Preview {
    NavigationStack {
        TaskDetailView(task: TaskItem(title: "サンプルタスク"))
    }
}
