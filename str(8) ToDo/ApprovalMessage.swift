//
//  ApprovalMessage.swift
//  str8ToDo
//
//  ペア承認パイプラインのメッセージ型。PeerSession で送受信。
//  Equatable: p5-selfcheck での ラウンドトリップ検証用。
//  approverName フィールドなし（なりすまし対策: 名前は受信側で MCPeerID.displayName から採る）。
//

import Foundation

enum ApprovalMessage: Codable, Equatable {
    case request(taskID: UUID, title: String)
    case approved(taskID: UUID)
    case niToken(Data)

    // Codable: 各ケースの構造化エンコード/デコード
    enum CodingKeys: String, CodingKey {
        case type, taskID, title, data
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .request(let taskID, let title):
            try container.encode("request", forKey: .type)
            try container.encode(taskID, forKey: .taskID)
            try container.encode(title, forKey: .title)
        case .approved(let taskID):
            try container.encode("approved", forKey: .type)
            try container.encode(taskID, forKey: .taskID)
        case .niToken(let data):
            try container.encode("niToken", forKey: .type)
            try container.encode(data, forKey: .data)
        }
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
        case "request":
            let taskID = try container.decode(UUID.self, forKey: .taskID)
            let title = try container.decode(String.self, forKey: .title)
            self = .request(taskID: taskID, title: title)
        case "approved":
            let taskID = try container.decode(UUID.self, forKey: .taskID)
            self = .approved(taskID: taskID)
        case "niToken":
            let data = try container.decode(Data.self, forKey: .data)
            self = .niToken(data)
        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Unknown type")
        }
    }
}
