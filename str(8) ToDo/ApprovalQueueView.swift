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
    @Environment(\.colorScheme) private var scheme
    private var c: S8Palette { S8Palette.of(scheme) }
    @Query private var allTasks: [TaskItem]
    @State private var peerSession = PeerSession()
    @State private var proximityGate = ProximityGate()
    @State private var showPeerPairing = false

    private var doneTasks: [TaskItem] {
        allTasks.filter { $0.status == .done }
    }

    private var lockedTasks: [TaskItem] { doneTasks.filter { $0.isAwaitingFutureSelf } }
    private var readyTasks: [TaskItem] { doneTasks.filter { !$0.isAwaitingFutureSelf } }

    #if canImport(CoreMotion) && os(iOS)
    @State private var chopService = ChopMotionService()
    #endif

    var body: some View {
        let c = self.c
        VStack(spacing: 0) {
            S8TopBar("承認", sub: "queue · self-approve tomorrow") {
                S8IconButton(icon: "users", accent: peerSession.isConnected, action: { showPeerPairing = true })
                    .accessibilityLabel("ペアリング")
            }

            HStack {
                S8Button("今週を締める", icon: "calendar-days", variant: .secondary, fillWidth: false, action: { showWeekReview = true })
                Spacer()
            }
            .padding(.horizontal, 24).padding(.bottom, 12)

            if doneTasks.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        if !lockedTasks.isEmpty {
                            sectionHeader("LOCKED", jp: "ロック中")
                            ForEach(lockedTasks) { task in lockedRow(task) }
                        }
                        if !readyTasks.isEmpty {
                            sectionHeader("READY", jp: "承認待ち")
                            ForEach(readyTasks) { task in readyRow(task) }
                            #if canImport(CoreMotion) && os(iOS)
                            chopMeter
                                .padding(.horizontal, 24).padding(.top, 22)
                            #endif
                        }
                        Color.clear.frame(height: 24)
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
        .background(c.paper.ignoresSafeArea())
        .sheet(isPresented: $showPeerPairing) {
            NavigationStack {
                PeerPairingView(session: peerSession, gate: proximityGate)
            }
        }
    }

    // MARK: - 行

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
            S8Icon(name: "lock", size: 16, color: c.fg3)
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
                // ペアに依頼（接続中のみ）
                if peerSession.isConnected {
                    S8IconButton(icon: "send", action: {
                        peerSession.send(.request(taskID: task.id, title: task.title))
                    })
                    .accessibilityLabel("ペアに依頼")
                }
                // 確定ボタン
                S8IconButton(icon: "check", accent: true, action: {
                    _ = task.approve(by: "self-future", context: context)
                    try? context.save()   // P11 #2: 承認を即永続化→ModelContext.didSave で widget 反映
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
        let thr = ChopStateMachine.Tuning.peakThreshold                            // 2.0
        let progress = min(max(0, mag / (thr * 1.4)), 1)                            // 0..1
        let angle = -120.0 + progress * 240.0                                       // -120..+120°
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
                // 針
                Rectangle().fill(c.accent).frame(width: 2, height: 13)
                    .offset(y: -35)
                    .rotationEffect(.degrees(angle))
                    .animation(.easeOut(duration: 0.12), value: mag)
                // 目盛ティック（頂点・左右）
                ForEach([-120.0, 0.0, 120.0], id: \.self) { deg in
                    Rectangle().fill(c.lineStrong).frame(width: 1, height: 5)
                        .offset(y: -44)
                        .rotationEffect(.degrees(deg))
                }
                // 中央 readout
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

    private var emptyState: some View {
        VStack(spacing: 8) {
            S8Icon(name: "check-circle", size: 34, color: c.fg3)
            Text("承認なし").font(S8Font.jp(15, .bold)).foregroundColor(c.fg1)
            Text("完了待ちのタスクはありません。").font(S8Font.jp(13)).foregroundColor(c.fg3)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24).padding(.vertical, 48)
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
}

#Preview {
    ApprovalQueueView(showWeekReview: .constant(false))
        .modelContainer(PreviewData.container)
}

// MARK: - PeerPairingView（Handoff 04b: LINK + PROXIMITY + REQUESTS）
//
// MPC 接続 + UWB 近接ゲート（≦10cm）。近接中のみ「承認」が活性。

struct PeerPairingView: View {
    let session: PeerSession
    let gate: ProximityGate
    @Environment(\.scenePhase) var scenePhase
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    private var c: S8Palette { S8Palette.of(scheme) }

    var body: some View {
        let c = self.c
        VStack(spacing: 0) {
            // Handoff ヘッダ: 空 / タイトル / 開始・停止
            HStack {
                Color.clear.frame(width: 64, height: 1)
                Spacer()
                Text("ペアリング").font(S8Font.jp(16, .bold)).foregroundColor(c.fg1)
                Spacer()
                Button(action: { session.isConnected ? session.stop() : session.start() }) {
                    Text(session.isConnected ? "停止" : "開始")
                        .font(S8Font.jp(14))
                        .foregroundColor(c.fg2)
                }
                .frame(width: 64, alignment: .trailing)
            }
            .padding(.horizontal, 24).padding(.vertical, 12)

            ScrollView {
                VStack(spacing: 0) {
                    // LINK section
                    sectionCap("LINK", jp: "接続")
                        .padding(.top, 8)
                    linkRow()

                    // ペアリング確認
                    if let invitation = session.pendingInvitation {
                        invitationRow(peerName: invitation.peerName, decide: invitation.decide)
                            .padding(.top, 6)
                    }

                    // PROXIMITY section
                    sectionCap("PROXIMITY", jp: "近接ゲート")
                        .padding(.top, 22)
                    proximityGauge()
                        .padding(.top, 4)

                    // REQUESTS section
                    if !session.receivedRequests.isEmpty {
                        sectionCap("REQUESTS", jp: "承認依頼")
                            .padding(.top, 22)
                        ForEach(session.receivedRequests) { request in
                            requestRow(request)
                        }
                        Text("承認側が端末を振り下ろすとスタンプが押される")
                            .font(S8Font.jp(11)).foregroundColor(c.fg3)
                            .padding(.top, 6)
                    }

                    // DEBUG simulatorBypass
                    #if DEBUG
                    sectionCap("DEBUG", jp: "テスト")
                        .padding(.top, 22)
                    Button(action: { gate.simulatorBypass.toggle() }) {
                        HStack {
                            Text("近接をシミュレート").font(S8Font.jp(14)).foregroundColor(c.fg1)
                            Spacer()
                            S8Icon(name: gate.simulatorBypass ? "check-circle" : "circle-dot",
                                   size: 17, color: gate.simulatorBypass ? c.ok : c.fg3)
                        }
                        .padding(.vertical, 13)
                        .overlay(alignment: .top) { S8Rule() }
                    }
                    .buttonStyle(.plain)
                    #endif

                    Color.clear.frame(height: 24)
                }
                .padding(.horizontal, 24)
            }
        }
        .background(c.paper.ignoresSafeArea())
        .onAppear { session.start() }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background { session.stop() }
        }
        .onDisappear { session.stop() }
    }

    private func sectionCap(_ tag: String, jp: String) -> some View {
        HStack(spacing: 10) {
            Text(tag).font(S8Font.mono(10)).tracking(1.6).foregroundColor(c.fg3)
            Text(jp).font(S8Font.jp(13, .medium)).foregroundColor(c.fg2)
            S8Rule()
        }
        .padding(.bottom, 8)
    }

    private func linkRow() -> some View {
        HStack(spacing: 10) {
            S8Icon(name: session.isConnected ? "check-circle" : "circle-dot",
                   size: 17, color: session.isConnected ? c.ok : c.fg3)
            Text(session.isConnected ? (session.connectedPeerName ?? "接続中") : "未接続")
                .font(S8Font.jp(14, session.isConnected ? .bold : .medium))
                .foregroundColor(c.fg1)
            Spacer()
            if session.isConnected {
                S8QualityBars(quality: 3, connected: true)
                Text("CONNECTED")
                    .font(S8Font.mono(10)).tracking(1.2).foregroundColor(c.ok)
            }
        }
        .padding(.vertical, 12)
        .overlay(alignment: .top) { S8Rule() }
    }

    private func invitationRow(peerName: String, decide: @escaping (Bool) -> Void) -> some View {
        HStack(spacing: 10) {
            Text("\(peerName) とペアリングしますか？")
                .font(S8Font.jp(14)).foregroundColor(c.fg1)
            Spacer()
            Button("拒否") { decide(false) }
                .font(S8Font.jp(13))
                .foregroundColor(c.fg2)
                .padding(.horizontal, 12).padding(.vertical, 7)
                .overlay(RoundedRectangle(cornerRadius: S8Radius.md).stroke(c.lineStrong, lineWidth: 1))
            Button("承諾") { decide(true) }
                .font(S8Font.jp(13, .bold))
                .foregroundColor(c.onAccent)
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(c.accent)
                .clipShape(RoundedRectangle(cornerRadius: S8Radius.md))
        }
        .padding(14)
        .background(c.surface)
        .overlay(RoundedRectangle(cornerRadius: S8Radius.md).stroke(c.lineStrong, lineWidth: 1))
    }

    /// Handoff 04b: UWB RANGE 半円ゲージ。単位 m、近接=ok 塗り、遠=surface2。
    private func proximityGauge() -> some View {
        let dist = gate.lastDistance
        let clamped = min(1.0, dist ?? 1.0)
        let progress = 1.0 - clamped  // 近い＝1、遠い＝0
        return VStack(spacing: 8) {
            HStack {
                Text("NI · UWB — RANGE")
                    .font(S8Font.mono(9.5)).tracking(1.6).foregroundColor(c.fg3)
                Spacer()
            }
            // 半円 arc
            ZStack {
                SemiArc(progress: 1.0)
                    .stroke(c.surface2, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                SemiArc(progress: progress)
                    .stroke(gate.isNear ? c.ok : c.warn, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                VStack(spacing: 0) {
                    Spacer()
                    HStack(alignment: .lastTextBaseline, spacing: 2) {
                        Text(dist.map { String(format: "%.2f", $0) } ?? "—")
                            .font(S8Font.mono(22, .bold)).foregroundColor(gate.isNear ? c.ok : c.fg1)
                        Text("m").font(S8Font.mono(11)).foregroundColor(c.fg3)
                    }
                }
                .padding(.bottom, 4)
            }
            .frame(width: 132, height: 70)
            Text(proximityStatusText())
                .font(S8Font.jp(11.5, .bold))
                .foregroundColor(gate.isNear ? c.ok : c.fg3)
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .background(c.surface)
        .overlay(
            RoundedRectangle(cornerRadius: 0).stroke(c.lineStrong, lineWidth: 1)
        )
    }

    private func proximityStatusText() -> String {
        if let reason = gate.unavailableReason { return reason }
        if gate.isNear { return "近接中 ── 承認ゲート開" }
        return "近接待機中"
    }

    private func requestRow(_ request: PeerApprovalRequest) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(request.title).font(S8Font.jp(14.5, .bold)).foregroundColor(c.fg1).lineLimit(1)
                HStack(spacing: 4) {
                    Text("FROM \(request.from) ·").font(S8Font.mono(10.5)).foregroundColor(c.fg3)
                    Text(String(request.taskID.uuidString.prefix(8)))
                        .font(S8Font.mono(10.5)).foregroundColor(c.fg3)
                }
            }
            Spacer()
            Button {
                session.send(.approved(taskID: request.taskID))
                session.removeRequest(id: request.taskID)
            } label: {
                Text("承認")
                    .font(S8Font.jp(13, .bold))
                    .foregroundColor((gate.isNear || gate.simulatorBypass) ? c.onAccent : c.fg3)
                    .padding(.horizontal, 16).padding(.vertical, 9)
                    .background((gate.isNear || gate.simulatorBypass) ? c.accent : c.surface2)
                    .clipShape(RoundedRectangle(cornerRadius: S8Radius.md))
            }
            .buttonStyle(.plain)
            .disabled(!(gate.isNear || gate.simulatorBypass))
        }
        .padding(.vertical, 13)
        .overlay(alignment: .top) { S8Rule() }
    }
}

/// 半円 arc: 左端(180°)から右端(0°)へ progress で塗る。
private struct SemiArc: Shape {
    let progress: Double
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let r = min(rect.width / 2, rect.height)
        let center = CGPoint(x: rect.midX, y: rect.maxY)
        let end = Angle.degrees(180 + max(0, min(1, progress)) * 180)
        p.addArc(center: center, radius: r - 4,
                 startAngle: .degrees(180), endAngle: end, clockwise: false)
        return p
    }
}
