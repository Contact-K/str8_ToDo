//
//  PhraseAlias.swift
//  str8ToDo
//
//  自然文クイック追加パーサ（P16）と辞書管理画面（P17）が共有する辞書エントリ。
//  P15 ではモデルのみ用意（UI は P17）。
//

import Foundation
import SwiftData

@Model
final class PhraseAlias {
    @Attribute(.unique) var id: UUID
    var keyword: String
    var whCategory: WHCategory
    var replacement: String
    var isBuiltIn: Bool = false
    var isEnabled: Bool = true

    init(
        id: UUID = UUID(),
        keyword: String,
        whCategory: WHCategory,
        replacement: String,
        isBuiltIn: Bool = false,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.keyword = keyword
        self.whCategory = whCategory
        self.replacement = replacement
        self.isBuiltIn = isBuiltIn
        self.isEnabled = isEnabled
    }
}

extension PhraseAlias {
    /// P18 H2: 辞書エントリ（keyword/replacement）の入力サニタイズ。改行除去→trim→100文字上限（超過は truncate）。
    /// DictionarySettingsView.AliasEditSheet と QuickAddParserView.NewAliasSheet の両方が使う共通ロジック。
    static func sanitizeEntry(_ text: String) -> String {
        let noNewlines = text
            .replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: "\r", with: "")
        return String(noNewlines.trimmingCharacters(in: .whitespaces).prefix(100))
    }
}
