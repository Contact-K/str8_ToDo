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
    @Environment(\.colorScheme) private var scheme
    private var c: S8Palette { S8Palette.of(scheme) }
    @Query private var allTasks: [TaskItem]
    @Query(sort: \Subject.name) private var subjects: [Subject]

    @State private var quickTitle = ""
    @State private var selectedTask: TaskItem?
    @State private var schedulingTask: TaskItem?
    @State private var showDeck = false
    @State private var showComposer = false
    @State private var showQuickAddParser = false
    @State private var selectedSubjectFilter: UUID? = nil

    /// 浮遊 active タスク（リストの対象）。
    private var floating: [TaskItem] {
        let base = allTasks.filter { $0.startDate == nil && $0.status == .active }
        if let filterID = selectedSubjectFilter {
            return base.filter { $0.subjectID == filterID }
        }
        return base
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
                    Button(action: { showComposer = true }) {
                        Label("詳細を追加", systemImage: "square.and.pencil")
                    }
                    .font(S8Font.jp(15, .medium))
                    .foregroundStyle(c.fg2)
                    // P16: 自然文1行入力（日時/場所/カテゴリ/所要時間を自動認識）
                    Button(action: { showQuickAddParser = true }) {
                        Label("自然文で追加", systemImage: "text.badge.plus")
                    }
                    .font(S8Font.jp(15, .medium))
                    .foregroundStyle(c.fg2)
                }
                .listRowBackground(c.paper)

                taskSection(title: "今日", tasks: todayTasks)
                taskSection(title: "いつか", tasks: somedayTasks)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(c.paper)
            .navigationTitle("リスト")
            .toolbar {
                ToolbarItem(placement: .secondaryAction) {
                    if !subjects.isEmpty {
                        Menu {
                            Button(action: { selectedSubjectFilter = nil }) {
                                HStack {
                                    Text("すべて")
                                    if selectedSubjectFilter == nil {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                            Divider()
                            ForEach(subjects) { subject in
                                Button(action: { selectedSubjectFilter = subject.id }) {
                                    HStack {
                                        Label(subject.name, systemImage: "circle.fill")
                                            .foregroundColor(Color(hex: subject.colorHex))
                                        if selectedSubjectFilter == subject.id {
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                            }
                        } label: {
                            Image(systemName: "funnel")
                        }
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("仕分けを始める") { showDeck = true }
                        .disabled(SortDeckEngine.deckTasks(from: allTasks).isEmpty)
                        .font(S8Font.jp(15, .semibold))
                        .foregroundStyle(c.fg1)
                        .padding(.vertical, S8Space.s3 + 2)
                        .padding(.horizontal, S8Space.s4 + 4)
                        .overlay(RoundedRectangle(cornerRadius: S8Radius.md).stroke(c.lineStrong, lineWidth: 1))
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
            .sheet(isPresented: $showComposer) {
                EventComposerView()
            }
            .sheet(isPresented: $showQuickAddParser) {
                QuickAddParserView()
            }
        }
    }

    /// PLAIN: セクション見出しを mono UPPERCASE caption + JP ラベルの2段で表示。
    private static let sectionTag: [String: String] = ["今日": "TODAY", "いつか": "SOMEDAY"]

    private func sectionHeader(_ title: String) -> some View {
        Text("\(Self.sectionTag[title] ?? title) / \(title)")
            .font(S8Font.mono(11)).tracking(1.5)
            .textCase(.uppercase)
            .foregroundStyle(c.fg3)
    }

    @ViewBuilder
    private func taskSection(title: String, tasks: [TaskItem]) -> some View {
        if !tasks.isEmpty {
            Section(header: sectionHeader(title)) {
                ForEach(tasks, id: \.id) { task in
                    // ponytail: S8Components に相当ロウがないので RuledListRow をここへ inline 移植。
                    HStack(spacing: 0) {
                        Rectangle()
                            .fill(selectedTask?.id == task.id ? c.accent : Color.clear)
                            .frame(width: 5)
                        VStack(alignment: .trailing, spacing: 2) {
                            TaskCardView(task: task, chromeless: true)
                            if let snooze = task.snoozeUntil, snooze > .now {
                                Text("\(Self.snoozeFormatter.string(from: snooze)) まで先送り中")
                                    .font(S8Font.mono(13.5))
                                    .foregroundStyle(c.fg3)
                            }
                        }
                        .padding(.vertical, 19)
                        .padding(.horizontal, 26)
                    }
                    .background(alignment: .top) { c.line.frame(height: 1) }
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(c.paper)
                        .contentShape(Rectangle())
                        .onTapGesture { selectedTask = task }
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
// ponytail: EventComposerView と日時UIが似るが2画面のサブセット関係のうちは統合しない

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
                        // ponytail: sheet を開いたまま時間が経過→過去時刻がコミットされる問題を回避。
                        // 押下時に startDate が過去なら現時刻へシフト。
                        let effective = max(startDate, .now)
                        task.scheduleAt(start: effective, duration: duration, context: context)
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
