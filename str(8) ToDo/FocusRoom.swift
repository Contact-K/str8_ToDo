//
//  FocusRoom.swift
//  str8ToDo
//
//  集中ルーム（Phase 14）の純粋モデル。SwiftData/UI 非依存。
//  ホスト-ゲスト間のクロックオフセット計算・参加者状態管理・状態遷移を集約し、
//  p14-selfcheck.swift で数値検証する。
//

import Foundation

enum RoomState: Equatable {
    case waiting        // 参加者募集中
    case readyToStart   // 全員 faceDown、開始時刻決定待ち
    case running        // カウントダウン中
    case ended          // 正常終了
    case aborted        // 途中中断（全員離脱 or ホスト離脱）
}

struct Participant: Identifiable, Hashable {
    let id: String       // MCPeerID.displayName または UUID 文字列
    var isFaceDown: Bool
    var isHost: Bool
}

enum FocusRoom {
    // MARK: - 状態遷移

    /// 全員 faceDown が揃っているか（参加者が 0 なら false）。
    static func isReadyToStart(participants: [Participant]) -> Bool {
        !participants.isEmpty && participants.allSatisfy { $0.isFaceDown }
    }

    /// ホストが離脱すると abort、残ピアが 0 になっても abort。それ以外は current を維持。
    static func nextStateAfterLeft(current: RoomState, remaining: [Participant]) -> RoomState {
        if remaining.isEmpty { return .aborted }
        if !remaining.contains(where: { $0.isHost }) { return .aborted }
        return current
    }

    // MARK: - クロックオフセット

    /// ping-pong 方式でオフセットを推定する。呼び出し側の想定:
    /// - ゲストが `pingSentAt`（ゲスト時刻）で ping を送る
    /// - ホストが受信して即応答、応答パケットに送信時のホスト時刻 `hostReplyTime` を埋め込む
    /// - ゲストが `pongReceivedAt`（ゲスト時刻）で応答を受信
    /// RTT = pongReceivedAt - pingSentAt。片道 delay ≈ RTT/2 と仮定。
    /// 応答送信時点でのゲスト時刻推定値 = pingSentAt + RTT/2
    /// オフセットの定義: `hostTime ≈ guestTime + offset`
    /// したがって offset = hostReplyTime - (pingSentAt + RTT/2)
    static func clockOffset(pingSentAt: TimeInterval, pongReceivedAt: TimeInterval, hostReplyTime: TimeInterval) -> TimeInterval {
        let rtt = pongReceivedAt - pingSentAt
        let oneWay = rtt / 2
        let guestEstimateOfHostSend = pingSentAt + oneWay
        return hostReplyTime - guestEstimateOfHostSend
    }

    /// ホストが announce した開始時刻（ホスト epoch）を、自分側のローカル時刻に変換する。
    /// hostTime = guestTime + offset → guestTime = hostTime - offset
    static func localStartTime(hostStartAt: TimeInterval, offset: TimeInterval) -> TimeInterval {
        hostStartAt - offset
    }

    /// ホストが「今から delaySec 後に開始」と announce したいときの hostStartAt。
    /// ネットワーク往復とバッファのため既定 3 秒推奨。
    static func recommendedHostStartAt(hostNow: TimeInterval, delaySec: TimeInterval = 3) -> TimeInterval {
        hostNow + delaySec
    }
}
