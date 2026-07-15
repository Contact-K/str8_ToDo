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

        // ① 日時・相対日付の抽出
        //   - 1件目を startDate、range を remaining から除去。
        //   - (a) 1件目が NSDataDetector から duration を貰っていればそれを採用（英語 "3-4pm" 等）。
        //   - (b) 2件目が同日・後方・24h 以内なら「終了時刻」とみなし duration を算出し、
        //         チップを「開始 – 終了」1本に統合（レンジ表記）。
        //   - どれにも該当しない 2件目以降は従来通り「追加の時刻」チップに落とす。
        var remaining = text
        let dateHits = dateMatches(in: remaining)
        if let first = dateHits.first {
            result.startDate = first.date
            result.recognizedChips.append((.when, chipLabelFormatter.string(from: first.date)))
            remaining.removeSubrange(first.range)

            if first.duration > 0 {
                result.duration = first.duration
                for extra in dateHits.dropFirst() {
                    result.recognizedChips.append((.when, "追加の時刻: \(extraTimeFormatter.string(from: extra.date))"))
                }
            } else if let second = dateHits.dropFirst().first,
                      let gap = validRangeEnd(start: first.date, end: second.date) {
                result.duration = gap
                // 2件目を吸収したので、開始チップを「開始 – 終了」表記に置換。
                result.recognizedChips.removeLast()
                result.recognizedChips.append((.when,
                    "\(chipLabelFormatter.string(from: first.date)) – \(extraTimeFormatter.string(from: second.date))"))
                for extra in dateHits.dropFirst(2) {
                    result.recognizedChips.append((.when, "追加の時刻: \(extraTimeFormatter.string(from: extra.date))"))
                }
            } else {
                for extra in dateHits.dropFirst() {
                    result.recognizedChips.append((.when, "追加の時刻: \(extraTimeFormatter.string(from: extra.date))"))
                }
            }
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
        //    NLTagger の lexicalClass で POS 判定し、内容語（名詞/動詞/形容詞/数詞/固有名詞）だけ残す。
        //    助詞・副詞・接続詞・代名詞・感嘆詞・限定詞・その他は辞書登録候補として無意味なため除外。
        let leftover = meaningfulWords(remaining)
        result.unrecognizedWords = leftover
        result.titleRemainder = leftover.joined(separator: " ")
        return result
    }

    // MARK: - ① 日時抽出

    /// P18 H5: 1件目だけでなく全マッチを返す。`duration` は NSDataDetector が範囲表現から
    /// 抽出した秒数（例 "3-4pm" → 3600）。単独時刻や日本語ではふつう 0。
    private static func dateMatches(in text: String) -> [(date: Date, duration: TimeInterval, range: Range<String.Index>)] {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue) else { return [] }
        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = detector.matches(in: text, options: [], range: nsRange)
        return matches.compactMap { match in
            guard let date = match.date, let range = Range(match.range, in: text) else { return nil }
            return (date, match.duration, range)
        }
    }

    /// 2件目が終了時刻として妥当なら差分（秒）を返す。妥当条件: 開始より後、同日、24h 以内。
    private static func validRangeEnd(start: Date, end: Date) -> TimeInterval? {
        let cal = Calendar.current
        guard end > start,
              cal.isDate(start, inSameDayAs: end),
              end.timeIntervalSince(start) <= 24 * 3600
        else { return nil }
        return end.timeIntervalSince(start)
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

    // MARK: - ③ 分かち書き（POS フィルタつき）

    /// 内容語（名詞/動詞/形容詞/数詞/固有名詞）だけを抽出。助詞・副詞・接続詞・代名詞・
    /// 感嘆詞・限定詞・その他語を除外。1 文字トークンも助詞取りこぼし対策で捨てる。
    /// 日本語混在時は言語を .japanese に固定（自動判定が英語に振れると POS スキームが変わるため）。
    private static func meaningfulWords(_ text: String) -> [String] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let tagger = NLTagger(tagSchemes: [.lexicalClass])
        tagger.string = trimmed
        if trimmed.unicodeScalars.contains(where: isJapaneseScalar) {
            tagger.setLanguage(.japanese, range: trimmed.startIndex..<trimmed.endIndex)
        }
        // 残す品詞。personalName/placeName/organizationName は .lexicalClass では出ないが
        // 将来 .nameType スキームと併用する時のために保険で入れておく（含んでも無害）。
        let keep: Set<NLTag> = [.noun, .verb, .adjective, .number, .otherWord,
                                 .personalName, .placeName, .organizationName]
        var out: [String] = []
        let opts: NLTagger.Options = [.omitWhitespace, .omitPunctuation, .joinNames]
        tagger.enumerateTags(in: trimmed.startIndex..<trimmed.endIndex,
                              unit: .word, scheme: .lexicalClass, options: opts) { tag, range in
            let word = String(trimmed[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard word.count >= 2 else { return true }
            if let tag, keep.contains(tag) {
                out.append(word)
            }
            return true
        }
        return out
    }

    /// 平仮名 / 片仮名 / CJK 統合漢字 のいずれか。
    private static func isJapaneseScalar(_ s: Unicode.Scalar) -> Bool {
        (0x3040...0x309F).contains(s.value)
            || (0x30A0...0x30FF).contains(s.value)
            || (0x4E00...0x9FFF).contains(s.value)
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
