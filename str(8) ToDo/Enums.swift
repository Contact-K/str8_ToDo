//
//  Enums.swift
//  str8ToDo
//
//  仕分けフェーズ／承認ステータスの定義。
//

import Foundation
import SwiftUI

/// 朝の仕分けカードで決まる「いつやるか」のバケツ。
enum SortPhase: String, Codable, CaseIterable, Identifiable {
    case now    = "今すぐ"
    case today  = "今日"
    case week   = "今週"
    case someday = "いつか"

    var id: String { rawValue }

    var label: String { rawValue }

    /// リスト画面でのざっくりした並び順（小さいほど手前）。
    var order: Int {
        switch self {
        case .now:   return 0
        case .today: return 1
        case .week:  return 2
        case .someday: return 3
        }
    }
}

/// 承認プロトコルの状態機械。
/// 未完了 → ペンディング（完了したが未承認）→ 承認済み（他者 or 未来の自分が承認）。
enum TaskStatus: String, Codable, CaseIterable, Identifiable {
    case incomplete = "未完了"
    case pending    = "ペンディング"
    case approved   = "承認済み"

    var id: String { rawValue }

    var label: String { rawValue }

    var systemImage: String {
        switch self {
        case .incomplete: return "circle"
        case .pending:    return "hourglass"
        case .approved:   return "checkmark.seal.fill"
        }
    }

    var tint: Color {
        switch self {
        case .incomplete: return .secondary
        case .pending:    return .orange
        case .approved:   return .green
        }
    }
}
