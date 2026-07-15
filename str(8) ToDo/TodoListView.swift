//
//  TodoListView.swift
//  str8ToDo
//
//  リストタブ本体。浮遊タスク（startDate なし・active）を 今日/いつか の2セクションで表示。
//  クイック追加・完了・日時確定でカレンダーへ昇格（一方向）。
//

import SwiftUI
import SwiftData

extension Notification.Name {
    /// ホイール中心タップ → タスク作成シートを開く。
    static let s8ListAddTask = Notification.Name("s8.list.addTask")
}

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

    private var deckIsEmpty: Bool { SortDeckEngine.deckTasks(from: allTasks).isEmpty }

    var body: some View {
        let c = self.c
        VStack(spacing: 0) {
            // ponytail: ヘッダは撤去、作成はホイール中心タップから発火。
            // クイック追加バー
            HStack(spacing: 8) {
                S8Field(placeholder: "タスクを追加", text: $quickTitle)
                S8IconButton(icon: "arrow-right", action: quickAdd)
            }
            .onSubmit(quickAdd)
            .padding(.horizontal, 24)
            .padding(.top, 12)
            .padding(.bottom, 12)

            // アクションチップ列
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    S8Chip("自然文で追加", icon: "text-cursor", action: { showQuickAddParser = true })
                    S8Chip("仕分けを始める", icon: "shuffle", selected: !deckIsEmpty, action: { showDeck = true })
                        .disabled(deckIsEmpty)
                    if !subjects.isEmpty {
                        subjectFilterChip
                    }
                }
                .padding(.horizontal, 24)
            }
            .padding(.bottom, 8)

            // リスト本体
            ScrollView {
                LazyVStack(spacing: 0) {
                    if !todayTasks.isEmpty {
                        sectionHeader("TODAY", jp: "今日")
                        ForEach(todayTasks, id: \.id) { task in taskRow(task) }
                    }
                    if !somedayTasks.isEmpty {
                        sectionHeader("SOMEDAY", jp: "いつか")
                        ForEach(somedayTasks, id: \.id) { task in taskRow(task) }
                    }
                    Color.clear.frame(height: 24)
                }
            }
        }
        // 背景はグローバル S8SamonPaper に任せる
        .sheet(item: $selectedTask) { task in
            TaskDetailView(task: task)
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
        // ホイール中心タップ → タスク作成
        .onReceive(NotificationCenter.default.publisher(for: .s8ListAddTask)) { _ in
            showComposer = true
        }
    }

    /// 科目フィルタ。S8Chip は Button そのものなので Menu の label には使わず、
    /// 同じ見た目を Menu ラベルとして描き直す（Menu > Button 入れ子の当たり判定問題を避ける）。
    private var subjectFilterChip: some View {
        let active = selectedSubjectFilter != nil
        return Menu {
            Button(action: { selectedSubjectFilter = nil }) {
                HStack {
                    Text("すべて")
                    if selectedSubjectFilter == nil { Image(systemName: "checkmark") }
                }
            }
            Divider()
            ForEach(subjects) { subject in
                Button(action: { selectedSubjectFilter = subject.id }) {
                    HStack {
                        Text(subject.name)
                        if selectedSubjectFilter == subject.id { Image(systemName: "checkmark") }
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                S8Icon(name: "filter", size: 14, color: active ? c.onAccent : c.fg2)
                Text(active ? (subjects.first { $0.id == selectedSubjectFilter }?.name ?? "科目絞込中") : "すべての科目")
                    .font(S8Font.jp(13, .medium))
                    .foregroundColor(active ? c.onAccent : c.fg2)
            }
            .padding(.horizontal, 11).padding(.vertical, 7)
            .background(active ? c.accent : .clear)
            .overlay(RoundedRectangle(cornerRadius: S8Radius.md).stroke(active ? c.accent : c.lineStrong, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: S8Radius.md))
        }
    }

    /// mono UPPERCASE caption + JP ラベルの2段セクション見出し。
    private func sectionHeader(_ tag: String, jp: String) -> some View {
        HStack(spacing: 10) {
            Text(tag).font(S8Font.mono(10)).tracking(1.6).foregroundColor(c.fg3)
            Text(jp).font(S8Font.jp(13, .medium)).foregroundColor(c.fg2)
            S8Rule()
        }
        .padding(.horizontal, 24).padding(.top, 20).padding(.bottom, 8)
    }

    /// 行タップで詳細シート、右端の2アイコンで完了/日時確定（旧 swipeActions の置換）。
    private func taskRow(_ task: TaskItem) -> some View {
        HStack(spacing: 12) {
            Circle().fill(task.effectiveColor ?? c.accent).frame(width: 6, height: 6)
            VStack(alignment: .leading, spacing: 2) {
                Text(task.title).font(S8Font.jp(15, .bold)).foregroundColor(c.fg1).lineLimit(1)
                if let snooze = task.snoozeUntil, snooze > .now {
                    Text("\(Self.snoozeFormatter.string(from: snooze)) まで先送り中")
                        .font(S8Font.jp(12)).foregroundColor(c.fg3)
                } else if task.isImportant {
                    S8Tag("STAR", icon: "star", color: c.accent)
                }
            }
            Spacer()
            HStack(spacing: 2) {
                S8IconButton(icon: "check", action: {
                    withAnimation {
                        task.markDone()
                        do { try context.save() } catch {
                            print("[TodoList] markDone save failed: \(error)")
                            assertionFailure("markDone save failed: \(error)")
                        }
                    }
                })
                .accessibilityLabel("完了")
                S8IconButton(icon: "calendar-days", action: { schedulingTask = task })
                    .accessibilityLabel("日時を決める")
            }
        }
        .padding(.horizontal, 24).padding(.vertical, 14)
        .background(c.paper)
        .overlay(alignment: .top) { S8Rule() }
        .contentShape(Rectangle())
        .onTapGesture { selectedTask = task }
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
        do {
            try context.save()
            quickTitle = ""
        } catch {
            // ponytail: 保存失敗時は入力を残す＝ユーザーが黙って消えたと誤解しない
            print("[TodoList] quickAdd save failed: \(error)")
            assertionFailure("quickAdd save failed: \(error)")
        }
    }

    // ponytail: List → ScrollView+LazyVStack 化で標準の .onMove ドラッグ並べ替えは使えなくなった。
    // 並べ替え自体は仕分けデッキ（SortDeckEngine/SortDeckView）が担うので実用上の穴は小さい。
    // 復活させるなら DragGesture + LazyVStack の手動 index 入替が必要。
}

// MARK: - 日時確定シート（カレンダーへの一方向昇格）
// ponytail: EventComposerView と日時UIが似るが2画面のサブセット関係のうちは統合しない

private struct SchedulePromoteSheet: View {
    let task: TaskItem
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    private var c: S8Palette { S8Palette.of(scheme) }

    @State private var startDate: Date = .now
    @State private var duration: TimeInterval = 3600

    var body: some View {
        let c = self.c
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                S8Button("キャンセル", icon: "x", variant: .ghost, fillWidth: false, action: { dismiss() })
                Spacer()
                Text("日時を決める").font(S8Font.jp(16, .bold)).foregroundColor(c.fg1)
                Spacer()
                S8Button("決定", icon: "check", variant: .primary, fillWidth: false, action: {
                    let effective = max(startDate, .now)
                    task.scheduleAt(start: effective, duration: duration, context: context)
                    dismiss()
                })
            }
            .padding(.horizontal, 24).padding(.vertical, 12)

            VStack(spacing: 0) {
                sectionCap("WHEN", jp: "開始")
                    .padding(.top, 8)
                HStack {
                    S8DatePicker(date: $startDate, showTime: true, minuteStep: 5)
                    Spacer()
                }
                .padding(.vertical, 12)
                .overlay(alignment: .top) { S8Rule() }

                sectionCap("DURATION", jp: "所要時間")
                    .padding(.top, 16)
                HStack {
                    Text(durationText(duration))
                        .font(S8Font.mono(15, .bold)).foregroundColor(c.fg1)
                    Spacer()
                    S8Stepper(
                        value: Binding(
                            get: { Int(duration / 60) },
                            set: { duration = TimeInterval($0) * 60 }
                        ),
                        range: 5...(24 * 60),
                        step: 5,
                        unit: "分",
                        width: 132
                    )
                }
                .padding(.vertical, 12)
                .overlay(alignment: .top) { S8Rule() }
            }
            .padding(.horizontal, 24)

            Spacer(minLength: 0)
        }
        .background(c.paper.ignoresSafeArea())
    }

    private func sectionCap(_ tag: String, jp: String) -> some View {
        HStack(spacing: 10) {
            Text(tag).font(S8Font.mono(10)).tracking(1.6).foregroundColor(c.fg3)
            Text(jp).font(S8Font.jp(13, .medium)).foregroundColor(c.fg2)
            S8Rule()
        }
        .padding(.bottom, 8)
    }
}

#Preview {
    TodoListView()
        .modelContainer(PreviewData.container)
}
