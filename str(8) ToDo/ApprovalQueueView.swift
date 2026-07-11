//
//  ApprovalQueueView.swift
//  str8ToDo
//
//  承認キューの表示と操作。done ステータスのタスク一覧。
//  実機では ChopMotionService で物理ハンコの検出に対応。
//

import SwiftUI
import SwiftData

#if canImport(CoreMotion) && os(iOS)
import CoreMotion
#endif

struct ApprovalQueueView: View {
    @Binding var showWeekReview: Bool
    @Environment(\.modelContext) private var context
    @Query private var allTasks: [TaskItem]
    @State private var peerSession = PeerSession()
    @State private var proximityGate = ProximityGate()

    private var doneTasks: [TaskItem] {
        allTasks.filter { $0.status == .done }
    }

    #if canImport(CoreMotion) && os(iOS)
    @State private var chopService = ChopMotionService()
    #endif

    var body: some View {
        NavigationStack {
            if doneTasks.isEmpty {
                ContentUnavailableView {
                    Label("承認なし", systemImage: "checkmark.seal.fill")
                } description: {
                    Text("完了待ちのタスクはありません。")
                }
                .navigationTitle("承認キュー")
                .toolbar {
                    // 承認漏れがなくても、一掃済みの状態から週を締められるように空状態でも表示する
                    ToolbarItem(placement: .primaryAction) {
                        Button(action: { showWeekReview = true }) {
                            Label("今週を締める", systemImage: "calendar.badge.checkmark")
                        }
                    }
                }
            } else {
                List {
                    let locked = doneTasks.filter { $0.isAwaitingFutureSelf }
                    let ready = doneTasks.filter { !$0.isAwaitingFutureSelf }

                    if !locked.isEmpty {
                        Section("ロック中") {
                            ForEach(locked) { task in
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(task.title)
                                            .font(.body)
                                        if let unlockDate = task.unlockDate {
                                            Text(unlockDate, style: .relative)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    Spacer()
                                    Image(systemName: "lock.fill")
                                        .foregroundStyle(.secondary)
                                }
                                .contentShape(Rectangle())
                            }
                        }
                    }

                    if !ready.isEmpty {
                        Section("承認待ち") {
                            ForEach(ready) { task in
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(task.title)
                                            .font(.body)
                                        if let completedAt = task.completedAt {
                                            Text(completedAt, style: .time)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    Spacer()
                                    // ペアに依頼（接続中のみ）
                                    if peerSession.isConnected {
                                        Button(action: {
                                            peerSession.send(.request(taskID: task.id, title: task.title))
                                        }) {
                                            Image(systemName: "person.fill.checkmark")
                                                .foregroundStyle(.blue)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                    // 確定ボタン
                                    Button(action: {
                                        _ = task.approve(by: "self-future", context: context)
                                        try? context.save()   // P11 #2: 承認を即永続化→ModelContext.didSave で widget 反映
                                    }) {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(.green)
                                    }
                                    .buttonStyle(.plain)
                                }
                                .contentShape(Rectangle())
                            }
                        }
                    }
                }
                .navigationTitle("承認キュー")
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        NavigationLink(destination: PeerPairingView(session: peerSession, gate: proximityGate)) {
                            Image(systemName: "person.2")
                        }
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Button(action: { showWeekReview = true }) {
                            Label("今週を締める", systemImage: "calendar.badge.checkmark")
                        }
                    }
                }
                #if canImport(CoreMotion) && os(iOS)
                .onAppear {
                    chopService.onChop = {
                        // 承認待ちの先頭1件を確定
                        if let first = doneTasks.first(where: { !$0.isAwaitingFutureSelf }) {
                            _ = first.approve(by: "self-future", context: context)
                            try? context.save()   // P11 #2: didSave で widget 反映
                        }
                    }
                    chopService.start()
                }
                .onDisappear {
                    chopService.stop()
                }
                #endif
                .onAppear {
                    // ペアセッション: メッセージ受信ハンドラ（分離版）
                    peerSession.onApproved = { taskID, senderName in
                        // 依頼側: 対応タスクを承認済みに変更
                        if let task = allTasks.first(where: { $0.id == taskID }) {
                            _ = task.approve(by: senderName, context: context, bypassesLock: true)
                            try? context.save()   // P11 #2: didSave で widget 反映
                        }
                    }

                    peerSession.onNIToken = { data in
                        // 相手の NI token を受信 → ProximityGate で測定開始。
                        // 空データ = 相手が UWB 非対応の合図 → 双方 BLE フォールバックに揃える
                        if data.isEmpty {
                            proximityGate.startFallback()
                        } else {
                            proximityGate.start(withPeerToken: data)
                        }
                    }

                    // ペア接続成功時: 自分の NI token を送信。
                    // 非対応機はトークンが無いので空データを送る（BLE でやろうの合図）
                    peerSession.onPeerConnected = { _ in
                        peerSession.send(.niToken(proximityGate.localTokenData ?? Data()))
                    }
                }
            }
        }
    }
}

#Preview {
    ApprovalQueueView(showWeekReview: .constant(false))
        .modelContainer(PreviewData.container)
}

// MARK: - PeerPairingView

/// ペアリングと承認の UI。PeerSession.receivedRequests を表示、
/// 承認時に approved を send back。pendingInvitation で相手からのペアリング確認を表示。
/// ProximityGate の isNear がプロキシ側のボタン活性化を制御する。

struct PeerPairingView: View {
    let session: PeerSession
    let gate: ProximityGate
    @Environment(\.scenePhase) var scenePhase

    var body: some View {
        VStack(spacing: 16) {
            // 接続状態
            Section("接続") {
                if session.isConnected {
                    Label(session.connectedPeerName ?? "接続中", systemImage: "checkmark.circle.fill")
                        .foregroundColor(.green)
                } else {
                    Label("未接続", systemImage: "circle")
                        .foregroundColor(.gray)
                }
            }

            // 開始/停止ボタン
            HStack {
                if session.isConnected {
                    Button("停止", action: { session.stop() })
                        .buttonStyle(.bordered)
                } else {
                    Button("開始", action: { session.start() })
                        .buttonStyle(.bordered)
                }
            }

            // 近接状態の表示と診断
            Section("近接") {
                if gate.unavailableReason != nil {
                    Text(gate.unavailableReason ?? "不明")
                        .font(.caption)
                        .foregroundColor(.orange)
                } else if gate.isNear {
                    Label("近接中", systemImage: "checkmark.circle.fill")
                        .foregroundColor(.green)
                } else {
                    Label("遠い", systemImage: "circle")
                        .foregroundColor(.gray)
                }
            }

            // ペアリング確認ダイアログ
            if let invitation = session.pendingInvitation {
                Section("ペアリング確認") {
                    HStack {
                        VStack(alignment: .leading) {
                            Text("\(invitation.peerName) とペアリングしますか？")
                                .font(.body)
                        }
                        Spacer()
                        Button("拒否", action: {
                            invitation.decide(false)
                        })
                        .buttonStyle(.bordered)
                        Button("承諾", action: {
                            invitation.decide(true)
                        })
                        .buttonStyle(.bordered)
                        .tint(.green)
                    }
                    .padding(.vertical, 8)
                }
            }

            // 承認依頼一覧
            if !session.receivedRequests.isEmpty {
                Section("承認依頼") {
                    ForEach(session.receivedRequests) { request in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(request.title)
                                    .font(.headline)
                                HStack {
                                    Text(request.from)
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                    Spacer()
                                    Text(request.taskID.uuidString.prefix(8))
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                }
                            }
                            Spacer()
                            Button("承認", action: {
                                session.send(.approved(taskID: request.taskID))
                                session.removeRequest(id: request.taskID)
                            })
                            .buttonStyle(.bordered)
                            .disabled(!(gate.isNear || gate.simulatorBypass))
                        }
                        .padding(.vertical, 8)
                    }
                }
            }

            // DEBUG: simulatorBypass トグル
            #if DEBUG
            Section("テスト") {
                Button(action: {
                    gate.simulatorBypass.toggle()
                }) {
                    HStack {
                        Text("近接をシミュレート")
                        Spacer()
                        Image(systemName: gate.simulatorBypass ? "checkmark.circle.fill" : "circle")
                            .foregroundColor(gate.simulatorBypass ? .green : .gray)
                    }
                }
            }
            #endif

            Spacer()
        }
        .padding()
        .navigationTitle("ペアリング")
        .onAppear {
            session.start()
        }
        .onChange(of: scenePhase) { oldPhase, newPhase in
            if newPhase == .background {
                session.stop()
            }
        }
        .onDisappear {
            session.stop()
        }
    }
}
