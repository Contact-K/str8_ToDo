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

    // MARK: - PeerRoomSession が使う純ロジック（p14-selfcheck で検証できるよう分離）

    /// `.hello` の重複メッセージ処理：既に参加済みの id なら追加しない。
    static func shouldAddParticipant(existing: [Participant], id: String) -> Bool {
        !existing.contains(where: { $0.id == id })
    }

    /// 終了状態への再入防止ガード。既に `.ended` なら false（呼び出し側は何もしない）、
    /// まだなら `.ended` に進めて true を返す。`markEnded`/`end()` の両方がこれを使う。
    static func tryTransitionToEnded(_ state: inout RoomState) -> Bool {
        guard state != .ended else { return false }
        state = .ended
        return true
    }

    /// 「一度だけ実行」ガード。`onEnded` が二重発火しても FocusSession の保存が1回に
    /// とどまることを保証する（FocusRoomView.finishAndSave が使う）。
    static func markFinishedOnce(_ hasFinished: inout Bool) -> Bool {
        guard !hasFinished else { return false }
        hasFinished = true
        return true
    }

    /// 受信レート制限：window 秒内に limit 回を超えたメッセージは拒否する（`.hello` / `.leave` の連投対策）。
    /// timestamps は呼び出し側が保持する直近受信時刻のリスト。古いものは呼び出しごとに剪定する。
    static func isRateLimited(_ timestamps: inout [TimeInterval], now: TimeInterval, limit: Int = 3, window: TimeInterval = 5) -> Bool {
        timestamps.removeAll { now - $0 > window }
        if timestamps.count >= limit { return true }
        timestamps.append(now)
        return false
    }
}
