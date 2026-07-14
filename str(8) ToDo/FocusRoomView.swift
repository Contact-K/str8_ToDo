//
//  FocusRoomView.swift
//  str8ToDo
//
//  集中ルーム画面（Phase 14）。ホストが時間設定→参加者募集→全員 faceDown で
//  同期開始→終了時に FocusSession を各端末が自身の分だけ save し、承認へ流す。
//  フォアグラウンド限定：background に入ったら退出。
//

import SwiftUI
import SwiftData
import os

struct FocusRoomView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var scheme
    private var c: S8Palette { S8Palette.of(scheme) }
    @State private var peer = PeerRoomSession()
    @State private var motion = HourglassMotionService()
    @State private var lastMotionPhase = HourglassStateMachine.Phase.setting

    // ホスト設定
    @State private var isHost = false
    @State private var selectedMinutes: Int = 25

    // タイマー状態
    @State private var localStartAt: TimeInterval? = nil
    @State private var now: Date = .now
    @State private var timer: Timer? = nil
    @State private var saveErrorMessage: String? = nil
    @State private var showSaveError: Bool = false   // B7: alert Binding を @State に。
    @State private var hasFinished = false
    /// B4 fix: background も 10 秒バッファに合流。短時間の離脱ではセッションを消さない。
    @State private var inactiveWatchTask: Task<Void, Never>? = nil

    /// ApprovalQueueView への直行動線（Notification 経由）。ContentView が受けて承認タブへ切替。
    static let proceedToApprovalNotification = Notification.Name("focusRoomProceedToApproval")

    var body: some View {
        let c = self.c
        VStack(spacing: 0) {
            S8TopBar("集中ルーム", sub: "focus · sync room") {
                S8IconButton(icon: "x") {
                    peer.broadcast(.leave(participantID: peer.myID))
                    cleanup()
                    dismiss()
                }
                .accessibilityLabel("退出")
            }
            S8Rule()
            ScrollView {
                VStack(spacing: 0) {
                    if hasFinished {
                        endedSection
                    } else {
                        switch peer.state {
                        case .waiting:
                            waitingSection
                        case .readyToStart:
                            readyToStartSection
                        case .running, .ended:
                            runningSection
                        case .aborted:
                            abortedSection
                        }
                    }
                    Color.clear.frame(height: 24)
                }
            }
        }
        .background(c.paper.ignoresSafeArea())
        .onAppear {
            peer.onStartScheduled = { localStart in
                self.localStartAt = localStart
                // 1 秒粒度でカウントダウン。満了判定はホストのみが行い、broadcast(.end) 経由で
                // 全端末（ホスト含む）が onEnded → finishAndSave する。
                self.timer?.invalidate()
                self.timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
                    Task { @MainActor in
                        self.now = .now
                        let elapsed = self.now.timeIntervalSince1970 - localStart
                        if elapsed >= Double(self.selectedMinutes * 60), self.peer.isHost {
                            self.peer.end()
                        }
                    }
                }
            }
            peer.onEnded = {
                self.finishAndSave()
            }
            motion.start()
            lastMotionPhase = motion.phase
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 300_000_000)
                if motion.isDeviceFaceDown {
                    peer.setFaceDown(true)
                }
            }
        }
        .onDisappear {
            cleanup()
        }
        .onChange(of: motion.phase) { _, newPhase in
            if newPhase == .running && lastMotionPhase != .running {
                peer.setFaceDown(true)
            } else if newPhase == .paused && lastMotionPhase != .paused {
                peer.setFaceDown(false)
            }
            lastMotionPhase = newPhase
        }
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .background, .inactive:
                // B4 fix: background も inactive と同じ 10s バッファに合流。
                inactiveWatchTask?.cancel()
                inactiveWatchTask = Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 10_000_000_000)
                    guard !Task.isCancelled else { return }
                    cleanup()
                    dismiss()
                }
            default:
                inactiveWatchTask?.cancel()
                inactiveWatchTask = nil
            }
        }
        .onChange(of: peer.state) { _, newState in
            if newState == .aborted {
                cleanup()
            }
        }
        // B7 fix: .constant(...) Binding を @State に。OK は alert のみ閉じ、シートは残す。
        .onChange(of: saveErrorMessage) { _, new in
            showSaveError = (new != nil)
        }
        .alert("保存に失敗しました", isPresented: $showSaveError) {
            Button("OK") {
                showSaveError = false
                saveErrorMessage = nil
            }
        } message: {
            Text(saveErrorMessage ?? "")
        }
    }

    /// timer/motion/peer の停止を一元化。呼び忘れ経路（退出ボタン・background・.inactive 長時間・
    /// aborted 遷移・save 成功後・save 失敗後）を全てここに集約する。
    /// reason: save 失敗系の呼び出しでログに残す（デバッグ用、既定 nil で既存呼び出しは無変更）。
    private func cleanup(reason: String? = nil) {
        if let reason {
            os_log("FocusRoom cleanup: %{public}s", log: .default, type: .debug, reason)
        }
        timer?.invalidate()
        timer = nil
        inactiveWatchTask?.cancel()
        inactiveWatchTask = nil
        motion.stop()
        peer.stop()
    }

    // MARK: - Waiting セクション（ホスト設定 or ゲストのホスト選択）
    private var waitingSection: some View {
        VStack(spacing: 0) {
            if !isHost && peer.discoveredHosts.isEmpty {
                S8SectionLabel(text: "ルームを開始")
                VStack(spacing: 10) {
                    S8Button("ルームを開く（ホスト）", icon: "plus", variant: .primary) {
                        isHost = true
                        peer.startHosting()
                    }
                    S8Button("ルームに参加", icon: "search", variant: .secondary) {
                        peer.startBrowsing()
                    }
                }
                .padding(.horizontal, 24).padding(.vertical, 12)
            }

            if isHost {
                S8SectionLabel(text: "時間設定")
                S8SetRow(icon: "hourglass", label: "集中時間") {
                    S8Stepper(value: $selectedMinutes, range: 5...120, step: 5, unit: "分", width: 132)
                }
                S8Rule()
                participantList
                HStack {
                    S8Icon(name: "info", size: 12, color: c.fg3)
                    Text("全員が端末を上下反転すると開始します")
                        .font(S8Font.mono(11)).tracking(1.0).foregroundColor(c.fg3)
                }
                .padding(.horizontal, 24).padding(.top, 8)
            }

            if !isHost && !peer.discoveredHosts.isEmpty {
                S8SectionLabel(text: "見つかったホスト")
                ForEach(Array(peer.discoveredHosts.enumerated()), id: \.offset) { i, host in
                    S8SetRow(icon: "wifi", label: host.displayName, trailing: {
                        S8Icon(name: "chevron-right", size: 14, color: c.fg3)
                    }, onTap: {
                        peer.requestJoin(host: host)
                    })
                    if i < peer.discoveredHosts.count - 1 { S8Rule() }
                }
            } else if !isHost && peer.discoveredHosts.isEmpty && !peer.participants.isEmpty {
                // ゲストがブラウズ中（B1 fix によって participants に自分だけ入っている）
                S8SectionLabel(text: "ホスト探索中")
                HStack {
                    S8Icon(name: "search", size: 14, color: c.fg3)
                    Text("近くのホストを探しています…")
                        .font(S8Font.jp(13)).foregroundColor(c.fg3)
                    Spacer()
                }
                .padding(.horizontal, 24).padding(.vertical, 15)
            }
        }
    }

    // MARK: - ReadyToStart セクション（B3 fix: 500ms の準備状態を可視化）
    private var readyToStartSection: some View {
        VStack(spacing: 8) {
            Text("まもなく開始")
                .font(S8Font.jp(28, .bold))
                .foregroundColor(c.accent)
                .padding(.top, 32)
            Text("端末を伏せたまま待機")
                .font(S8Font.mono(11)).tracking(1.2).foregroundColor(c.fg3)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }

    // MARK: - Running セクション（同期タイマー・参加者リスト）
    private var runningSection: some View {
        VStack(spacing: 12) {
            if let localStart = localStartAt {
                let elapsed = now.timeIntervalSince1970 - localStart
                let remain = TimeInterval(selectedMinutes * 60) - elapsed
                Text(countdownText(remain))
                    .font(S8Font.mono(72, .bold))
                    .foregroundColor(c.fg1)
                    .padding(.top, 24)
                if elapsed < 0 {
                    Text("まもなく開始…")
                        .font(S8Font.mono(11)).tracking(1.2).foregroundColor(c.fg3)
                }
            }
            Text("参加中: \(peer.participants.count) 人")
                .font(S8Font.mono(11)).tracking(1.2).foregroundColor(c.fg3)
                .padding(.top, 8)
            participantList
        }
    }

    // MARK: - 参加者リスト（共通）
    private var participantList: some View {
        VStack(spacing: 0) {
            S8SectionLabel(text: "参加者 \(peer.participants.count) / 7")
            ForEach(Array(peer.participants.enumerated()), id: \.element.id) { i, p in
                S8SetRow(icon: p.isFaceDown ? "check-circle" : "user", label: p.id + (p.isHost ? " (ホスト)" : "")) {
                    S8Tag(p.isFaceDown ? "READY" : "WAIT", color: p.isFaceDown ? c.ok : c.warn)
                }
                if i < peer.participants.count - 1 { S8Rule() }
            }
        }
    }

    // MARK: - 終了・中断
    private var endedSection: some View {
        VStack(spacing: 12) {
            Text("集中セッション終了").font(S8Font.jp(21, .bold)).foregroundColor(c.fg1).padding(.top, 32)
            Text("お疲れさまでした").font(S8Font.mono(11)).tracking(1.2).foregroundColor(c.fg3)
            S8Button("承認へ進む", icon: "check-circle", variant: .primary) {
                NotificationCenter.default.post(name: Self.proceedToApprovalNotification, object: nil)
                dismiss()
            }
            .padding(.horizontal, 24).padding(.top, 16)
        }
    }

    private var abortedSection: some View {
        VStack(spacing: 12) {
            Text("ホストが離脱しました")
                .font(S8Font.jp(21, .bold)).foregroundColor(c.fg1).padding(.top, 32)
            Text("このルームは再開できません")
                .font(S8Font.mono(11)).tracking(1.2).foregroundColor(c.fg3)
            S8Button("閉じる", variant: .secondary) { dismiss() }
                .padding(.horizontal, 24).padding(.top, 16)
        }
    }

    // MARK: - 終了時に FocusSession を保存
    private func finishAndSave() {
        guard FocusRoom.markFinishedOnce(&hasFinished) else { return }
        timer?.invalidate()
        timer = nil
        peer.markEnded()
        guard let localStart = localStartAt else {
            // save 失敗と同じ扱い：localStartAt が無いと FocusSession を組み立てられない
            os_log("FocusRoom save failed: localStartAt is nil", log: .default, type: .error)
            saveErrorMessage = "セッション開始時刻が不明のため保存できませんでした"
            cleanup(reason: "localStartAt nil")
            return
        }
        let start = Date(timeIntervalSince1970: localStart)
        let end = Date(timeIntervalSince1970: localStart + Double(selectedMinutes * 60))
        let session = FocusSession.record(start: start, end: end, task: nil, subject: nil, context: context)
        session.roomID = peer.roomID
        session.participantCount = peer.participants.count
        session.approverID = peer.approverDisplayName
        do {
            try context.save()
        } catch {
            os_log("FocusRoom save failed: %@", log: .default, type: .error, error.localizedDescription)
            saveErrorMessage = "保存に失敗しました：\(error.localizedDescription)"
            cleanup(reason: "save failed")
            return
        }
        // 保存成功後は resources を止めるだけ。dismiss は endedSection の「承認へ進む」ボタンに委ねる。
        cleanup()
    }
}

#Preview {
    FocusRoomView().modelContainer(PreviewData.container)
}
