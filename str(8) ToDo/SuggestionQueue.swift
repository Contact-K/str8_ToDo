//
//  SuggestionQueue.swift
//  str8ToDo
//
//  クイック追加（P16 QuickAddParserView）のサジェストでタップ／表示された未認識ワードを、
//  辞書管理画面（P17 DictionarySettingsView）の「登録待ち」セクションに引き渡すための
//  一時キュー。UserDefaults に追加日時付きで保存する純ロジック（重複除外）。
//

import Foundation

enum SuggestionQueue {
    private struct Entry: Codable {
        let word: String
        let addedAt: Date
    }

    private static let key = "suggestionQueueEntries"
    private static let legacyKey = "suggestionQueueWords"
    private static let expirationInterval: TimeInterval = 30 * 24 * 60 * 60

    static func all() -> [String] {
        loadEntries().map(\.word)
    }

    /// P18 H9: キューの最大件数。到達時は古い方（FIFO）から捨てて新しい語を優先する。
    private static let maxCount = 100
    /// P18 H9: 1語あたりの最大文字数。UserDefaults 肥大化・表示崩れ防止のため超過は無視する。
    private static let maxWordLength = 100

    /// 既に入っている語は無視（重複除外）。長すぎる語は skip、上限到達時は古い語から捨てる。
    static func enqueue(_ word: String) {
        let trimmed = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= maxWordLength else { return }
        var entries = loadEntries()
        guard !entries.contains(where: { $0.word == trimmed }) else { return }
        if entries.count >= maxCount {
            entries = Array(entries.dropFirst())
        }
        entries.append(Entry(word: trimmed, addedAt: .now))
        save(entries)
    }

    static func dequeue(_ word: String) {
        save(loadEntries().filter { $0.word != word })
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
        UserDefaults.standard.removeObject(forKey: legacyKey)
    }

    private static func loadEntries() -> [Entry] {
        let defaults = UserDefaults.standard
        let entries: [Entry]

        if let data = defaults.data(forKey: key) {
            entries = (try? JSONDecoder().decode([Entry].self, from: data)) ?? []
        } else if let words = defaults.stringArray(forKey: legacyKey) {
            entries = words.map { Entry(word: $0, addedAt: .now) }
            save(entries)
            defaults.removeObject(forKey: legacyKey)
        } else {
            entries = []
        }

        let expirationDate = Date.now.addingTimeInterval(-expirationInterval)
        let validEntries = entries.filter { $0.addedAt >= expirationDate }
        if validEntries.count != entries.count {
            save(validEntries)
        }
        return validEntries
    }

    private static func save(_ entries: [Entry]) {
        UserDefaults.standard.set(try? JSONEncoder().encode(entries), forKey: key)
    }
}

/// P18 M12: クイック追加(QuickAddParserView)と辞書管理画面(DictionarySettingsView)が別々に持っていた
/// AliasDraftWord / PendingWordDraft を統合した共通ラッパー（String は Identifiable でないため必要）。
struct AliasCandidateWord: Identifiable {
    let word: String
    var id: String { word }
}
