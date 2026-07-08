//
//  TimerView.swift
//  str8ToDo
//
//  砂時計タイマー。実機ではモーション（伏せて開始・起こして一時停止・長押しキャンセル）、
//  シミュレータでは手動ボタンにフォールバック。完了で FocusSession を記録する。
//
//  実機残項目: 伏せて開始/起こして一時停止の実機確認、意図フリップ 10/10、机バンプ誤発火 0。
//

import SwiftUI
import SwiftData
import Combine

struct TimerView: View {
    @Environment(\.modelContext) private var context
    @Query private var allTasks: [TaskItem]

    @State private var motion = HourglassMotionService()

    // 設定
    @State private var selectedMinutes = 25
    @State private var linkedTaskID: UUID?
    @State private var dragBaseMinutes: Int?

    // セッション状態（経過は paused を除いて累積）
    @State private var sessionStart: Date?
    @State private var runStartedAt: Date?
    @State private var accumulated: TimeInterval = 0
    @State private var now: Date = .now
    @State private var showHUD = false

    /// View 再生成で変わらないよう @State（cancel が schedule と同じ ID を指す）。
    @State private var alarmID = UUID()
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var isSessionActive: Bool { sessionStart != nil }
    private var isRunning: Bool { runStartedAt != nil }

    private var totalDuration: TimeInterval { TimeInterval(selectedMinutes * 60) }

    private var elapsed: TimeInterval {
        accumulated + (runStartedAt.map { now.timeIntervalSince($0) } ?? 0)
    }

    private var remaining: TimeInterval { max(0, totalDuration - elapsed) }

    /// 紐付け候補: 浮遊または今日の active タスク。
    private var linkableTasks: [TaskItem] {
        allTasks.filter { task in
            guard task.status == .active else { return false }
            guard let start = task.startDate else { return true }
            return Calendar.current.isDateInToday(start)
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                hourglass

                Text(timeText(remaining))
                    .font(.system(size: 56, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())

                if !isSessionActive {
                    presets
                    taskPicker
                }

                controls

                if motion.isAvailable && !isSessionActive {
                    Text("伏せて開始（起こすと一時停止・長押しでキャンセル）")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .padding(.top, 24)
            .navigationTitle("タイマー")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: { showHUD = true }) {
                        Image(systemName: "ladybug")
                    }
                    .accessibilityLabel("モーション HUD を開く")
                }
            }
            .sheet(isPresented: $showHUD) {
                NavigationStack {
                    MotionHUDView(service: motion)
                }
            }
            .onReceive(timer) { date in
                now = date
                if isRunning && remaining <= 0 {
                    finish()
                }
            }
            .onAppear {
                motion.start()
                restoreSnapshot()
            }
            .onDisappear { motion.stop() }
            .onChange(of: motion.phase) {
                syncWithMotion()
            }
        }
    }

    // MARK: - パーツ

    /// 砂時計ビジュアル: 上の砂が減り、下の砂が増える。長押しでキャンセル。
    private var hourglass: some View {
        let progress = totalDuration > 0 ? min(1, elapsed / totalDuration) : 0
        return VStack(spacing: 2) {
            ZStack(alignment: .bottom) {
                TriangleDown().stroke(Color.secondary, lineWidth: 2)
                TriangleDown()
                    .fill(Color.accentColor.opacity(0.6))
                    .scaleEffect(CGFloat(1 - progress), anchor: .top)
            }
            .frame(width: 100, height: 70)

            ZStack(alignment: .bottom) {
                TriangleUp().stroke(Color.secondary, lineWidth: 2)
                TriangleUp()
                    .fill(Color.accentColor.opacity(0.6))
                    .frame(height: 70 * CGFloat(progress))
                    .clipped()
            }
            .frame(width: 100, height: 70)
        }
        .contentShape(Rectangle())
        .gesture(dragToAdjust)
        .onLongPressGesture(minimumDuration: 0.8) {
            if isSessionActive { cancelSession() }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("砂時計 残り\(timeText(remaining))")
        .sensoryFeedback(.increase, trigger: selectedMinutes)
    }

    /// 縦ドラッグで1分刻み増減（セッション中は無効）。
    private var dragToAdjust: some Gesture {
        DragGesture()
            .onChanged { value in
                guard !isSessionActive else { return }
                if dragBaseMinutes == nil { dragBaseMinutes = selectedMinutes }
                let delta = -Int(value.translation.height / 12)
                selectedMinutes = min(120, max(1, (dragBaseMinutes ?? selectedMinutes) + delta))
            }
            .onEnded { _ in dragBaseMinutes = nil }
    }

    private var presets: some View {
        HStack(spacing: 12) {
            ForEach([25, 5, 15], id: \.self) { minutes in
                Button("\(minutes)分") { selectedMinutes = minutes }
                    .buttonStyle(.bordered)
                    .fontWeight(selectedMinutes == minutes ? .bold : .regular)
            }
        }
    }

    private var taskPicker: some View {
        Picker("タスク", selection: $linkedTaskID) {
            Text("紐付けなし").tag(nil as UUID?)
            ForEach(linkableTasks, id: \.id) { task in
                Text(task.title).tag(task.id as UUID?)
            }
        }
        .pickerStyle(.menu)
    }

    @ViewBuilder
    private var controls: some View {
        // シミュレータ（センサーなし）では手動ボタン、実機でも代替操作として常設
        HStack(spacing: 16) {
            if !isSessionActive {
                Button("開始") { startRun() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .accessibilityLabel("タイマーを開始")
            } else {
                Button(isRunning ? "一時停止" : "再開") {
                    isRunning ? pauseRun() : resumeRun()
                }
                .buttonStyle(.bordered)
                .controlSize(.large)

                Button("終了") { finish() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .accessibilityLabel("タイマーを終了して記録")

                Button("キャンセル") { cancelSession() }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .tint(.red)
                    .accessibilityLabel("記録せずにキャンセル")
            }
        }
    }

    // MARK: - スナップショット永続化

    private func saveSnapshot() {
        guard let start = sessionStart else { return }
        let snapshot: [String: Any] = [
            "sessionStart": start.timeIntervalSinceReferenceDate,
            "accumulated": accumulated,
            "runStartedAt": runStartedAt?.timeIntervalSinceReferenceDate ?? NSNull(),
            "selectedMinutes": selectedMinutes,
            "linkedTaskID": linkedTaskID?.uuidString ?? NSNull(),
            "alarmID": alarmID.uuidString
        ]
        UserDefaults.standard.set(snapshot, forKey: "timer.session")
    }

    private func clearSnapshot() {
        UserDefaults.standard.removeObject(forKey: "timer.session")
    }

    private func restoreSnapshot() {
        guard let snapshot = UserDefaults.standard.dictionary(forKey: "timer.session") else { return }

        // ponytail: TimerRestore.decide で判定（妥当性チェック込み）。不正→クリア / 自動finish / 復元のみ。
        let decision = TimerRestore.decide(snapshot: snapshot, now: .now)

        switch decision {
        case .invalid:
            // パース失敗・不正値→クリア
            clearSnapshot()

        case .resume(let sessionStart, let accumulated, let runStartedAt, let selectedMinutes, let linkedTaskID, let alarmID):
            // 実行中（期限内）or 一時停止中→状態復元のみ
            self.sessionStart = sessionStart
            self.accumulated = accumulated
            self.runStartedAt = runStartedAt
            self.selectedMinutes = selectedMinutes
            self.linkedTaskID = linkedTaskID
            self.alarmID = alarmID
            self.now = .now

        case .autoFinish(let sessionStart, let end, let linkedTaskID, let alarmID):
            // 実行中で期限超過→状態セット後に自動 finish（endCap で期限に制限）
            self.sessionStart = sessionStart
            self.linkedTaskID = linkedTaskID
            self.alarmID = alarmID
            self.now = .now
            finish(endCap: end)
        }
    }

    // MARK: - セッション制御

    /// モーションのフェーズ遷移を UI 状態へ反映（実機のみ発火）。
    private func syncWithMotion() {
        switch motion.phase {
        case .running:
            if !isSessionActive {
                startRun()
            } else if !isRunning {
                resumeRun()
            }
        case .paused:
            if isRunning { pauseRun() }
        case .setting, .armed:
            break
        }
    }

    private func startRun() {
        sessionStart = .now
        runStartedAt = .now
        accumulated = 0
        now = .now
        AlarmService.schedule(id: alarmID, fireDate: .now.addingTimeInterval(remaining),
                              title: "タイマー終了")
        saveSnapshot()
    }

    private func pauseRun() {
        guard let started = runStartedAt else { return }
        accumulated += Date.now.timeIntervalSince(started)
        runStartedAt = nil
        AlarmService.cancel(id: alarmID)
        saveSnapshot()
    }

    private func resumeRun() {
        runStartedAt = .now
        now = .now
        AlarmService.schedule(id: alarmID, fireDate: .now.addingTimeInterval(remaining),
                              title: "タイマー終了")
        saveSnapshot()
    }

    /// 完了（時間切れ or 手動終了）: FocusSession を記録。
    /// endCap: 復元時の自動 finish では予定終了時刻を渡して end を制限。
    private func finish(endCap: Date? = nil) {
        guard let start = sessionStart else { return }
        if let started = runStartedAt {
            accumulated += Date.now.timeIntervalSince(started)
        }
        let end = endCap ?? Date.now
        let task = linkableTasks.first { $0.id == linkedTaskID }
        FocusSession.record(start: start, end: end, task: task, context: context)
        AlarmService.cancel(id: alarmID)
        resetSession()
        clearSnapshot()
    }

    /// キャンセル（長押し or ボタン）: 記録せずに破棄。
    private func cancelSession() {
        AlarmService.cancel(id: alarmID)
        resetSession()
        clearSnapshot()
    }

    private func resetSession() {
        sessionStart = nil
        runStartedAt = nil
        accumulated = 0
        motion.reset()
    }

    private func timeText(_ interval: TimeInterval) -> String {
        let seconds = Int(interval.rounded())
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}

// MARK: - 砂時計の形

private struct TriangleDown: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

private struct TriangleUp: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

#Preview {
    TimerView()
        .modelContainer(PreviewData.container)
}
