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

        // ① 日時・相対日付の抽出
        var remaining = text
        if let (date, range) = firstDateMatch(in: remaining) {
            result.startDate = date
            result.recognizedChips.append((.when, chipLabelFormatter.string(from: date)))
            remaining.removeSubrange(range)
        }

        // ② PhraseAlias 照合（部分文字列検索。理由は上のヘッダコメント参照）
        let enabledAliases = aliases.filter(\.isEnabled)
        var rewritten = remaining
        var shouldRecurse = false

        for alias in enabledAliases {
            guard let range = remaining.range(of: alias.keyword) else { continue }

            result.recognizedChips.append((alias.whCategory, alias.replacement))
            switch alias.whCategory {
            case .where_:
                result.placeHint = alias.replacement
            case .which:
                result.categoryHint = alias.replacement
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
            case .what, .who, .other:
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

    private static func firstDateMatch(in text: String) -> (date: Date, range: Range<String.Index>)? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue) else { return nil }
        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = detector.firstMatch(in: text, options: [], range: nsRange),
              let date = match.date,
              let range = Range(match.range, in: text)
        else { return nil }
        return (date, range)
    }

    private static let chipLabelFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "M/d HH:mm"
        f.locale = Locale(identifier: "ja_JP")
        return f
    }()

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
