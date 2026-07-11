//
//  RoomMessage.swift
//  str8ToDo
//
//  集中ルームで交換するメッセージ（Phase 14）。ApprovalMessage と対を成す。
//  Multipeer over JSON で送受信。
//

import Foundation

enum RoomMessage: Codable {
    /// 参加通知（ホストは自身の入室時、ゲストは接続完了時）。
    /// isHost フラグは持たない（自己申告でなりすませるため）。host かどうかは受信側が
    /// 内部状態（`.startHosting()` を呼んだか / `requestJoin` で選んだ peer か）で判定する。
    case hello(participantID: String)
    /// faceDown 状態変化（自分が伏せた or 起こした）
    case faceDown(participantID: String, isFaceDown: Bool)
    /// クロック同期 ping（ゲストが送る）
    case clockPing(pingSentAt: TimeInterval)
    /// クロック同期 pong（ホストが応答）— pingSentAt はゲストからの受信値を反射、hostReplyTime はホストが応答した時のホスト epoch
    case clockPong(pingSentAt: TimeInterval, hostReplyTime: TimeInterval)
    /// 開始 announce（ホストが送る、hostStartAt はホスト epoch、roomID はルーム識別）
    case start(hostStartAt: TimeInterval, roomID: UUID)
    /// 終了 announce（ホストが送る）
    case end
    /// 明示的離脱通知
    case leave(participantID: String)

    // Codable: 各ケースの構造化エンコード/デコード
    enum CodingKeys: String, CodingKey {
        case type, participantID, isFaceDown, pingSentAt, hostReplyTime, hostStartAt, roomID
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .hello(let participantID):
            try container.encode("hello", forKey: .type)
            try container.encode(participantID, forKey: .participantID)
        case .faceDown(let participantID, let isFaceDown):
            try container.encode("faceDown", forKey: .type)
            try container.encode(participantID, forKey: .participantID)
            try container.encode(isFaceDown, forKey: .isFaceDown)
        case .clockPing(let pingSentAt):
            try container.encode("clockPing", forKey: .type)
            try container.encode(pingSentAt, forKey: .pingSentAt)
        case .clockPong(let pingSentAt, let hostReplyTime):
            try container.encode("clockPong", forKey: .type)
            try container.encode(pingSentAt, forKey: .pingSentAt)
            try container.encode(hostReplyTime, forKey: .hostReplyTime)
        case .start(let hostStartAt, let roomID):
            try container.encode("start", forKey: .type)
            try container.encode(hostStartAt, forKey: .hostStartAt)
            try container.encode(roomID, forKey: .roomID)
        case .end:
            try container.encode("end", forKey: .type)
        case .leave(let participantID):
            try container.encode("leave", forKey: .type)
            try container.encode(participantID, forKey: .participantID)
        }
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
        case "hello":
            let participantID = try container.decode(String.self, forKey: .participantID)
            self = .hello(participantID: participantID)
        case "faceDown":
            let participantID = try container.decode(String.self, forKey: .participantID)
            let isFaceDown = try container.decode(Bool.self, forKey: .isFaceDown)
            self = .faceDown(participantID: participantID, isFaceDown: isFaceDown)
        case "clockPing":
            let pingSentAt = try container.decode(TimeInterval.self, forKey: .pingSentAt)
            self = .clockPing(pingSentAt: pingSentAt)
        case "clockPong":
            let pingSentAt = try container.decode(TimeInterval.self, forKey: .pingSentAt)
            let hostReplyTime = try container.decode(TimeInterval.self, forKey: .hostReplyTime)
            self = .clockPong(pingSentAt: pingSentAt, hostReplyTime: hostReplyTime)
        case "start":
            let hostStartAt = try container.decode(TimeInterval.self, forKey: .hostStartAt)
            let roomID = try container.decode(UUID.self, forKey: .roomID)
            self = .start(hostStartAt: hostStartAt, roomID: roomID)
        case "end":
            self = .end
        case "leave":
            let participantID = try container.decode(String.self, forKey: .participantID)
            self = .leave(participantID: participantID)
        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Unknown type")
        }
    }
}
