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

    /// P18 H9: キューの最大件数。到達時は古い方（FIFO）から捨てて新しい語を優先する。
    private static let maxCount = 100
    /// P18 H9: 1語あたりの最大文字数。UserDefaults 肥大化・表示崩れ防止のため超過は無視する。
    private static let maxWordLength = 100

    /// 既に入っている語は無視（重複除外）。長すぎる語は skip、上限到達時は古い語から捨てる。
    static func enqueue(_ word: String) {
        let trimmed = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= maxWordLength else { return }
        var words = all()
        guard !words.contains(trimmed) else { return }
        if words.count >= maxCount {
            words = Array(words.dropFirst())
        }
        words.append(trimmed)
        UserDefaults.standard.set(words, forKey: key)
    }

    static func dequeue(_ word: String) {
        UserDefaults.standard.set(all().filter { $0 != word }, forKey: key)
    }
}

/// P18 M12: クイック追加(QuickAddParserView)と辞書管理画面(DictionarySettingsView)が別々に持っていた
/// AliasDraftWord / PendingWordDraft を統合した共通ラッパー（String は Identifiable でないため必要）。
struct AliasCandidateWord: Identifiable {
    let word: String
    var id: String { word }
}
