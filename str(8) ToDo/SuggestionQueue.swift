//
//  SuggestionQueue.swift
//  str8ToDo
//
//  クイック追加（P16 QuickAddParserView）のサジェストでタップ／表示された未認識ワードを、
//  辞書管理画面（P17 DictionarySettingsView）の「登録待ち」セクションに引き渡すための
//  一時キュー。UserDefaults に [String] を保存するだけの純ロジック（重複除外）。
//

import Foundation

enum SuggestionQueue {
    private static let key = "suggestionQueueWords"

    static func all() -> [String] {
        UserDefaults.standard.stringArray(forKey: key) ?? []
    }

    /// 既に入っている語は無視（重複除外）。
    static func enqueue(_ word: String) {
        let trimmed = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var words = all()
        guard !words.contains(trimmed) else { return }
        words.append(trimmed)
        UserDefaults.standard.set(words, forKey: key)
    }

    static func dequeue(_ word: String) {
        UserDefaults.standard.set(all().filter { $0 != word }, forKey: key)
    }
}
