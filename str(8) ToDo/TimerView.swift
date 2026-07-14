//
//  TimerView.swift
//  str8ToDo
//
//  砂時計タイマー。実機ではモーション（上下反転で開始・元姿勢に戻して一時停止・長押しキャンセル）、
//  シミュレータでは手動ボタンにフォールバック。完了で FocusSession を記録する。
//
//  実機残項目: 上下反転で開始/元姿勢に戻して一時停止の実機確認、意図フリップ 10/10、机バンプ誤発火 0。
//

import SwiftUI
import SwiftData
import Combine
import ActivityKit

struct TimerView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.colorScheme) private var scheme
    private var c: S8Palette { S8Palette.of(scheme) }
    @Query private var allTasks: [TaskItem]
    @Query private var subjects: [Subject]

    @State private var motion = HourglassMotionService()

    // 設定
    @State private var selectedMinutes = 25
    @State private var linkedTaskID: UUID?
    @State private var linkedSubjectID: UUID?
    @State private var dragBaseMinutes: Int?
    /// Handoff 00c: ホイール PRESET ダイヤル（0=preset1 / 1=preset2 / 2=preset3）と連動。
    @AppStorage("wheel.timer.preset") private var wheelPreset = 0
    /// ユーザーカスタマイズ可能なプリセット（設定で編集）。
    @AppStorage(AppSettingsKey.timerPreset1) private var preset1 = AppSettingsKey.timerPreset1Default
    @AppStorage(AppSettingsKey.timerPreset2) private var preset2 = AppSettingsKey.timerPreset2Default
    @AppStorage(AppSettingsKey.timerPreset3) private var preset3 = AppSettingsKey.timerPreset3Default

    private var timerPresets: [Int] { [preset1, preset2, preset3] }

    // セッション状態（経過は paused を除いて累積）
    @State private var sessionStart: Date?
    @State private var runStartedAt: Date?
    @State private var accumulated: TimeInterval = 0
    @State private var now: Date = .now
    @State private var showHUD = false
    @State private var isAlarmAuthDenied = false

    /// View 再生成で変わらないよう @State（cancel が schedule と同じ ID を指す）。
    @State private var alarmID = UUID()
    @State private var showRoom = false
    /// Handoff 08c: Live Activity ハンドル（session を跨いで1本のみ）。
    @State private var activity: Activity<TimerAttributes>? = nil
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
        let c = self.c
        VStack(spacing: 0) {
            S8TopBar("タイマー", sub: "hourglass · flip 180°") {
                EmptyView()   // ponytail: bug/motion HUD ボタンは撤去（デバッグ機能）
            }
            ScrollView {
                VStack(spacing: 24) {
                    hourglass

                    Text(timeText(remaining))
                        .font(.system(size: 56, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText())

                    if !isSessionActive {
                        presets
                    }

                    taskPicker

                    subjectPicker

                    controls

                    phaseTelemetry

                    if isAlarmAuthDenied {
                        Label("アラーム権限が未許可のため、ロック中は音が鳴りません", systemImage: "bell.slash")
                            .font(.caption)
                            .foregroundStyle(c.warn)
                    }

                    if motion.isAvailable && !isSessionActive {
                        if motion.phase == .armed {
                            Label("待機中 — 上下反転で開始", systemImage: "bell.ring")
                                .font(.caption)
                                .foregroundStyle(c.info)
                        } else if motion.phase == .setting {
                            Label("画面を上にして置くと待機", systemImage: "iphone.landscape")
                                .font(.caption)
                                .foregroundStyle(c.fg3)
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 12)
                .padding(.bottom, 32)
                .frame(maxWidth: .infinity)
            }
        }
        .background(c.paper.ignoresSafeArea())
        .sheet(isPresented: $showRoom) {
            FocusRoomView()
        }
        .onReceive(timer) { date in
            now = date
            if isRunning && remaining <= 0 {
                finish()
            }
        }
        .onAppear {
            motion.start()
            isAlarmAuthDenied = AlarmService.isAuthorizationDenied
            restoreSnapshot()
        }
        .onDisappear { motion.stop() }
        .onChange(of: motion.phase) { _, _ in
            guard !showRoom else { return }
            syncWithMotion()
        }
        .onChange(of: linkedTaskID) {
            if isSessionActive {
                saveSnapshot()
            }
        }
        .onChange(of: linkedSubjectID) {
            if isSessionActive {
                saveSnapshot()
            } else if let linkedSubjectID {
                if let subject = subjects.first(where: { $0.id == linkedSubjectID }) {
                    selectedMinutes = subject.pomodoroMinutes
                }
            }
        }
        // Handoff 00c: ホイール PRESET 変更で selectedMinutes を切替（実行中は無視）。
        .onChange(of: wheelPreset) { _, new in
            guard !isSessionActive else { return }
            let idx = max(0, min(timerPresets.count - 1, new))
            selectedMinutes = timerPresets[idx]
        }
    }

    // MARK: - パーツ

    /// Handoff 02a/02b: 計器フェイスプレート内に砂時計。外周ティック + 残分アーク + 中央ドラッグ増減。
    /// 長押しでセッションキャンセル。
    private var hourglass: some View {
        let progress = totalDuration > 0 ? min(1, elapsed / totalDuration) : 0
        let remainFraction = 1 - progress
        return ZStack {
            faceplate(remainFraction: remainFraction)
            hourglassShape(progress: progress)
            VStack {
                Spacer()
                Text(isSessionActive
                     ? "REMAIN \(timeText(remaining)) / \(String(format: "%02d:00", selectedMinutes))"
                     : "SET \(selectedMinutes) MIN · DRAG ±1")
                    .font(S8Font.mono(8)).tracking(1.6).foregroundColor(c.fg3)
                    .padding(.bottom, 22)
            }
        }
        .frame(width: 264, height: 264)
        .contentShape(Circle())
        .gesture(dragToAdjust)
        .onLongPressGesture(minimumDuration: 0.8) {
            if isSessionActive { cancelSession() }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("砂時計 残り\(timeText(remaining))")
        .sensoryFeedback(.increase, trigger: selectedMinutes)
    }

    /// 円形フェイスプレート（外周円 + 内側 12 ティック + 残分 arc）。
    private func faceplate(remainFraction: Double) -> some View {
        ZStack {
            Circle().fill(c.surface).overlay(Circle().stroke(c.lineStrong, lineWidth: 1.5))
            Circle().inset(by: 17).stroke(c.line, lineWidth: 1)
            // マイナーティック
            ForEach([30, 60, 120, 150, 210, 240, 300, 330], id: \.self) { deg in
                Rectangle().fill(c.line).frame(width: 1, height: 8)
                    .offset(y: -128)
                    .rotationEffect(.degrees(Double(deg)))
            }
            // メジャーティック
            ForEach([0, 90, 180, 270], id: \.self) { deg in
                Rectangle().fill(c.lineStrong).frame(width: 1.5, height: 11)
                    .offset(y: -126)
                    .rotationEffect(.degrees(Double(deg)))
            }
            // 残分 arc （accent）
            Circle()
                .trim(from: 0, to: max(0, min(1, remainFraction)))
                .stroke(c.accent, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .padding(4)
                .animation(.easeInOut(duration: 0.4), value: remainFraction)
            // 進行インジケータ（上部の点）
            Circle().fill(c.accent).frame(width: 8, height: 8).offset(y: -121)
        }
    }

    /// フェイスプレート内に置く砂時計本体（上下三角）。
    private func hourglassShape(progress: Double) -> some View {
        VStack(spacing: 4) {
            ZStack(alignment: .bottom) {
                TriangleDown().stroke(c.lineStrong, lineWidth: 2)
                TriangleDown()
                    .fill(c.accent.opacity(0.55))
                    .scaleEffect(CGFloat(1 - progress), anchor: .top)
            }
            .frame(width: 100, height: 72)

            ZStack(alignment: .bottom) {
                TriangleUp().stroke(c.lineStrong, lineWidth: 2)
                TriangleUp()
                    .fill(c.accent.opacity(0.55))
                    .frame(height: 72 * CGFloat(progress))
                    .clipped()
            }
            .frame(width: 100, height: 72)
        }
    }

    /// Handoff 02: フェイズテレメトリ（PHASE — SETTING/RUNNING/PAUSED · face state）。
    /// 計器の下に置く mono キャプション。
    private var phaseTelemetry: some View {
        let phaseLabel: String
        let phaseColor: Color
        if !isSessionActive {
            phaseLabel = "PHASE — SETTING · GRAVITY.Z −0.02"
            phaseColor = c.fg3
        } else if !isRunning {
            phaseLabel = "PHASE — PAUSED · FACE UP"
            phaseColor = c.warn
        } else {
            phaseLabel = "PHASE — RUNNING · FACE DOWN · ALARM SET"
            phaseColor = c.ok
        }
        return HStack(spacing: 10) {
            Circle().fill(phaseColor).frame(width: 6, height: 6)
            Text(phaseLabel).font(S8Font.mono(9)).tracking(1.4).foregroundColor(c.fg3)
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(c.surface)
        .overlay(RoundedRectangle(cornerRadius: 2).stroke(c.line, lineWidth: 1))
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
        HStack(spacing: 8) {
            ForEach(timerPresets, id: \.self) { minutes in
                S8Chip("\(minutes)分", selected: selectedMinutes == minutes, action: { selectedMinutes = minutes })
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
        .tint(c.fg2)
    }

    private var subjectPicker: some View {
        Picker("科目", selection: $linkedSubjectID) {
            Text("科目なし").tag(nil as UUID?)
            ForEach(subjects, id: \.id) { subject in
                Text(subject.name).tag(subject.id as UUID?)
            }
        }
        .pickerStyle(.menu)
        .tint(c.fg2)
    }

    @ViewBuilder
    private var controls: some View {
        // シミュレータ（センサーなし）では手動ボタン、実機でも代替操作として常設
        VStack(spacing: 12) {
            if !isSessionActive {
                S8Button("開始", icon: "hourglass", variant: .primary, action: startRun)
                    .accessibilityLabel("タイマーを開始")
                    .sensoryFeedback(.impact(flexibility: .soft), trigger: isSessionActive)
            } else {
                HStack(spacing: 10) {
                    S8Button(isRunning ? "一時停止" : "再開", icon: isRunning ? "clock" : "hourglass",
                             variant: .secondary, action: { isRunning ? pauseRun() : resumeRun() })
                        .sensoryFeedback(.impact(flexibility: .soft), trigger: isRunning)

                    S8Button("終了", icon: "check", variant: .primary, action: { finish() })
                        .accessibilityLabel("タイマーを終了して記録")
                        .sensoryFeedback(.success, trigger: isSessionActive)
                }
                S8Button("キャンセル", icon: "x", variant: .ghost, action: cancelSession)
                    .accessibilityLabel("記録せずにキャンセル")
            }
            if !isSessionActive {
                S8Button("ルームで集中", icon: "users", variant: .ghost, action: { showRoom = true })
            }
        }
    }

    // MARK: - スナップショット永続化

    private func saveSnapshot() {
        guard let start = sessionStart else { return }
        // ponytail: NSNull は plist 型ではないため、nil のキーは辞書に含めない
        var snapshot: [String: Any] = [
            "sessionStart": start.timeIntervalSinceReferenceDate,
            "accumulated": accumulated,
            "selectedMinutes": selectedMinutes,
            "alarmID": alarmID.uuidString
        ]
        if let runStartedAt {
            snapshot["runStartedAt"] = runStartedAt.timeIntervalSinceReferenceDate
        }
        if let linkedTaskID {
            snapshot["linkedTaskID"] = linkedTaskID.uuidString
        }
        if let linkedSubjectID {
            snapshot["linkedSubjectID"] = linkedSubjectID.uuidString
        }
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
            // パース失敗・不正値→古いアラームがあればキャンセルしてクリア
            if let alarmIDStr = snapshot["alarmID"] as? String,
               let alarmUUID = UUID(uuidString: alarmIDStr) {
                AlarmService.cancel(id: alarmUUID)
            }
            clearSnapshot()

        case .resume(let sessionStart, let accumulated, let runStartedAt, let selectedMinutes, let linkedTaskID, let linkedSubjectID, let alarmID):
            // 実行中（期限内）or 一時停止中→状態復元のみ
            self.sessionStart = sessionStart
            self.accumulated = accumulated
            self.runStartedAt = runStartedAt
            self.selectedMinutes = selectedMinutes
            self.linkedTaskID = linkedTaskID
            self.linkedSubjectID = linkedSubjectID
            self.alarmID = alarmID
            self.now = .now

        case .autoFinish(let sessionStart, let end, let linkedTaskID, let linkedSubjectID, let alarmID):
            // 実行中で期限超過→状態セット後に自動 finish（endCap で期限に制限）
            self.sessionStart = sessionStart
            self.linkedTaskID = linkedTaskID
            self.linkedSubjectID = linkedSubjectID
            self.alarmID = alarmID
            self.now = .now
            finish(endCap: end)
        }
    }

    // MARK: - セッション制御

    /// 状態変更と保存を集約: 状態変更後に自動的に saveSnapshot() を呼ぶ。
    private func updateSession(_ mutate: () -> Void) {
        mutate()
        saveSnapshot()
    }

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
        updateSession {
            sessionStart = .now
            runStartedAt = .now
            accumulated = 0
            now = .now
        }
        AlarmService.schedule(id: alarmID, fireDate: .now.addingTimeInterval(remaining),
                              title: "タイマー終了")
        startActivityIfNeeded()
    }

    private func pauseRun() {
        guard let started = runStartedAt else { return }
        updateSession {
            accumulated += Date.now.timeIntervalSince(started)
            runStartedAt = nil
        }
        AlarmService.cancel(id: alarmID)
        updateActivity(isPaused: true)
    }

    private func resumeRun() {
        updateSession {
            runStartedAt = .now
            now = .now
        }
        AlarmService.schedule(id: alarmID, fireDate: .now.addingTimeInterval(remaining),
                              title: "タイマー終了")
        updateActivity(isPaused: false)
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
        let subject = subjects.first { $0.id == linkedSubjectID }
        FocusSession.record(start: start, end: end, task: task, subject: subject, context: context)
        AlarmService.cancel(id: alarmID)
        endActivity()
        resetSession()
        clearSnapshot()
    }

    /// キャンセル（長押し or ボタン）: 記録せずに破棄。
    private func cancelSession() {
        AlarmService.cancel(id: alarmID)
        endActivity()
        resetSession()
        clearSnapshot()
    }

    private func resetSession() {
        sessionStart = nil
        runStartedAt = nil
        accumulated = 0
        motion.reset()
    }

    // MARK: - Handoff 08c: Live Activity

    /// タイマー開始時に Live Activity を起動（既に走っていれば no-op）。
    /// Activity.areActivitiesEnabled が false（ユーザーが Live Activity を無効化）なら黙って諦める。
    private func startActivityIfNeeded() {
        guard #available(iOS 16.1, *) else { return }
        guard activity == nil else { return }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let task = linkableTasks.first { $0.id == linkedTaskID }
        let subject = subjects.first { $0.id == linkedSubjectID }
        let attrs = TimerAttributes(
            subjectName: subject?.name,
            taskTitle: task?.title ?? "集中"
        )
        let state = TimerAttributes.ContentState(
            endDate: .now.addingTimeInterval(remaining),
            totalMinutes: selectedMinutes,
            isPaused: false,
            pausedRemainingSec: 0
        )
        do {
            activity = try Activity.request(
                attributes: attrs,
                content: .init(state: state, staleDate: nil)
            )
        } catch {
            // 起動失敗（enable=false 直後・quota 到達等）は UI 継続、Live Activity なしで動く。
        }
    }

    /// 進行中の Activity を pause/resume 反映で更新。
    private func updateActivity(isPaused: Bool) {
        guard #available(iOS 16.1, *) else { return }
        guard let activity else { return }
        let paused = Int(remaining.rounded())
        let state = TimerAttributes.ContentState(
            endDate: .now.addingTimeInterval(remaining),
            totalMinutes: selectedMinutes,
            isPaused: isPaused,
            pausedRemainingSec: paused
        )
        Task { await activity.update(.init(state: state, staleDate: nil)) }
    }

    /// Activity を終了（final state はロック画面に薄く残す）。
    private func endActivity() {
        guard #available(iOS 16.1, *) else { return }
        guard let activity else { return }
        self.activity = nil
        let state = TimerAttributes.ContentState(
            endDate: .now,
            totalMinutes: selectedMinutes,
            isPaused: true,
            pausedRemainingSec: 0
        )
        Task { await activity.end(.init(state: state, staleDate: nil), dismissalPolicy: .immediate) }
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
