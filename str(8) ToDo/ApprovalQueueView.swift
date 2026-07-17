//
//  ApprovalQueueView.swift
//  str8ToDo
//
//  Phase 17: ApprovalQueueView struct は削除し、TodoListView に統合済み。
//  このファイルはペアリング画面（PeerPairingView）と共有 Shape (SemiArc) のみを保持。
//  ファイル名は履歴保持のため据え置き（pbxproj 更新回避）。
//

import SwiftUI
import SwiftData

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
            // Handoff ヘッダ: タイトル / 開始・停止（ボタンサイズを他画面と揃える）
            HStack {
                Text("ペアリング").font(S8Font.jp(16, .bold)).foregroundColor(c.fg1)
                Spacer()
                let active = session.isConnected || session.isSearching
                S8Button(
                    active ? "停止" : "開始",
                    icon: active ? "x" : "plus",
                    variant: active ? .secondary : .primary,
                    fillWidth: false,
                    action: { active ? session.stop() : session.start() }
                )
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

                    // ponytail: DEBUG simulatorBypass セクションは撤去（本番向け）

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
