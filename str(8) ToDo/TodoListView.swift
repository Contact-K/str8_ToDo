//
//  TodoListView.swift
//  str8ToDo
//
//  リストタブ本体。Phase 17 で承認タブを統合：
//    浮遊タスク（startDate なし・active）を TODAY / SOMEDAY
//    完了済み（status == .done）を LOCKED / READY
//  実機では ChopMotionService で物理ハンコの検出に対応（READY 内でのみ発動）。
//

import SwiftUI
import SwiftData

#if canImport(CoreMotion) && os(iOS)
import CoreMotion
#endif

extension Notification.Name {
    /// ホイール中心タップ → タスク作成シートを開く。
    static let s8ListAddTask = Notification.Name("s8.list.addTask")
}

@MainActor
struct TodoListView: View {
    /// 統合前は ApprovalQueueView から親へ委譲していた週レビュー起動。
    @Binding var showWeekReview: Bool
    /// P2P セッションは ContentView が所有し、ここへ渡される（Phase 17 統合前は Approval が保持）。
    let peerSession: PeerSession

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
    @State private var showPeerPairing = false
    @State private var proximityGate = ProximityGate()
    @State private var searchQuery: String = ""
    @State private var showSearch: Bool = false

    #if canImport(CoreMotion) && os(iOS)
    @State private var chopService = ChopMotionService()
    #endif

    init(showWeekReview: Binding<Bool>, peerSession: PeerSession) {
        self._showWeekReview = showWeekReview
        self.peerSession = peerSession
    }

    // MARK: - 派生セット

    /// 浮遊 active タスク（リストの対象）。
    private var floating: [TaskItem] {
        let base = allTasks.filter { $0.startDate == nil && $0.status == .active }
        let filtered: [TaskItem]
        if let filterID = selectedSubjectFilter {
            filtered = base.filter { $0.subjectID == filterID }
        } else {
            filtered = base
        }
        return applySearch(filtered)
    }

    private var todayTasks: [TaskItem] {
        floating.filter { $0.phase == .now || $0.phase == .today }
            .sorted { ($0.sortIndex, $0.id.uuidString) < ($1.sortIndex, $1.id.uuidString) }
    }

    private var somedayTasks: [TaskItem] {
        floating.filter { $0.phase == .week || $0.phase == .someday }
            .sorted { ($0.sortIndex, $0.id.uuidString) < ($1.sortIndex, $1.id.uuidString) }
    }

    private var doneTasks: [TaskItem] {
        applySearch(allTasks.filter { $0.status == .done })
    }
    private var lockedTasks: [TaskItem] { doneTasks.filter { $0.isAwaitingFutureSelf } }
    private var readyTasks: [TaskItem] { doneTasks.filter { !$0.isAwaitingFutureSelf } }

    private var deckIsEmpty: Bool { SortDeckEngine.deckTasks(from: allTasks).isEmpty }

    /// Phase 17: title + notes を .localizedStandardContains で filter。空クエリはそのまま返す。
    private func applySearch(_ tasks: [TaskItem]) -> [TaskItem] {
        let q = searchQuery.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return tasks }
        return tasks.filter {
            $0.title.localizedStandardContains(q) || $0.notes.localizedStandardContains(q)
        }
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            if showSearch {
                S8Field(placeholder: "タスク名 / メモを検索", text: $searchQuery)
                    .padding(.horizontal, 24).padding(.top, 4).padding(.bottom, 8)
            }

            // クイック追加バー
            HStack(spacing: 8) {
                S8Field(placeholder: "タスクを追加", text: $quickTitle)
                S8IconButton(icon: "arrow-right", action: quickAdd)
            }
            .onSubmit(quickAdd)
            .padding(.horizontal, 24)
            .padding(.top, 4)
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
                    if !lockedTasks.isEmpty {
                        sectionHeader("LOCKED", jp: "ロック中")
                        ForEach(lockedTasks, id: \.id) { task in lockedRow(task) }
                    }
                    if !readyTasks.isEmpty {
                        sectionHeader("READY", jp: "承認待ち")
                        ForEach(readyTasks, id: \.id) { task in readyRow(task) }
                        #if canImport(CoreMotion) && os(iOS)
                        chopMeter
                            .padding(.horizontal, 24).padding(.top, 22)
                        #endif
                    }
                    Color.clear.frame(height: 24)
                }
            }
        }
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
        .sheet(isPresented: $showPeerPairing) {
            NavigationStack {
                PeerPairingView(session: peerSession, gate: proximityGate)
            }
        }
        // ホイール中心タップ → タスク作成
        .onReceive(NotificationCenter.default.publisher(for: .s8ListAddTask)) { _ in
            showComposer = true
        }
        #if canImport(CoreMotion) && os(iOS)
        // Phase 17: chop は統合ビュー全体で active。onChop の中で readyTasks を都度参照して
        // nil のときは no-op（READY セクションが空でも安全に空振り）。
        .onAppear {
            chopService.onChop = {
                if let first = allTasks.first(where: { $0.status == .done && !$0.isAwaitingFutureSelf }) {
                    _ = first.approve(by: "self-future", context: context)
                    try? context.save()
                }
            }
            chopService.start()
        }
        .onDisappear {
            chopService.stop()
        }
        #endif
        .onAppear {
            // Phase 17: ペアセッション handler もこちらへ移設
            peerSession.onApproved = { taskID, senderName in
                if let task = allTasks.first(where: { $0.id == taskID }) {
                    _ = task.approve(by: senderName, context: context, bypassesLock: true)
                    try? context.save()
                }
            }
            peerSession.onNIToken = { data in
                if data.isEmpty {
                    proximityGate.startFallback()
                } else {
                    proximityGate.start(withPeerToken: data)
                }
            }
            peerSession.onPeerConnected = { _ in
                peerSession.send(.niToken(proximityGate.localTokenData ?? Data()))
            }
        }
    }

    // MARK: - Header bar（Phase 17: 検索 + 今週を締める + P2P）

    private var headerBar: some View {
        HStack(spacing: 8) {
            S8Button("今週を締める", icon: "calendar-days", variant: .secondary, fillWidth: false, action: { showWeekReview = true })
            Spacer()
            S8IconButton(icon: "search", accent: showSearch, action: {
                withAnimation(.easeOut(duration: 0.15)) {
                    showSearch.toggle()
                    if !showSearch { searchQuery = "" }
                }
            })
            .accessibilityLabel("検索")
            S8IconButton(icon: "users", accent: peerSession.isConnected, action: { showPeerPairing = true })
                .accessibilityLabel("ペアリング")
        }
        .padding(.horizontal, 24).padding(.top, 12).padding(.bottom, 8)
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

    /// TODAY / SOMEDAY 行：タップで詳細、右端で完了/日時確定。
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

    // MARK: - 承認セクション行

    private func lockedRow(_ task: TaskItem) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(task.title).font(S8Font.jp(15, .bold)).foregroundColor(c.fg1).lineLimit(1)
                if let unlockDate = task.unlockDate {
                    Text(unlockDate, style: .relative)
                        .font(S8Font.mono(12)).foregroundColor(c.fg3)
                }
            }
            Spacer()
            HStack(spacing: 2) {
                if peerSession.isConnected {
                    S8IconButton(icon: "send", action: {
                        peerSession.send(.request(taskID: task.id, title: task.title))
                    })
                    .accessibilityLabel("ペアに依頼")
                }
                S8Icon(name: "lock", size: 16, color: c.fg3)
            }
        }
        .padding(.horizontal, 24).padding(.vertical, 14)
        .overlay(alignment: .top) { S8Rule() }
        .contentShape(Rectangle())
    }

    private func readyRow(_ task: TaskItem) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(task.title).font(S8Font.jp(15, .bold)).foregroundColor(c.fg1).lineLimit(1)
                if let completedAt = task.completedAt {
                    Text(completedAt, style: .time)
                        .font(S8Font.mono(12)).foregroundColor(c.fg3)
                }
            }
            Spacer()
            HStack(spacing: 2) {
                if peerSession.isConnected {
                    S8IconButton(icon: "send", action: {
                        peerSession.send(.request(taskID: task.id, title: task.title))
                    })
                    .accessibilityLabel("ペアに依頼")
                }
                S8IconButton(icon: "check", accent: true, action: {
                    _ = task.approve(by: "self-future", context: context)
                    try? context.save()
                })
                .accessibilityLabel("確定")
            }
        }
        .padding(.horizontal, 24).padding(.vertical, 14)
        .overlay(alignment: .top) { S8Rule() }
        .contentShape(Rectangle())
    }

    #if canImport(CoreMotion) && os(iOS)
    /// Handoff 04a: chop 計器（丸ゲージ + 現在加速度 + 状態）。
    /// 針は加速度に応じて -120°〜+120° を動く（無負荷 -120°）。
    private var chopMeter: some View {
        let mag = chopService.accelerationMagnitude
        let thr = ChopStateMachine.Tuning.peakThreshold
        let progress = min(max(0, mag / (thr * 1.4)), 1)
        let angle = -120.0 + progress * 240.0
        let statePhase: (label: String, color: Color) = {
            switch chopService.machine.state {
            case .idle:     return ("READY", c.fg3)
            case .peaked:   return ("PEAKED", c.warn)
            case .cooldown: return ("COOLDOWN", c.accentInk)
            }
        }()
        return VStack(spacing: 10) {
            ZStack {
                Circle().fill(c.surface)
                Circle().strokeBorder(c.lineStrong, lineWidth: 1.5)
                Rectangle().fill(c.accent).frame(width: 2, height: 13)
                    .offset(y: -35)
                    .rotationEffect(.degrees(angle))
                    .animation(.easeOut(duration: 0.12), value: mag)
                ForEach([-120.0, 0.0, 120.0], id: \.self) { deg in
                    Rectangle().fill(c.lineStrong).frame(width: 1, height: 5)
                        .offset(y: -44)
                        .rotationEffect(.degrees(deg))
                }
                VStack(spacing: 1) {
                    HStack(alignment: .lastTextBaseline, spacing: 1) {
                        Text(String(format: "%.1f", mag))
                            .font(S8Font.mono(19, .bold)).foregroundColor(c.fg1)
                        Text("G").font(S8Font.mono(10)).foregroundColor(c.fg3)
                    }
                    Text("CHOP").font(S8Font.mono(7.5)).tracking(1.4).foregroundColor(c.fg3)
                }
                .offset(y: 8)
            }
            .frame(width: 96, height: 96)

            HStack(spacing: 8) {
                Circle().fill(statePhase.color).frame(width: 5, height: 5)
                Text("\(statePhase.label) · THRESHOLD \(String(format: "%.1f", thr)) G")
                    .font(S8Font.mono(9.5)).tracking(1.3).foregroundColor(c.fg3)
            }
            Text("端末を振り下ろすと先頭の承認待ちを確定")
                .font(S8Font.jp(11.5)).foregroundColor(c.fg3)
        }
        .frame(maxWidth: .infinity)
    }
    #endif

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
        context.insert(TaskItem(title: title, phase: .today, sortIndex: maxIndex + 1,
                                lastSortedDay: Calendar.current.startOfDay(for: .now)))
        do {
            try context.save()
            quickTitle = ""
        } catch {
            print("[TodoList] quickAdd save failed: \(error)")
            assertionFailure("quickAdd save failed: \(error)")
        }
    }
}

// MARK: - 日時確定シート（カレンダーへの一方向昇格）

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
    TodoListView(showWeekReview: .constant(false), peerSession: PeerSession())
        .modelContainer(PreviewData.container)
}
