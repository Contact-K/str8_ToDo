//
//  PeerSession.swift
//  str8ToDo
//
//  MultipeerConnectivity ラッパー。ペアの相手に done タスクの承認を依頼。
//  - start(): advertiser + browser 同時起動（対称ペアリング、見つけたら自動 invite / 招待確認ダイアログ）
//  - stop(): 全停止 + 切断
//  - send(): ApprovalMessage を JSON エンコード送信
//  - receivedRequests: 受信した承認依頼リスト
//  - onApproved/onNIToken: 分離されたハンドラ（ApprovalQueueView のみ設定）
//  フォアグラウンド限定（View 側が ScenePhase を監視して stop() を呼ぶ）。
//  NI 連携用: ApprovalMessage に niToken(Data) を足す（最小）。
//

import Foundation
import SwiftUI

#if canImport(MultipeerConnectivity)
import MultipeerConnectivity

struct PeerApprovalRequest: Identifiable {
    let id = UUID()
    let taskID: UUID
    let title: String
    let from: String
}

@MainActor
@Observable
final class PeerSession: NSObject {
    private let session: MCSession
    private let advertiser: MCNearbyServiceAdvertiser
    private let browser: MCNearbyServiceBrowser
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private(set) var connectedPeerName: String?
    private(set) var isConnected = false
    /// start() 後、まだ peer が接続していない探索状態。UI 側で「タップ即反応」の視覚フィードバックに使う。
    private(set) var isSearching = false
    private(set) var receivedRequests: [PeerApprovalRequest] = []
    private(set) var pendingInvitation: (peerName: String, decide: (Bool) -> Void)?
    
    var onApproved: ((UUID, String) -> Void)?
    var onNIToken: ((Data) -> Void)?
    var onPeerConnected: ((String) -> Void)?

    // serviceType は "str8-approve"（15字以内・小文字とハイフンのみ）
    private static let serviceType = "str8-approve"

    override init() {
        let peerID = MCPeerID(displayName: Self.displayName)
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

    /// advertiser + browser 同時起動。見つけたら自動 invite。
    func start() {
        advertiser.startAdvertisingPeer()
        browser.startBrowsingForPeers()
        isSearching = true
    }

    /// 全停止 + 切断。
    func stop() {
        advertiser.stopAdvertisingPeer()
        browser.stopBrowsingForPeers()
        session.disconnect()
        connectedPeerName = nil
        isConnected = false
        isSearching = false
        receivedRequests = []
        pendingInvitation = nil
    }

    /// ApprovalMessage を JSON エンコード送信。
    func send(_ message: ApprovalMessage) {
        guard isConnected else { return }

        do {
            let data = try encoder.encode(message)
            try session.send(data, toPeers: session.connectedPeers, with: .reliable)
        } catch {
            // ponytail: 送信失敗は黙って無視（実装段階でデバッグ可能）
        }
    }

    /// 承認依頼を削除（PeerPairingView が承認時に呼び出す）。
    func removeRequest(id: UUID) {
        receivedRequests.removeAll { $0.taskID == id }
    }
}

// MARK: - MCSessionDelegate

extension PeerSession: MCSessionDelegate {
    nonisolated func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        Task { @MainActor in
            switch state {
            case .connected:
                self.connectedPeerName = peerID.displayName
                self.isConnected = true
                self.isSearching = false
                self.onPeerConnected?(peerID.displayName)
            case .notConnected:
                self.connectedPeerName = nil
                self.isConnected = false
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
            let message = try decoder.decode(ApprovalMessage.self, from: data)
            Task { @MainActor in
                self.handleReceivedMessage(message, from: peerID.displayName)
            }
        } catch {
            // ponytail: デコード失敗は無視
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

    private nonisolated func handleReceivedMessage(_ message: ApprovalMessage, from senderName: String) {
        Task { @MainActor in
            switch message {
            case .request(let taskID, let title):
                // 同じ taskID の重複は無視
                guard !self.receivedRequests.contains(where: { $0.taskID == taskID }) else { return }
                self.receivedRequests.append(PeerApprovalRequest(taskID: taskID, title: title, from: senderName))
            case .approved(let taskID):
                self.onApproved?(taskID, senderName)
            case .niToken(let data):
                self.onNIToken?(data)
            }
        }
    }
}

// MARK: - MCNearbyServiceAdvertiserDelegate

extension PeerSession: MCNearbyServiceAdvertiserDelegate {
    nonisolated func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {
        // ponytail: エラーログ省略（開発時は Xcode ログで確認）
    }

    nonisolated func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        Task { @MainActor in
            // 既に接続済みまたは保留中なら拒否
            if self.isConnected || self.pendingInvitation != nil {
                invitationHandler(false, nil)
                return
            }
            
            // ponytail: 確認ダイアログ+encryption .required まで。暗号学的なピア認証は W4 で必要になったら
            // ダイアログで確認待ち
            self.pendingInvitation = (peerName: peerID.displayName, decide: { accept in
                invitationHandler(accept, accept ? self.session : nil)
                self.pendingInvitation = nil
            })
        }
    }
}

// MARK: - MCNearbyServiceBrowserDelegate

extension PeerSession: MCNearbyServiceBrowserDelegate {
    nonisolated func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        // ponytail: エラーログ省略
    }

    nonisolated func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String : String]?) {
        Task { @MainActor in
            // 見つけたら自動 invite
            browser.invitePeer(peerID, to: self.session, withContext: nil, timeout: 30)
        }
    }

    nonisolated func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        // 自動的に MCSession から削除される
    }
}

#endif
