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
    @State private var hasFinished = false
    /// 10 秒以上続く .inactive（電話着信等の一時的な離脱は許容）を監視して退出させるタスク。
    @State private var inactiveWatchTask: Task<Void, Never>? = nil

    /// ApprovalQueueView への直行動線（Notification 経由。最少 diff）。ContentView が受けて承認タブへ切替。
    static let proceedToApprovalNotification = Notification.Name("focusRoomProceedToApproval")

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Group {
                    if hasFinished {
                        endedSection
                    } else {
                        switch peer.state {
                        case .waiting:
                            waitingSection
                        case .readyToStart, .running, .ended:
                            runningSection
                        case .aborted:
                            abortedSection
                        }
                    }
                }
                .padding()
                Spacer()
            }
            .navigationTitle("集中ルーム")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("退出") {
                        peer.broadcast(.leave(participantID: peer.myID))
                        cleanup()
                        dismiss()
                    }
                }
            }
            .onAppear {
                // コールバック登録（分離不要、onAppear inline）
                peer.onStartScheduled = { localStart in
                    self.localStartAt = localStart
                    // 1 秒粒度でカウントダウン。満了判定はホストのみが行い、broadcast(.end) 経由で
                    // 全端末（ホスト含む）が onEnded → finishAndSave する（1Hz 自己申告から脱却）。
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
                // ルーム参加時に既に端末が伏せられている場合、共有 FSM は faceUp 経由の
                // .setting → .armed → .running を要求するため、モーション初期化後に
                // 現在の姿勢を確認して faceDown なら明示的に伝える。
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
                // running に遷移したら faceDown、paused に遷移したら faceUp
                if newPhase == .running && lastMotionPhase != .running {
                    peer.setFaceDown(true)
                } else if newPhase == .paused && lastMotionPhase != .paused {
                    peer.setFaceDown(false)
                }
                lastMotionPhase = newPhase
            }
            .onChange(of: scenePhase) { _, newPhase in
                switch newPhase {
                case .background:
                    // フォアグラウンド限定：background 遷移で退出
                    cleanup()
                    dismiss()
                case .inactive:
                    // 電話着信等の一時的な .inactive は許容。10 秒以上続いたら退出。
                    inactiveWatchTask?.cancel()
                    inactiveWatchTask = Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 10_000_000_000)
                        guard !Task.isCancelled else { return }
                        cleanup()
                        dismiss()
                    }
                default:
                    // .active 復帰：inactive 監視を解除
                    inactiveWatchTask?.cancel()
                    inactiveWatchTask = nil
                }
            }
            .onChange(of: peer.state) { _, newState in
                if newState == .aborted {
                    cleanup()
                }
            }
            .alert("保存に失敗しました", isPresented: .constant(saveErrorMessage != nil)) {
                Button("OK") {
                    saveErrorMessage = nil
                    // hasFinished は既に true で ended 状態から抜けられないため、alert 経由で明示的に閉じる
                    dismiss()
                }
            } message: {
                Text(saveErrorMessage ?? "")
            }
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

    // MARK: - Waiting セクション（ホストは設定＋開始ボタン、ゲストはホスト選択）
    private var waitingSection: some View {
        VStack(spacing: 16) {
            if !isHost && peer.discoveredHosts.isEmpty {
                // どちらでもない：モード選択
                Button("ルームを開く（ホスト）") {
                    isHost = true
                    peer.startHosting()
                }
                .buttonStyle(.borderedProminent)
                Button("ルームに参加") {
                    peer.startBrowsing()
                }
                .buttonStyle(.bordered)
            }

            if isHost {
                Stepper("時間: \(selectedMinutes) 分", value: $selectedMinutes, in: 5 ... 120, step: 5)
                Text("参加者: \(peer.participants.count) / 7")
                    .foregroundStyle(.secondary)
                ForEach(peer.participants) { p in
                    HStack {
                        Circle().fill(p.isFaceDown ? .green : .gray).frame(width: 8, height: 8)
                        Text(p.id + (p.isHost ? " (ホスト)" : ""))
                        Spacer()
                    }
                }
                Text("全員が端末を上下反転すると開始します").font(.caption).foregroundStyle(.secondary)
            }

            if !isHost && !peer.discoveredHosts.isEmpty {
                Text("見つかったホスト").font(.caption)
                ForEach(peer.discoveredHosts, id: \.self) { host in
                    Button(host.displayName) {
                        peer.requestJoin(host: host)
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    // MARK: - Running セクション（同期タイマー、参加者リスト）
    private var runningSection: some View {
        VStack(spacing: 16) {
            if let localStart = localStartAt {
                let elapsed = now.timeIntervalSince1970 - localStart
                let remain = TimeInterval(selectedMinutes * 60) - elapsed
                Text(countdownText(remain))
                    .font(.system(size: 72, weight: .bold, design: .rounded))
                if elapsed < 0 {
                    Text("まもなく開始…").font(.caption).foregroundStyle(.secondary)
                }
            }
            Text("参加中: \(peer.participants.count) 人").font(.caption)
            ForEach(peer.participants) { p in
                HStack {
                    Circle().fill(p.isFaceDown ? .green : .orange).frame(width: 8, height: 8)
                    Text(p.id + (p.isHost ? " (ホスト)" : ""))
                    Spacer()
                }
            }
        }
    }

    // MARK: - 終了・中断
    private var endedSection: some View {
        VStack(spacing: 12) {
            Text("集中セッション終了").font(.title2)
            Text("お疲れさまでした").font(.caption).foregroundStyle(.secondary)
            Button("承認へ進む") {
                NotificationCenter.default.post(name: Self.proceedToApprovalNotification, object: nil)
                dismiss()
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var abortedSection: some View {
        VStack(spacing: 12) {
            Text("ホストが離脱したためルームが中断されました").font(.title3)
            Text("このルームは再開できません").font(.caption).foregroundStyle(.secondary)
            Button("閉じる") { dismiss() }
                .buttonStyle(.bordered)
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
