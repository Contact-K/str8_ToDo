//
//  PeerRoomSession.swift
//  str8ToDo
//
//  集中ルーム（Phase 14）の Multipeer 層。ホスト-ゲスト対称ペアリング。
//  - startHosting(): advertise 開始（ホスト待機）
//  - startBrowsing(): browse 開始（ゲスト探索）
//  - requestJoin(): 発見済みホストに参加リクエスト
//  - broadcast(): 全員に RoomMessage JSON 送信
//  - setFaceDown(): faceDown 状態を更新して broadcast
//  - announceStartIfReady(): 全員 faceDown なら start announce
//  - end(): 終了通知
//  - stop(): 全停止
//  - requestClockSync(): ゲスト側から clock ping を送る
//  フォアグラウンド限定（View 側が ScenePhase で stop() を呼ぶ）。
//

import Foundation
import SwiftUI
import os

#if canImport(MultipeerConnectivity)
import MultipeerConnectivity

@MainActor
@Observable
final class PeerRoomSession: NSObject {
    private let session: MCSession
    private let advertiser: MCNearbyServiceAdvertiser
    private let browser: MCNearbyServiceBrowser
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private(set) var participants: [Participant] = []
    private(set) var state: RoomState = .waiting
    private(set) var myID: String
    private(set) var isHost: Bool = false
    private(set) var clockOffsetToHost: TimeInterval = 0
    private(set) var discoveredHosts: [MCPeerID] = []
    var roomID: UUID = UUID()
    /// TOFU 対策：`requestJoin(host:)` で選んだ peer にのみピン留めする。以後の `.hello` からは確定しない。
    private var hostPeerID: MCPeerID?
    private var pendingPingSentAt: TimeInterval?
    /// pong を1回でも受け取ってオフセットを算出したか。start 受信時のガードに使う。
    private var hasClockSynced: Bool = false
    /// 受信レート制限用の直近タイムスタンプ（.hello / .leave）。peer.displayName ごとに独立させ、1 peer の連投が他 peer を巻き込まないようにする。
    private var helloTimestamps: [String: [TimeInterval]] = [:]
    private var leaveTimestamps: [String: [TimeInterval]] = [:]

    /// FocusSession.approverID に詰める識別子。ホストなら自分の ID、ゲストなら
    /// requestJoin で確定したホストの ID（TaskItem.approverID パターン踏襲）。
    var approverDisplayName: String? {
        isHost ? myID : hostPeerID?.displayName
    }

    var onStateChanged: ((RoomState) -> Void)?
    var onStartScheduled: ((TimeInterval) -> Void)?
    var onEnded: (() -> Void)?
    var onParticipantsChanged: (() -> Void)?

    // serviceType は "str8-focusroom"（15字以内・小文字とハイフンのみ）
    private static let serviceType = "str8-focusroom"

    override init() {
        let peerID = MCPeerID(displayName: Self.displayName)
        self.myID = peerID.displayName
        self.session = MCSession(peer: peerID, securityIdentity: nil, encryptionPreference: .required)
        self.advertiser = MCNearbyServiceAdvertiser(peer: peerID, discoveryInfo: nil, serviceType: Self.serviceType)
        self.browser = MCNearbyServiceBrowser(peer: peerID, serviceType: Self.serviceType)

        super.init()

        session.delegate = self
        advertiser.delegate = self
        browser.delegate = self
    }

    /// displayName: UIDevice.current.name（UIKit 利用可能時）、それ以外は ProcessInfo のホスト名。
    private static var displayName: String {
        #if canImport(UIKit)
        return UIDevice.current.name
        #else
        return ProcessInfo.processInfo.hostName
        #endif
    }

    /// ホストとしてルームを開く（advertise 開始）。
    func startHosting() {
        isHost = true
        participants = [Participant(id: myID, isFaceDown: false, isHost: true)]
        state = .waiting
        advertiser.startAdvertisingPeer()
    }

    /// ゲストとしてブラウズ開始（近くのホストを探す）。
    func startBrowsing() {
        isHost = false
        browser.startBrowsingForPeers()
    }

    /// ゲスト向け：発見済みホストに参加リクエスト。
    /// TOFU 対策：host はここで選んだ peer にのみ確定する（`.hello` からは確定しない）。
    func requestJoin(host: MCPeerID) {
        if hostPeerID == nil {
            hostPeerID = host
        }
        browser.invitePeer(host, to: session, withContext: nil, timeout: 30)
    }

    /// 全員に broadcast（内部で JSON エンコードして MCSession.send に流す）。
    func broadcast(_ message: RoomMessage) {
        guard !session.connectedPeers.isEmpty else { return }

        do {
            let data = try encoder.encode(message)
            try session.send(data, toPeers: session.connectedPeers, with: .reliable)
        } catch {
            // ponytail: 送信失敗は黙って無視
        }
    }

    /// 自分の faceDown 状態を更新して broadcast。
    func setFaceDown(_ isFaceDown: Bool) {
        if let idx = participants.firstIndex(where: { $0.id == myID }) {
            participants[idx].isFaceDown = isFaceDown
        }
        onParticipantsChanged?()
        broadcast(.faceDown(participantID: myID, isFaceDown: isFaceDown))
    }

    /// ホストのみ：全員 faceDown なら hostStartAt を計算して broadcast。
    /// `state != .running` ガードで、開始後に faceDown が再送されても二重 announce しない
    /// （onStartScheduled の二重発火防止）。
    func announceStartIfReady() {
        guard isHost, state != .running, FocusRoom.isReadyToStart(participants: participants) else { return }

        let hostNow = Date().timeIntervalSince1970
        let hostStartAt = FocusRoom.recommendedHostStartAt(hostNow: hostNow)
        broadcast(.start(hostStartAt: hostStartAt, roomID: self.roomID))

        // ホスト側も自分の localStartTime を計算
        let localStart = FocusRoom.localStartTime(hostStartAt: hostStartAt, offset: 0)
        state = .running
        onStateChanged?(state)
        onStartScheduled?(localStart)
    }

    /// 終了通知。ホストの Timer 満了から呼ばれる想定（1Hz 自己申告からの脱却）。
    /// 全端末（ホスト自身含む）は onEnded 経由で finishAndSave する。
    func end() {
        guard FocusRoom.tryTransitionToEnded(&state) else { return }
        broadcast(.end)
        onStateChanged?(state)
        onEnded?()
    }

    /// 終了状態を設定（FocusSession 保存前に呼び出す）。再入ガード付き。
    func markEnded() {
        guard FocusRoom.tryTransitionToEnded(&state) else { return }
        onEnded?()
    }

    /// 停止（advertiser/browser/session を止める）。
    func stop() {
        advertiser.stopAdvertisingPeer()
        browser.stopBrowsingForPeers()
        session.disconnect()
        participants = []
        state = .waiting
        isHost = false
        clockOffsetToHost = 0
        discoveredHosts = []
        hostPeerID = nil
        pendingPingSentAt = nil
        hasClockSynced = false
        helloTimestamps = [:]
        leaveTimestamps = [:]
    }

    /// clock ping-pong を投げる（ゲスト側から起動）。
    func requestClockSync() {
        let pingSentAt = Date().timeIntervalSince1970
        pendingPingSentAt = pingSentAt
        broadcast(.clockPing(pingSentAt: pingSentAt))
    }

    /// 内部: 受信メッセージをハンドル。
    private func handle(_ message: RoomMessage, from peerID: MCPeerID) {
        switch message {
        case .hello(let participantID):
            // 詐称防止：participantID は実際に接続してきた peerID の displayName と一致必須
            guard participantID == peerID.displayName else { return }
            // 受信レート制限（.hello 連投対策、peer ごとに独立）
            guard !FocusRoom.isRateLimited(&helloTimestamps[participantID, default: []], now: Date().timeIntervalSince1970) else { return }
            // 重複メッセージ処理：既に参加済みなら無視
            guard FocusRoom.shouldAddParticipant(existing: participants, id: participantID) else { return }
            // isHost は自己申告を信用しない：自分がホストなら hello の送り主は常にゲスト、
            // 自分がゲストなら requestJoin で確定した hostPeerID と一致するかで判定。
            let helloIsHost = isHost ? false : (peerID == hostPeerID)
            participants.append(Participant(id: participantID, isFaceDown: false, isHost: helloIsHost))
            onParticipantsChanged?()

        case .faceDown(let participantID, let isFaceDown):
            // 詐称防止：participantID は実際に送信してきた peerID の displayName と一致必須
            guard participantID == peerID.displayName else {
                os_log("faceDown participantID mismatch from %{public}s", log: .default, type: .debug, peerID.displayName)
                return
            }
            if let idx = participants.firstIndex(where: { $0.id == participantID }) {
                participants[idx].isFaceDown = isFaceDown
            }
            onParticipantsChanged?()
            // ホストなら ready check
            if isHost {
                announceStartIfReady()
            }

        case .clockPing(let pingSentAt):
            // ホストのみ、送信者に unicast で応答
            guard isHost else { return }
            let hostReplyTime = Date().timeIntervalSince1970
            let pong = RoomMessage.clockPong(pingSentAt: pingSentAt, hostReplyTime: hostReplyTime)
            do {
                let data = try encoder.encode(pong)
                try session.send(data, toPeers: [peerID], with: .reliable)
            } catch {
                // ponytail: unicast 送信失敗は無視
            }

        case .clockPong(let pingSentAt, let hostReplyTime):
            // ゲスト側のみ受信、かつホストからのみ
            guard !isHost, peerID == hostPeerID else { return }
            // 自分が送った pending ping と対応するか検証
            guard pingSentAt == pendingPingSentAt else { return }
            pendingPingSentAt = nil
            // offset を計算
            let pongReceivedAt = Date().timeIntervalSince1970
            clockOffsetToHost = FocusRoom.clockOffset(pingSentAt: pingSentAt, pongReceivedAt: pongReceivedAt, hostReplyTime: hostReplyTime)
            self.hasClockSynced = true

        case .start(let hostStartAt, let receivedRoomID):
            // ゲスト側のみ受信、かつホストからのみ
            guard !isHost, peerID == hostPeerID else { return }
            // 二重発火防止：既に running なら再announceを無視
            guard state != .running else { return }
            // クロック同期未完了で start を受け付けると過去/未来にジャンプしうる。安全側に aborted。
            guard hasClockSynced else {
                self.state = .aborted
                self.onStateChanged?(self.state)
                return
            }
            // ゲスト側でホストの roomID を上書き
            self.roomID = receivedRoomID
            // localStartTime を計算
            let localStart = FocusRoom.localStartTime(hostStartAt: hostStartAt, offset: clockOffsetToHost)
            state = .running
            onStateChanged?(state)
            onStartScheduled?(localStart)

        case .end:
            // ゲスト側のみ受信、かつホストからのみ
            guard !isHost, peerID == hostPeerID else { return }
            guard FocusRoom.tryTransitionToEnded(&state) else { return }
            onStateChanged?(state)
            onEnded?()

        case .leave(let participantID):
            guard peerID.displayName == participantID else { return }
            // 受信レート制限（.leave 連投対策、peer ごとに独立）
            guard !FocusRoom.isRateLimited(&leaveTimestamps[participantID, default: []], now: Date().timeIntervalSince1970) else { return }
            participants.removeAll { $0.id == participantID }
            onParticipantsChanged?()
            let nextState = FocusRoom.nextStateAfterLeft(current: state, remaining: participants)
            if nextState != state {
                state = nextState
                onStateChanged?(state)
            }
        }
    }
}

// MARK: - MainActor 集約ハンドラ
//
// MCNearbyServiceAdvertiser と MCSession は別々の内部キューから delegate を呼ぶため、
// 満員判定（advertiser）と切断反映（session:peer:didChange:）が実イベント順と食い違う余地がある。
// 両方の本体を @MainActor メソッドに集約し、nonisolated 側は Task { @MainActor in ... } で
// この単一の実行列に乗せるだけにする（MainActor は直列実行なので、ここに来た時点で順序が揃う）。
extension PeerRoomSession {
    @MainActor
    private func handlePeerStateChange(peerID: MCPeerID, state: MCSessionState) {
        switch state {
        case .connected:
            // 接続完了時に hello を送る（isHost は自己申告しない）
            self.broadcast(.hello(participantID: self.myID))
            // ゲスト側のみ clock sync を要求
            if !self.isHost {
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
                    self.requestClockSync()
                }
            }

        case .notConnected:
            // 切断された参加者を削除
            let participantID = peerID.displayName
            self.participants.removeAll { $0.id == participantID }
            self.onParticipantsChanged?()
            let nextState = FocusRoom.nextStateAfterLeft(current: self.state, remaining: self.participants)
            if nextState != self.state {
                self.state = nextState
                self.onStateChanged?(nextState)
            }

        case .connecting:
            break
        @unknown default:
            break
        }
    }

    @MainActor
    private func handleInvitation(from peerID: MCPeerID, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        // ponytail: 参加人数制限（MCSession standard max = 8、ここでは 7 上限）
        if self.participants.count >= 7 {
            invitationHandler(false, nil)
            return
        }
        // 自動 accept
        invitationHandler(true, self.session)
    }
}

// MARK: - MCSessionDelegate

extension PeerRoomSession: MCSessionDelegate {
    nonisolated func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        Task { @MainActor in
            self.handlePeerStateChange(peerID: peerID, state: state)
        }
    }

    nonisolated func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        let decoder = JSONDecoder()
        do {
            let message = try decoder.decode(RoomMessage.self, from: data)
            Task { @MainActor in
                self.handle(message, from: peerID)
            }
        } catch {
            os_log("decode failed from %{public}s", log: .default, type: .debug, peerID.displayName)
        }
    }

    nonisolated func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {
        // 未使用
    }

    nonisolated func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {
        // 未使用
    }

    nonisolated func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: (any Error)?) {
        // 未使用
    }
}

// MARK: - MCNearbyServiceAdvertiserDelegate

extension PeerRoomSession: MCNearbyServiceAdvertiserDelegate {
    nonisolated func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {
        // ponytail: エラーログ省略
    }

    nonisolated func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        Task { @MainActor in
            self.handleInvitation(from: peerID, invitationHandler: invitationHandler)
        }
    }
}

// MARK: - MCNearbyServiceBrowserDelegate

extension PeerRoomSession: MCNearbyServiceBrowserDelegate {
    nonisolated func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        // ponytail: エラーログ省略
    }

    nonisolated func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String : String]?) {
        Task { @MainActor in
            // 見つかったホストを登録（重複排除）
            if !self.discoveredHosts.contains(peerID) {
                self.discoveredHosts.append(peerID)
            }
        }
    }

    nonisolated func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        Task { @MainActor in
            self.discoveredHosts.removeAll { $0 == peerID }
        }
    }
}

#endif
