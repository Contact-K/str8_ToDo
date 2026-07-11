//
//  PhraseParser.swift
//  str8ToDo
//
//  自然文クイック追加パーサ（企画書 E2 / P16）。純関数、完全ローカル、ネット不要。
//  iOS26 Foundation Models framework は不採用（対応端末限定を避けるため）。
//
//  パイプライン:
//   ① NSDataDetector(.date) で日時・相対日付（「明日」「来週」「14:00」等）を抽出
//   ② 残りのテキストから PhraseAlias（isEnabled）のキーワードを部分文字列として検索・照合。
//      ヒットしたら chip 化して remaining から取り除く。.when カテゴリのヒットだけは
//      replacement を元の文に埋め戻して①から再パース（replacement が新たな日時表現を
//      含みうるのはこのカテゴリだけなので、他カテゴリは直接ヒントフィールドへ格納する
//      だけで再パースは不要。再帰は最大2段）
//      ponytail: NLTokenizer(unit: .word) のトークン単位で照合すると、「ポモ」等の辞書に
//      無いカタカナ略語は文字単位（"ポ"+"モ"）に分割されてしまい一致しない（実機/シミュレータ
//      で確認済み）。そのためエイリアス照合はトークン化前の remaining への部分文字列検索で行う。
//   ③ エイリアスヒット分を除いた残りを NLTokenizer(unit: .word) で分かち書きし、
//      titleRemainder / unrecognizedWords を確定する
//   ④ どの語にも当たらない部分は titleRemainder に残す（情報を握りつぶさない）
//

import Foundation
import NaturalLanguage

struct PhraseParser {
    struct ParseResult {
        var titleRemainder: String = ""
        var startDate: Date?
        var duration: TimeInterval?
        var placeHint: String?
        var categoryHint: String?
        /// P18 H6: who（誰と）カテゴリのヒット。最初の1件を採用。
        var whoHint: String?
        /// P18 H6: other（その他）カテゴリのヒット。最初の1件を採用。
        var otherHint: String?
        var recognizedChips: [(WHCategory, String)] = []
        var unrecognizedWords: [String] = []
    }

    /// 再帰の最大段数（「①からの再パース」を最大2回まで許可）。
    private static let maxRecursionDepth = 2

    static func parse(_ text: String, aliases: [PhraseAlias]) -> ParseResult {
        parse(text, aliases: aliases, depth: 0)
    }

    private static func parse(_ text: String, aliases: [PhraseAlias], depth: Int) -> ParseResult {
        var result = ParseResult()

        // ① 日時・相対日付の抽出（P18 H5: 複数マッチ対応。最初の1件だけ startDate として確定し、
        // 除去する。2件目以降は remaining に残したまま「追加の時刻」chip として見える化するだけ）
        var remaining = text
        let dateHits = dateMatches(in: remaining)
        if let first = dateHits.first {
            result.startDate = first.date
            result.recognizedChips.append((.when, chipLabelFormatter.string(from: first.date)))
            remaining.removeSubrange(first.range)
        }
        for extra in dateHits.dropFirst() {
            result.recognizedChips.append((.when, "追加の時刻: \(extraTimeFormatter.string(from: extra.date))"))
        }

        // ② PhraseAlias 照合（部分文字列検索。理由は上のヘッダコメント参照）
        let enabledAliases = aliases.filter(\.isEnabled)
        var rewritten = remaining
        var shouldRecurse = false

        for alias in enabledAliases {
            guard let range = remaining.range(of: alias.keyword) else { continue }

            // P18 H4: 意図しない複合語マッチ回避（大学 vs 大学図書館 等）。前後が日本語(Han/Hiragana/
            // Katakana)または英数字なら単語境界とみなさず skip する。
            let before: Character? = range.lowerBound > remaining.startIndex
                ? remaining[remaining.index(before: range.lowerBound)] : nil
            let after: Character? = range.upperBound < remaining.endIndex ? remaining[range.upperBound] : nil
            guard isWordBoundary(before), isWordBoundary(after) else { continue }

            result.recognizedChips.append((alias.whCategory, alias.replacement))
            switch alias.whCategory {
            case .where_:
                result.placeHint = alias.replacement
            case .which:
                result.categoryHint = alias.replacement
            case .who:
                if result.whoHint == nil { result.whoHint = alias.replacement }
            case .other:
                if result.otherHint == nil { result.otherHint = alias.replacement }
            case .how:
                if let minutes = durationMinutes(from: alias.replacement) {
                    result.duration = TimeInterval(minutes * 60)
                }
            case .when:
                // ponytail: 最初にマッチした範囲だけ置換（同じ語が複数回現れる稀なケースは近似で許容）
                if depth < maxRecursionDepth, let rewriteRange = rewritten.range(of: alias.keyword) {
                    rewritten.replaceSubrange(rewriteRange, with: alias.replacement)
                    shouldRecurse = true
                }
            case .what:
                break // chip としては認識済みだが専用ヒントフィールドは持たない
            }
            remaining.removeSubrange(range)
        }

        if shouldRecurse {
            return parse(rewritten, aliases: aliases, depth: depth + 1)
        }

        // ③ 残りを分かち書きして titleRemainder / unrecognizedWords を確定
        let leftover = tokenize(remaining)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        result.unrecognizedWords = leftover
        result.titleRemainder = leftover.joined(separator: " ")
        return result
    }

    // MARK: - ① 日時抽出

    /// P18 H5: 1件目だけでなく全マッチを返す（呼び出し側で先頭を startDate、残りを chip 化する）。
    private static func dateMatches(in text: String) -> [(date: Date, range: Range<String.Index>)] {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue) else { return [] }
        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = detector.matches(in: text, options: [], range: nsRange)
        return matches.compactMap { match in
            guard let date = match.date, let range = Range(match.range, in: text) else { return nil }
            return (date, range)
        }
    }

    private static let chipLabelFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "M/d HH:mm"
        f.locale = Locale(identifier: "ja_JP")
        return f
    }()

    /// P18 H5: 2件目以降の「追加の時刻」chip 表示用（HH:mm のみ）。
    private static let extraTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        f.locale = Locale(identifier: "ja_JP")
        return f
    }()

    /// P18 H4: 指定文字が単語境界か（nil＝文字列端も境界扱い）。日本語(Han/Hiragana/Katakana)や
    /// 英数字はいずれも Unicode.Scalar.Properties.isAlphabetic / Character.isNumber で判定できるため、
    /// 前後どちらかがそれに該当する場合は「複合語の内部」とみなし境界ではないと判定する。
    private static func isWordBoundary(_ character: Character?) -> Bool {
        guard let character, let scalar = character.unicodeScalars.first else { return true }
        return !(scalar.properties.isAlphabetic || character.isNumber)
    }

    // MARK: - ③ 分かち書き

    private static func tokenize(_ text: String) -> [String] {
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = text
        var tokens: [String] = []
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            tokens.append(String(text[range]))
            return true
        }
        return tokens
    }

    // MARK: - how（所要時間）の簡易パース

    /// "25分" / "1時間" / "1時間30分" 等、数値+単位のみの簡易パース。
    private static func durationMinutes(from text: String) -> Int? {
        var minutes = 0
        var found = false
        if let hourRange = text.range(of: #"[0-9０-９]+\s*時間"#, options: .regularExpression) {
            let digits = String(text[hourRange].filter(\.isNumber)).applyingTransform(.fullwidthToHalfwidth, reverse: false)
            if let hours = Int(digits ?? "") { minutes += hours * 60; found = true }
        }
        if let minRange = text.range(of: #"[0-9０-９]+\s*分"#, options: .regularExpression) {
            let digits = String(text[minRange].filter(\.isNumber)).applyingTransform(.fullwidthToHalfwidth, reverse: false)
            if let mins = Int(digits ?? "") { minutes += mins; found = true }
        }
        return found ? minutes : nil
    }
}
