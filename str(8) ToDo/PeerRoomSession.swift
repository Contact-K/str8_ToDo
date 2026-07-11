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
    private var hostPeerID: MCPeerID?
    private var pendingPingSentAt: TimeInterval?

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
    func requestJoin(host: MCPeerID) {
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
    func announceStartIfReady() {
        guard isHost, FocusRoom.isReadyToStart(participants: participants) else { return }

        let hostNow = Date().timeIntervalSince1970
        let hostStartAt = FocusRoom.recommendedHostStartAt(hostNow: hostNow)
        broadcast(.start(hostStartAt: hostStartAt, roomID: self.roomID))

        // ホスト側も自分の localStartTime を計算
        let localStart = FocusRoom.localStartTime(hostStartAt: hostStartAt, offset: 0)
        state = .running
        onStateChanged?(state)
        onStartScheduled?(localStart)
    }

    /// 終了通知。
    func end() {
        broadcast(.end)
        state = .ended
        onStateChanged?(state)
        onEnded?()
    }

    /// 終了状態を設定（FocusSession 保存前に呼び出す）。
    func markEnded() {
        guard self.state != .ended else { return }
        self.state = .ended
        self.onEnded?()
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
        case .hello(let participantID, let isHostFlag):
            // ゲスト側でホストの peerID を記録（初回のみ）
            if isHostFlag && !isHost && hostPeerID == nil {
                hostPeerID = peerID
            }
            // 既存の参加者なら無視
            guard !participants.contains(where: { $0.id == participantID }) else { return }
            participants.append(Participant(id: participantID, isFaceDown: false, isHost: isHostFlag))
            onParticipantsChanged?()

        case .faceDown(let participantID, let isFaceDown):
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

        case .start(let hostStartAt, let receivedRoomID):
            // ゲスト側のみ受信、かつホストからのみ
            guard !isHost, peerID == hostPeerID else { return }
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
            state = .ended
            onStateChanged?(state)
            onEnded?()

        case .leave(let participantID):
            guard peerID.displayName == participantID else { return }
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

// MARK: - MCSessionDelegate

extension PeerRoomSession: MCSessionDelegate {
    nonisolated func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        Task { @MainActor in
            switch state {
            case .connected:
                // 接続完了時に hello を送る
                let isHostFlag = self.isHost
                self.broadcast(.hello(participantID: self.myID, isHost: isHostFlag))
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
            // ponytail: 参加人数制限（MCSession standard max = 8、ここでは 7 上限）
            if self.participants.count >= 7 {
                invitationHandler(false, nil)
                return
            }
            // 自動 accept
            invitationHandler(true, self.session)
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
