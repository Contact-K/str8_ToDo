//
//  WHCategory.swift
//  str8ToDo
//
//  イベント作成シート（企画書 2026-07-07 新設）の7分類。P15 で概要タイル/フォーカス編集の軸に使う。
//

import Foundation

enum WHCategory: String, Codable, CaseIterable {
    case what, when, where_, which, who, how, other

    var label: String {
        switch self {
        case .what:   return "何を"
        case .when:   return "いつ"
        case .where_: return "どこ"
        case .which:  return "どれ"
        case .who:    return "誰と"
        case .how:    return "どのくらい"
        case .other:  return "その他"
        }
    }

    var iconName: String {
        switch self {
        case .what:   return "pencil"
        case .when:   return "clock.fill"
        case .where_: return "mappin.and.ellipse"
        case .which:  return "briefcase.fill"
        case .who:    return "person.2.fill"
        case .how:    return "gauge.medium"
        case .other:  return "ellipsis.circle.fill"
        }
    }
}
