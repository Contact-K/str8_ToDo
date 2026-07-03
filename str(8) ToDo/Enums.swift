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

/// 完了と承認の2層状態機械（2026-07-02 改訂）。
/// active → done（自己チェック済み・UI上は完了）→ approved（確定。stats に乗るのはここだけ）。
enum TaskStatus: String, Codable, CaseIterable, Identifiable {
    case active   = "active"
    case done     = "done"
    case approved = "approved"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .active:   return "未完了"
        case .done:     return "完了"
        case .approved: return "確定"
        }
    }

    var systemImage: String {
        switch self {
        case .active:   return "circle"
        case .done:     return "checkmark.circle"
        case .approved: return "checkmark.seal.fill"
        }
    }

    var tint: Color {
        switch self {
        case .active:   return .secondary
        case .done:     return .blue
        case .approved: return .green
        }
    }
}
