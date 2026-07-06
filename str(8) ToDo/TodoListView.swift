//
//  TodoListView.swift
//  str8ToDo
//
//  リストタブ本体。浮遊タスク（startDate なし・active）を 今日/いつか の2セクションで表示。
//  クイック追加・スワイプ完了・日時確定でカレンダーへ昇格（一方向）・ドラッグ並べ替え。
//

import SwiftUI
import SwiftData

struct TodoListView: View {
    @Environment(\.modelContext) private var context
    @Query private var allTasks: [TaskItem]

    @State private var quickTitle = ""
    @State private var selectedTask: TaskItem?
    @State private var schedulingTask: TaskItem?
    @State private var showDeck = false

    /// 浮遊 active タスク（リストの対象）。
    private var floating: [TaskItem] {
        allTasks.filter { $0.startDate == nil && $0.status == .active }
    }

    private var todayTasks: [TaskItem] {
        floating.filter { $0.phase == .now || $0.phase == .today }
            .sorted { ($0.sortIndex, $0.id.uuidString) < ($1.sortIndex, $1.id.uuidString) }
    }

    private var somedayTasks: [TaskItem] {
        floating.filter { $0.phase == .week || $0.phase == .someday }
            .sorted { ($0.sortIndex, $0.id.uuidString) < ($1.sortIndex, $1.id.uuidString) }
    }

    var body: some View {
        NavigationStack {
            List {
                // クイック追加
                Section {
                    HStack(spacing: 8) {
                        TextField("タスクを追加", text: $quickTitle)
                            .onSubmit(quickAdd)
                        Button(action: quickAdd) {
                            Image(systemName: "plus.circle.fill")
                        }
                        .disabled(quickTitle.trimmingCharacters(in: .whitespaces).isEmpty)
                        .accessibilityLabel("タスクを追加")
                    }
                }

                taskSection(title: "今日", tasks: todayTasks)
                taskSection(title: "いつか", tasks: somedayTasks)
            }
            .navigationTitle("リスト")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("仕分けを始める") { showDeck = true }
                        .disabled(SortDeckEngine.deckTasks(from: allTasks).isEmpty)
                }
            }
            .sheet(item: $selectedTask) { task in
                NavigationStack {
                    TaskDetailView(task: task)
                }
            }
            .sheet(item: $schedulingTask) { task in
                SchedulePromoteSheet(task: task)
                    .presentationDetents([.medium])
            }
            .sheet(isPresented: $showDeck) {
                SortDeckView(tasks: allTasks)
            }
        }
    }

    @ViewBuilder
    private func taskSection(title: String, tasks: [TaskItem]) -> some View {
        if !tasks.isEmpty {
            Section(title) {
                ForEach(tasks, id: \.id) { task in
                    VStack(alignment: .trailing, spacing: 2) {
                        TaskCardView(task: task)
                        if let snooze = task.snoozeUntil, snooze > .now {
                            Text("\(Self.snoozeFormatter.string(from: snooze)) まで先送り中")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                        .contentShape(Rectangle())
                        .onTapGesture { selectedTask = task }
                        .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
                        .listRowSeparator(.hidden)
                        .swipeActions(edge: .leading) {
                            Button {
                                withAnimation {
                                    task.markDone()
                                    try? context.save()
                                }
                            } label: {
                                Label("完了", systemImage: "checkmark.circle")
                            }
                            .tint(.green)
                        }
                        .swipeActions(edge: .trailing) {
                            Button {
                                schedulingTask = task
                            } label: {
                                Label("日時を決める", systemImage: "calendar.badge.plus")
                            }
                            .tint(.blue)
                        }
                }
                .onMove { source, destination in
                    move(tasks, from: source, to: destination)
                }
            }
        }
    }

    // MARK: - 操作

    private static let snoozeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "M/d"
        return formatter
    }()

    private func quickAdd() {
        let title = quickTitle.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return }
        let maxIndex = floating.map(\.sortIndex).max() ?? -1
        // 「今日やる」と自分で決めたタスクを当日のデッキで再質問しないよう、当日スタンプを押す
        context.insert(TaskItem(title: title, phase: .today, sortIndex: maxIndex + 1,
                                lastSortedDay: Calendar.current.startOfDay(for: .now)))
        try? context.save()
        quickTitle = ""
    }

    /// ドラッグ並べ替え → 並べ替え後の「今日 → いつか」連結順で sortIndex を通しで振り直す
    /// （セクション間の重複・交差をなくす）。
    private func move(_ tasks: [TaskItem], from source: IndexSet, to destination: Int) {
        var reordered = tasks
        reordered.move(fromOffsets: source, toOffset: destination)
        let isTodaySection = tasks.first.map { $0.phase == .now || $0.phase == .today } ?? true
        let combined = isTodaySection ? reordered + somedayTasks : todayTasks + reordered
        for (index, task) in combined.enumerated() {
            task.sortIndex = index
        }
        try? context.save()
    }
}

// MARK: - 日時確定シート（カレンダーへの一方向昇格）
// ponytail: AddTaskSheet と日時UIが似るが2画面のサブセット関係のうちは統合しない

private struct SchedulePromoteSheet: View {
    let task: TaskItem
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var startDate: Date = .now
    @State private var duration: TimeInterval = 3600

    var body: some View {
        NavigationStack {
            Form {
                DatePicker("開始", selection: $startDate, displayedComponents: [.date, .hourAndMinute])

                HStack {
                    Text("所要時間")
                    Spacer()
                    Stepper(value: $duration, in: 300...(24 * 3600), step: 300) {
                        Text(durationText(duration))
                    }
                }
            }
            .navigationTitle("日時を決める")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("決定") {
                        task.startDate = startDate
                        task.duration = duration
                        // 浮遊時代の状態を持ち越さない
                        task.snoozeUntil = nil
                        task.lastSortedDay = nil
                        try? context.save()
                        dismiss()
                    }
                }
            }
        }
    }
}

#Preview {
    TodoListView()
        .modelContainer(PreviewData.container)
}
