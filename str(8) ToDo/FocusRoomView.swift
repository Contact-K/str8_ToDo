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

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Group {
                    switch peer.state {
                    case .waiting:
                        waitingSection
                    case .readyToStart, .running:
                        runningSection
                    case .ended:
                        endedSection
                    case .aborted:
                        abortedSection
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
                        peer.stop()
                        dismiss()
                    }
                }
            }
            .onAppear {
                setupCallbacks()
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
                motion.stop()
                peer.stop()
                timer?.invalidate()
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
                // フォアグラウンド限定：background 遷移で退出（.inactive は無視）
                if newPhase == .background {
                    peer.stop()
                    motion.stop()
                    timer?.invalidate()
                    dismiss()
                }
            }
            .onChange(of: peer.state) { _, newState in
                if newState == .aborted {
                    timer?.invalidate()
                    timer = nil
                    peer.stop()
                    motion.stop()
                }
            }
            .alert("保存に失敗しました", isPresented: .constant(saveErrorMessage != nil)) {
                Button("OK") { saveErrorMessage = nil }
            } message: {
                Text(saveErrorMessage ?? "")
            }
        }
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
                Text("全員が端末を伏せると開始します").font(.caption).foregroundStyle(.secondary)
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
                let remain = max(0, TimeInterval(selectedMinutes * 60) - elapsed)
                Text("\(Int(remain / 60)):\(String(format: "%02d", Int(remain.truncatingRemainder(dividingBy: 60))))")
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
        VStack {
            Text("集中セッション終了").font(.title2)
            Text("承認へ進みます").font(.caption).foregroundStyle(.secondary)
        }
    }

    private var abortedSection: some View {
        VStack {
            Text("ルームが中断されました").font(.title3)
            Button("閉じる") { dismiss() }
                .buttonStyle(.bordered)
        }
    }

    // MARK: - コールバック
    private func setupCallbacks() {
        peer.onStartScheduled = { localStart in
            self.localStartAt = localStart
            // 1 秒粒度でカウントダウン
            self.timer?.invalidate()
            self.timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
                self.now = .now
                let elapsed = self.now.timeIntervalSince1970 - localStart
                if elapsed >= Double(self.selectedMinutes * 60) {
                    self.finishAndSave()
                }
            }
        }
        peer.onEnded = {
            self.finishAndSave()
        }
    }

    // MARK: - 終了時に FocusSession を保存
    private func finishAndSave() {
        guard !hasFinished else { return }
        hasFinished = true
        timer?.invalidate()
        timer = nil
        peer.markEnded()
        guard let localStart = localStartAt else { return }
        let start = Date(timeIntervalSince1970: localStart)
        let end = Date(timeIntervalSince1970: localStart + Double(selectedMinutes * 60))
        let session = FocusSession.record(start: start, end: end, task: nil, subject: nil, context: context)
        session.roomID = peer.roomID
        session.participantCount = peer.participants.count
        do {
            try context.save()
        } catch {
            os_log("FocusRoom save failed: %@", log: .default, type: .error, error.localizedDescription)
            saveErrorMessage = "保存に失敗しました：\(error.localizedDescription)"
            return
        }
        motion.stop()
        // 数秒後に dismiss と peer.stop()
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            peer.stop()
            dismiss()
        }
    }
}

#Preview {
    FocusRoomView().modelContainer(PreviewData.container)
}
