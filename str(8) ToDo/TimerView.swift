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
    // dragBaseMinutes 廃止 2026-07-14: 円盤縦ドラッグは Crown ホイール（ホイール中心長押し）へ移行。
    /// Handoff 00c: ホイール PRESET ダイヤル（0=preset1 / 1=preset2 / 2=preset3）と連動。
    @AppStorage("wheel.timer.preset") private var wheelPreset = 0
    /// ユーザーカスタマイズ可能なプリセット（設定で編集）。ショップで枠を購入すると 4/5/6 が有効化。
    @AppStorage(AppSettingsKey.timerPreset1) private var preset1 = AppSettingsKey.timerPreset1Default
    @AppStorage(AppSettingsKey.timerPreset2) private var preset2 = AppSettingsKey.timerPreset2Default
    @AppStorage(AppSettingsKey.timerPreset3) private var preset3 = AppSettingsKey.timerPreset3Default
    @AppStorage(AppSettingsKey.timerPreset4) private var preset4 = AppSettingsKey.timerPreset4Default
    @AppStorage(AppSettingsKey.timerPreset5) private var preset5 = AppSettingsKey.timerPreset5Default
    @AppStorage(AppSettingsKey.timerPreset6) private var preset6 = AppSettingsKey.timerPreset6Default
    /// 手動時間（0=未設定）。設定されているとプリセットより優先。
    @AppStorage("timer.manualMinutes") private var manualMinutes = 0

    /// アクティブなプリセット配列（ショップの presetCap で切り詰め）。
    private var timerPresets: [Int] {
        let all = [preset1, preset2, preset3, preset4, preset5, preset6]
        return Array(all.prefix(ShopManager.shared.presetCap))
    }

    /// 手動値がある時は手動、無ければ選択プリセット。
    private var effectivePresetMinutes: Int {
        manualMinutes > 0 ? manualMinutes : timerPresets[max(0, min(timerPresets.count - 1, wheelPreset))]
    }

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
    @State private var showPresetSettings = false
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
                S8IconButton(icon: "settings", action: { showPresetSettings = true })
                    .accessibilityLabel("プリセット設定")
            }
            ScrollView {
                VStack(spacing: 24) {
                    hourglass

                    Text(timeText(remaining))
                        .font(.system(size: 56, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText())

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
                            // 中央ホログラム「ひっくり返して開始」で誘導、下部ラベルは補助のみ。
                            Label("回すと開始", systemImage: "arrow.triangle.2.circlepath")
                                .font(.caption)
                                .foregroundStyle(c.info)
                        } else if motion.phase == .setting {
                            Label("端末上下を反転で待機（充電口を上）", systemImage: "iphone.gen3")
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
        // 背景はグローバル S8SamonPaper に任せる
        .sheet(isPresented: $showRoom) {
            FocusRoomView()
        }
        .sheet(isPresented: $showPresetSettings) {
            presetSettingsSheet
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
            // 起動時: 手動値があればプリセットより優先して反映（セッション実行中は restoreSnapshot が上書き済み）。
            if !isSessionActive {
                selectedMinutes = effectivePresetMinutes
            }
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
        // プリセットを明示的に選び直したら手動値はリセット（プリセット優先の意思表示）。
        .onChange(of: wheelPreset) { _, new in
            guard !isSessionActive else { return }
            let idx = max(0, min(timerPresets.count - 1, new))
            manualMinutes = 0
            selectedMinutes = timerPresets[idx]
            clearSnapshot()
        }
        // 手動値が更新されたらそちらを反映＋古い残時間 snapshot は捨てる。
        .onChange(of: manualMinutes) { _, new in
            guard !isSessionActive else { return }
            if new > 0 {
                selectedMinutes = new
            }
            clearSnapshot()
        }
    }

    // MARK: - パーツ

    /// Handoff 02a/02b: 計器フェイスプレート内に砂時計。外周ティック + 残分アーク。
    /// 時間調整はホイール中心長押しで Crown 展開（旧・円盤縦ドラッグは廃止 2026-07-14）。
    /// 長押しでセッションキャンセル。
    private var hourglass: some View {
        let progress = totalDuration > 0 ? min(1, elapsed / totalDuration) : 0
        let remainFraction = 1 - progress
        return ZStack {
            faceplate(remainFraction: remainFraction)
            hourglassShape(progress: progress)
            // 仕様反転 2026-07-14: armed 状態は「上部を下」で待機している。ユーザー視点では
            // テキストが逆さまなので 180° 回転して描画 → 端末を戻すと正立に見えつつ running に遷移。
            if motion.phase == .armed {
                Text("ひっくり返して開始")
                    .font(S8Font.jp(15, .bold))
                    .foregroundColor(c.accent)
                    .rotationEffect(.degrees(180))
            }
            VStack {
                Spacer()
                Text(isSessionActive
                     ? "REMAIN \(timeText(remaining)) / \(String(format: "%02d:00", selectedMinutes))"
                     : "SET \(selectedMinutes) MIN")
                    .font(S8Font.mono(8)).tracking(1.6).foregroundColor(c.fg3)
                    .padding(.bottom, 22)
            }
        }
        .frame(width: 264, height: 264)
        .contentShape(Circle())
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

    /// プリセット設定シート（ヘッダの設定ボタンから開く）。
    private var presetSettingsSheet: some View {
        let c = self.c
        return VStack(spacing: 0) {
            HStack {
                Spacer()
                Text("タイマープリセット").font(S8Font.jp(16, .bold)).foregroundColor(c.fg1)
                Spacer()
            }
            .padding(.horizontal, 24).padding(.top, 18).padding(.bottom, 8)
            .overlay(alignment: .trailing) {
                Button("閉じる") { showPresetSettings = false }
                    .font(S8Font.jp(14)).foregroundColor(c.accentInk)
                    .padding(.trailing, 20).padding(.top, 18)
            }
            presetEditRows
            Spacer(minLength: 0)
        }
        .background(c.paper.ignoresSafeArea())
        .presentationDetents([.medium])
    }

    /// プリセット編集行（設定タブから移設 2026-07-14）。ショップの presetCap 分だけ表示。
    /// 現在選択中の枠は accent 表示、選択されていない枠はタップで切替。
    /// 長押しで Crown ホイールを起動（S8ClickWheel 中心コアと同じアクションを直接呼ぶ）。
    private var presetEditRows: some View {
        let c = self.c
        let cap = ShopManager.shared.presetCap
        return VStack(spacing: 0) {
            S8SectionLabel(text: "タイマープリセット")
            ForEach(0..<cap, id: \.self) { i in
                if i > 0 { S8Rule() }
                presetEditRow(index: i, minutes: bindingForPreset(i))
            }
        }
        .background(c.paper)
    }

    /// index に対応する @AppStorage への Binding を返す。ShopManager.presetCap を超える index は呼ばれない前提。
    private func bindingForPreset(_ i: Int) -> Binding<Int> {
        switch i {
        case 0: return $preset1
        case 1: return $preset2
        case 2: return $preset3
        case 3: return $preset4
        case 4: return $preset5
        default: return $preset6
        }
    }

    private func presetEditRow(index: Int, minutes: Binding<Int>) -> some View {
        let c = self.c
        let isCurrent = wheelPreset == index
        return HStack(spacing: 14) {
            Button(action: { wheelPreset = index }) {
                HStack(spacing: 10) {
                    S8Icon(name: "hourglass", size: 20, color: isCurrent ? c.accent : c.fg2)
                    Text("プリセット\(index + 1)").font(S8Font.jp(15, isCurrent ? .bold : .regular)).foregroundColor(isCurrent ? c.accent : c.fg1)
                }
            }
            .buttonStyle(.plain)
            Spacer()
            S8Stepper(value: minutes, range: 1...180, step: 1, unit: "分", width: 132)
        }
        .padding(.horizontal, 24).padding(.vertical, 15)
    }

    private var taskPicker: some View {
        S8Picker(
            selection: $linkedTaskID,
            options: [(nil as UUID?, "紐付けなし")] + linkableTasks.map { ($0.id as UUID?, $0.title) },
            style: .sheet,
            placeholder: "タスクを選択"
        )
    }

    private var subjectPicker: some View {
        S8Picker(
            selection: $linkedSubjectID,
            options: [(nil as UUID?, "科目なし")] + subjects.map { ($0.id as UUID?, $0.name) },
            style: .sheet,
            placeholder: "科目を選択"
        )
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

    /// Activity を終了。self.activity ハンドルだけでなく、システムに残っている全 TimerAttributes
    /// activity を強制的に end する（activity handle が nil でもゴースト Live Activity が消える）。
    private func endActivity() {
        guard #available(iOS 16.1, *) else { return }
        self.activity = nil
        let state = TimerAttributes.ContentState(
            endDate: .now,
            totalMinutes: selectedMinutes,
            isPaused: true,
            pausedRemainingSec: 0
        )
        Task {
            // Activity<TimerAttributes>.activities はシステムに登録済みの全 activity を返す。
            // ゴースト（前セッションの残りや handle 消失）も含めて確実に dismiss する。
            for act in Activity<TimerAttributes>.activities {
                await act.end(.init(state: state, staleDate: nil), dismissalPolicy: .immediate)
            }
        }
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
