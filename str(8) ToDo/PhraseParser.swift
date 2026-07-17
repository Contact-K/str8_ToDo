//
//  PhraseParser.swift
//  str8ToDo
//
//  自然文クイック追加パーサ（企画書 E2 / P16）。純関数、完全ローカル、ネット不要。
//  iOS26 Foundation Models framework は不採用（対応端末限定を避けるため）。
//
//  パイプライン:
//   ⓪ JPRuleLayer で日本語の日時・繰り返し・リマインダー・優先度を規則ベース抽出（Phase 16 拡張）。
//      NSDataDetector が拾えない相対表現（明日／来週火曜／14時半／1時間後 等）と、rrule /
//      reminderOffsets / isImportant はここで確定する。消費した範囲は remaining から除く。
//   ① NSDataDetector(.date) で日時・相対日付を抽出（英字絶対日時等のフォールバック）。
//      ⓪ で startDate が確定していれば skip する（自前規則が優先）。
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
        /// Phase 16 拡張: JPRuleLayer が抽出する RRULE 文字列（例: FREQ=WEEKLY;BYDAY=WE）。
        var rrule: String?
        /// Phase 16 拡張: JPRuleLayer が抽出する通知オフセット分数（例: [10, 60]）。
        var reminderOffsets: [Int] = []
        /// Phase 16 拡張: 優先度（! / 重要 / 至急 / 緊急 / 優先）を検出したら true。
        var isImportant: Bool = false
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

        // ⓪ JPRuleLayer: 日本語規則ベースで when/rrule/reminder/priority を先に抽出。
        //    消費した範囲は remaining から除去し、後段は残りだけ扱う。
        let jp = JPRuleLayer.extract(text)
        result.startDate = jp.startDate
        result.duration = jp.duration
        result.rrule = jp.rrule
        result.reminderOffsets = jp.reminderOffsets
        result.isImportant = jp.isImportant
        result.whoHint = jp.whoHint  // Phase 16.5: 関係語彙は JPRuleLayer 優先、辞書 who はフォールバック
        result.placeHint = jp.whereHint  // Phase 16.5: 場所語彙も JPRuleLayer 優先
        result.recognizedChips.append(contentsOf: jp.chips)
        var remaining = JPRuleLayer.remainder(from: text, consumed: jp.consumed)

        // ① 日時・相対日付の抽出（NSDataDetector, 英字絶対日時等のフォールバック）
        //   - 1件目を startDate、range を remaining から除去。
        //   - (a) 1件目が NSDataDetector から duration を貰っていればそれを採用（英語 "3-4pm" 等）。
        //   - (b) 2件目が同日・後方・24h 以内なら「終了時刻」とみなし duration を算出し、
        //         チップを「開始 – 終了」1本に統合（レンジ表記）。
        //   - どれにも該当しない 2件目以降は従来通り「追加の時刻」チップに落とす。
        //   - ただし ⓪ で startDate 確定済みなら二重パースを避けて skip。
        if result.startDate == nil {
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
                // Phase 16 拡張: JPRuleLayer で startDate 確定済みなら辞書 when は skip（自前規則優先）。
                if result.startDate == nil,
                   depth < maxRecursionDepth,
                   let rewriteRange = rewritten.range(of: alias.keyword) {
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

    /// P18 H4: 指定文字が単語境界か（nil＝文字列端も境界扱い）。
    /// - 漢字(Han)・カタカナ・英数字：複合語の内部と判断して境界ではない（大学 vs 大学院/大学ノート）。
    /// - 平仮名：助詞（で/を/に/の/は/が/と/も 等）の可能性が高いため境界扱い（大学でレポート）。
    /// - 空白・記号：境界扱い。
    private static func isWordBoundary(_ character: Character?) -> Bool {
        guard let character, let scalar = character.unicodeScalars.first else { return true }
        if character.isWhitespace { return true }
        if character.isNumber { return false }
        let v = scalar.value
        // Han (CJK 統合漢字 + 拡張A)
        if (0x4E00...0x9FFF).contains(v) || (0x3400...0x4DBF).contains(v) { return false }
        // カタカナ
        if (0x30A0...0x30FF).contains(v) { return false }
        // 平仮名は境界扱い（助詞のため）
        if (0x3040...0x309F).contains(v) { return true }
        // ASCII 英字は複合語内部扱い、その他は境界扱い
        if v < 0x80 { return !scalar.properties.isAlphabetic }
        return true
    }

    // MARK: - ③ 分かち書き（POS フィルタつき）

    /// 内容語（名詞/動詞/形容詞/数詞/固有名詞）だけを抽出。助詞・副詞・接続詞・代名詞・
    /// 感嘆詞・限定詞・その他語を除外。日本語混在時は言語を .japanese に固定（自動判定が
    /// 英語に振れると POS スキームが変わるため）。
    ///
    /// Phase 16.5: NLTagger は日本語トークンを .otherWord タグにし、複合名詞（マグロ漁 /
    /// 就職活動 / 図書館）を機械的に短単位分割する。そのため 3 段構成にした：
    ///   Stage 1: 全トークンを (text, tag, range) で収集
    ///   Stage 2: 隣接する .otherWord 同士を merge（range が完全接続 = 元テキストで隣り合ってる）
    ///   Stage 3: keep タグ判定 + count >= 2 フィルタ
    /// これで「マグロ(3字) + 漁(1字)」→「マグロ漁(4字)」として救済され、単字 fallback による
    /// 情報欠落を防ぐ。「大学 図書館」は空白が range gap になるので過剰マージしない。
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

        // Stage 1: 全トークン収集
        struct Tok { var text: String; var tag: NLTag?; var range: Range<String.Index> }
        var tokens: [Tok] = []
        let opts: NLTagger.Options = [.omitWhitespace, .omitPunctuation, .joinNames]
        tagger.enumerateTags(in: trimmed.startIndex..<trimmed.endIndex,
                              unit: .word, scheme: .lexicalClass, options: opts) { tag, range in
            let word = String(trimmed[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !word.isEmpty {
                tokens.append(Tok(text: word, tag: tag, range: range))
            }
            return true
        }

        // Stage 2: 隣接する otherWord 同士を merge（間に何も無い＝元テキストで隣り合ってる）。
        // ただし NLTagger は日本語トークン（助詞・動詞語尾を含む）を全部 .otherWord にするため、
        // 両側の先頭文字が「漢字またはカタカナ」の時だけ merge する。平仮名で始まる語は助詞や動詞
        // 語尾（を/に/と/する/だ 等）と判断して結合しない。これで「掃除 + を + する」は分離維持、
        // 「マグロ + 漁」「就職 + 活動」「図書 + 館」は正しく結合される。
        var merged: [Tok] = []
        for t in tokens {
            if let last = merged.last,
               last.tag == .otherWord, t.tag == .otherWord,
               last.range.upperBound == t.range.lowerBound,
               startsWithKanjiOrKatakana(last.text),
               startsWithKanjiOrKatakana(t.text) {
                let combined = Tok(text: last.text + t.text, tag: .otherWord,
                                    range: last.range.lowerBound..<t.range.upperBound)
                merged[merged.count - 1] = combined
            } else {
                merged.append(t)
            }
        }

        // Stage 3: 品詞フィルタ + 2字以上
        var out: [String] = []
        for t in merged {
            guard let tag = t.tag, keep.contains(tag) else { continue }
            guard t.text.count >= 2 else { continue }
            out.append(t.text)
        }
        return out
    }

    /// 語の先頭が漢字（CJK 統合漢字 + 拡張A）または カタカナ か。複合名詞 merge 判定用。
    private static func startsWithKanjiOrKatakana(_ text: String) -> Bool {
        guard let s = text.unicodeScalars.first else { return false }
        let v = s.value
        // Han
        if (0x4E00...0x9FFF).contains(v) || (0x3400...0x4DBF).contains(v) { return true }
        // Katakana
        if (0x30A0...0x30FF).contains(v) { return true }
        return false
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
