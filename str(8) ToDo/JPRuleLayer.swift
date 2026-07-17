//
//  JPRuleLayer.swift
//  str8ToDo
//
//  日本語自然文向けの規則ベース抽出層（Phase 16 拡張、ML/AI 不使用）。
//  PhraseParser の ①-NSDataDetector より前段に置き、when / rrule / reminder / priority を
//  決定論的に抽出する。NSDataDetector が拾えない日本語相対表現（明日／来週火曜／14時半／
//  1時間後 等）を埋め、テストしやすいよう now と calendar を引数注入する。
//
//  ponytail: 時刻は 24h リテラル解釈（「3時」→ 03:00）。PM を意図するときは「午後3時」または
//  「15時」を使う。曖昧さを許すと「3時から5時」の朝ジム／午後ミーティングを区別できない。
//

import Foundation

enum JPRuleLayer {
    struct Result {
        var startDate: Date?
        var duration: TimeInterval?
        var rrule: String?
        var reminderOffsets: [Int] = []
        var isImportant: Bool = false
        /// Phase 16.5 拡張: 関係語彙（友達/母/同僚 等）が抽出されたら格納。
        var whoHint: String?
        /// Phase 16.5 拡張: 場所語彙（公園/海/カフェ 等）が抽出されたら格納。PhraseParser 側で
        /// PhraseAlias の placeHint とマージされる（JPRuleLayer 優先）。
        var whereHint: String?
        var chips: [(WHCategory, String)] = []
        var consumed: [Range<String.Index>] = []
    }

    /// テキストから when/rrule/reminder/priority を抽出。呼び出し側は Result.consumed を使って
    /// 残りテキストを組み立て、後段の NSDataDetector / PhraseAlias 処理に回すことを想定。
    static func extract(_ text: String, now: Date = .now, calendar: Calendar = .current) -> Result {
        var result = Result()
        var consumed: [Range<String.Index>] = []

        extractPriority(text, consumed: &consumed, into: &result)
        extractReminders(text, consumed: &consumed, into: &result)

        var rruleImplied: Date? = nil
        extractRRule(text, now: now, calendar: calendar, consumed: &consumed, into: &result, impliedDate: &rruleImplied)

        var relativeDate: Date? = nil
        extractRelative(text, now: now, calendar: calendar, consumed: &consumed, into: &result, date: &relativeDate)

        var datePart: Date? = nil
        extractDatePart(text, now: now, calendar: calendar, consumed: &consumed, into: &result, date: &datePart)

        var timeParts: [(hour: Int, minute: Int)] = []
        extractTimeParts(text, consumed: &consumed, into: &result, times: &timeParts)

        extractWho(text, consumed: &consumed, into: &result)
        extractWhere(text, consumed: &consumed, into: &result)

        result.consumed = consumed
        result.startDate = composeStart(
            relative: relativeDate,
            datePart: datePart,
            rruleImplied: rruleImplied,
            firstTime: timeParts.first,
            now: now,
            calendar: calendar
        )
        if let start = result.startDate, timeParts.count >= 2 {
            let end = calendar.date(bySettingHour: timeParts[1].hour, minute: timeParts[1].minute, second: 0, of: start) ?? start
            let diff = end.timeIntervalSince(start)
            if diff > 0 && diff <= 24 * 3600 {
                result.duration = diff
            }
        }
        return result
    }

    /// consumed 範囲を空白置換した remainder テキストを返す。
    static func remainder(from text: String, consumed: [Range<String.Index>]) -> String {
        guard !consumed.isEmpty else { return text }
        let merged = mergeRanges(consumed)
        var out = text
        for r in merged.reversed() {
            out.replaceSubrange(r, with: " ")
        }
        return out
    }

    // MARK: - Priority

    private static func extractPriority(_ text: String, consumed: inout [Range<String.Index>], into result: inout Result) {
        // "!" / "！" 連続、または "重要 / 至急 / 緊急 / 優先"
        for hit in matches(in: text, pattern: #"[!！]+|重要|至急|緊急|優先"#, avoiding: consumed) {
            result.isImportant = true
            let label = String(text[hit.range])
            if !result.chips.contains(where: { $0.0 == .other && $0.1 == label }) {
                result.chips.append((.other, label))
            }
            consumed.append(hit.range)
        }
    }

    // MARK: - Reminders

    /// アラビア / 全角 / 漢数字（一〜二十三くらいまで）を受ける汎用数字パターン。
    /// パターン内で `\#(anyDigits)` として展開する（Swift の extended-delimiter 文字列補間）。
    private static let anyDigits = #"[0-9０-９]+|[一二三四五六七八九十]{1,3}"#

    private static func extractReminders(_ text: String, consumed: inout [Range<String.Index>], into result: inout Result) {
        // N分前 / N時間前
        for hit in matches(in: text, pattern: #"(\#(anyDigits))\s*(分|時間)前"#, avoiding: consumed) {
            guard let num = toInt(hit.groups[1]), let unit = hit.groups[2] else { continue }
            let mins = (unit == "時間") ? num * 60 : num
            result.reminderOffsets.append(mins)
            result.chips.append((.when, "\(num)\(unit)前"))
            consumed.append(hit.range)
        }
        // 前日
        for hit in matches(in: text, pattern: #"前日"#, avoiding: consumed) {
            result.reminderOffsets.append(1440)
            result.chips.append((.when, "前日"))
            consumed.append(hit.range)
        }
        // 当日朝 / 朝一
        for hit in matches(in: text, pattern: #"当日朝|朝一"#, avoiding: consumed) {
            result.reminderOffsets.append(0)
            result.chips.append((.when, String(text[hit.range])))
            consumed.append(hit.range)
        }
    }

    // MARK: - RRule

    private static func extractRRule(_ text: String, now: Date, calendar: Calendar, consumed: inout [Range<String.Index>], into result: inout Result, impliedDate: inout Date?) {
        // 走査順は specific → generic、最初のヒットのみ採用。
        func try_(_ pattern: String, _ handler: (RegexHit) -> Bool) {
            guard result.rrule == nil else { return }
            for hit in matches(in: text, pattern: pattern, avoiding: consumed) {
                if handler(hit) {
                    consumed.append(hit.range)
                    return
                }
            }
        }

        try_(#"毎週([月火水木金土日])曜?"#) { hit in
            guard let jp = hit.groups[1], let code = weekdayCode(jp) else { return false }
            result.rrule = "FREQ=WEEKLY;BYDAY=\(code)"
            impliedDate = nextWeekday(code: code, from: now, calendar: calendar)
            result.chips.append((.when, "毎週\(jp)曜"))
            return true
        }
        try_(#"毎([月火水木金土日])曜"#) { hit in
            guard let jp = hit.groups[1], let code = weekdayCode(jp) else { return false }
            result.rrule = "FREQ=WEEKLY;BYDAY=\(code)"
            impliedDate = nextWeekday(code: code, from: now, calendar: calendar)
            result.chips.append((.when, "毎\(jp)曜"))
            return true
        }
        try_(#"平日|月[〜~\-]金|月から金"#) { _ in
            result.rrule = "FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR"
            impliedDate = nextWeekdayInSet(codes: ["MO","TU","WE","TH","FR"], from: now, calendar: calendar)
            result.chips.append((.when, "平日"))
            return true
        }
        try_(#"週末|土日"#) { _ in
            result.rrule = "FREQ=WEEKLY;BYDAY=SA,SU"
            impliedDate = nextWeekdayInSet(codes: ["SA","SU"], from: now, calendar: calendar)
            result.chips.append((.when, "週末"))
            return true
        }
        try_(#"毎朝"#) { _ in
            result.rrule = "FREQ=DAILY"
            impliedDate = todayAt(hour: 9, minute: 0, now: now, calendar: calendar)
            result.chips.append((.when, "毎朝"))
            return true
        }
        try_(#"毎晩|毎夜"#) { _ in
            result.rrule = "FREQ=DAILY"
            impliedDate = todayAt(hour: 20, minute: 0, now: now, calendar: calendar)
            result.chips.append((.when, "毎晩"))
            return true
        }
        try_(#"毎日|日々"#) { _ in
            result.rrule = "FREQ=DAILY"
            impliedDate = calendar.startOfDay(for: now)
            result.chips.append((.when, "毎日"))
            return true
        }
        try_(#"毎月末"#) { _ in
            result.rrule = "FREQ=MONTHLY;BYMONTHDAY=-1"
            impliedDate = lastDayOfMonth(from: now, calendar: calendar)
            result.chips.append((.when, "毎月末"))
            return true
        }
        try_(#"毎月(\#(anyDigits))日"#) { hit in
            guard let d = toInt(hit.groups[1]), (1...31).contains(d) else { return false }
            result.rrule = "FREQ=MONTHLY;BYMONTHDAY=\(d)"
            impliedDate = nextDayOfMonth(day: d, from: now, calendar: calendar)
            result.chips.append((.when, "毎月\(d)日"))
            return true
        }
        try_(#"毎月"#) { _ in
            result.rrule = "FREQ=MONTHLY"
            impliedDate = calendar.startOfDay(for: now)
            result.chips.append((.when, "毎月"))
            return true
        }
        try_(#"毎週"#) { _ in
            result.rrule = "FREQ=WEEKLY"
            impliedDate = calendar.startOfDay(for: now)
            result.chips.append((.when, "毎週"))
            return true
        }
        try_(#"毎年|毎年度"#) { _ in
            result.rrule = "FREQ=YEARLY"
            impliedDate = calendar.startOfDay(for: now)
            result.chips.append((.when, "毎年"))
            return true
        }
        // ponytail: INTERVAL は TaskItem.occurs() 未対応。rrule 文字列は保存されるが表示上は間引き無視。
        try_(#"隔週"#) { _ in
            result.rrule = "FREQ=WEEKLY;INTERVAL=2"
            impliedDate = calendar.startOfDay(for: now)
            result.chips.append((.when, "隔週"))
            return true
        }
    }

    // MARK: - Relative time (N時間後 / N分後 / Nヶ月後 / N年後 …)

    private static func extractRelative(_ text: String, now: Date, calendar: Calendar, consumed: inout [Range<String.Index>], into result: inout Result, date: inout Date?) {
        // specific → generic。月・年はうるう年/月末クランプがあるので Calendar 経由で計算する。
        let patterns: [(String, (RegexHit) -> Date?)] = [
            (#"(\#(anyDigits))\s*年後"#, { h in
                guard let yy = toInt(h.groups[1]) else { return nil }
                return calendar.date(byAdding: .year, value: yy, to: now)
            }),
            (#"(\#(anyDigits))\s*(ヶ月|カ月|か月)後"#, { h in
                guard let mm = toInt(h.groups[1]) else { return nil }
                return calendar.date(byAdding: .month, value: mm, to: now)
            }),
            (#"(\#(anyDigits))\s*週間後"#, { h in
                guard let ww = toInt(h.groups[1]) else { return nil }
                return calendar.date(byAdding: .day, value: ww * 7, to: now)
            }),
            (#"(\#(anyDigits))\s*日後"#, { h in
                guard let dd = toInt(h.groups[1]) else { return nil }
                return calendar.date(byAdding: .day, value: dd, to: now)
            }),
            (#"(\#(anyDigits))\s*時間(\#(anyDigits))\s*分後"#, { h in
                guard let hh = toInt(h.groups[1]), let mm = toInt(h.groups[2]) else { return nil }
                return now.addingTimeInterval(TimeInterval(hh * 3600 + mm * 60))
            }),
            (#"(\#(anyDigits))\s*時間半後"#, { h in
                guard let hh = toInt(h.groups[1]) else { return nil }
                return now.addingTimeInterval(TimeInterval(hh * 3600 + 1800))
            }),
            (#"(\#(anyDigits))\s*時間後"#, { h in
                guard let hh = toInt(h.groups[1]) else { return nil }
                return now.addingTimeInterval(TimeInterval(hh * 3600))
            }),
            (#"(\#(anyDigits))\s*分後"#, { h in
                guard let mm = toInt(h.groups[1]) else { return nil }
                return now.addingTimeInterval(TimeInterval(mm * 60))
            }),
        ]
        for (pattern, extractor) in patterns {
            guard date == nil else { return }
            if let hit = matches(in: text, pattern: pattern, avoiding: consumed).first,
               let d = extractor(hit) {
                date = d
                result.chips.append((.when, String(text[hit.range])))
                consumed.append(hit.range)
            }
        }
    }

    // MARK: - Who (関係語彙)

    /// 関係語彙リスト（長い順に走査するため sorted 側で並べ替える）。
    private static let relationshipWords: [String] = [
        // 家族
        "おばあちゃん", "おじいちゃん", "お母さん", "お父さん",
        "母親", "父親", "祖母", "祖父",
        "家族", "母", "父", "兄", "姉", "妹", "弟",
        "娘", "息子", "妻", "夫",
        // 友人・恋愛
        "幼馴染", "友達", "友人", "彼氏", "彼女", "恋人",
        // 学校・職場
        "クラスメート", "先生", "先輩", "後輩", "同僚", "上司", "部下", "同期", "教授",
    ]

    private static func extractWho(_ text: String, consumed: inout [Range<String.Index>], into result: inout Result) {
        guard result.whoHint == nil else { return }
        // 長い語を先に照合（お母さん が 母 に食われないため）
        let sorted = relationshipWords.sorted { $0.count > $1.count }
        for word in sorted {
            guard result.whoHint == nil else { return }
            for r in standaloneMatches(in: text, word: word, avoiding: consumed) {
                result.whoHint = word
                result.chips.append((.who, word))
                consumed.append(r)
                return
            }
        }
    }

    // MARK: - Where (場所語彙)

    /// 抽象的・公共的な場所語彙。「公園に行く」「海で泳ぐ」等の場所を認識する。長い順に走査して
    /// 短い語の誤ヒットを避ける（映画館→館 等）。
    /// ponytail: ユーザーが個別マッピングしたがりそうな語（大学/会社/学校/家/実家/職場/部屋/
    /// オフィス 等）は意図的に除外。それらは PhraseAlias でユーザーが具体名を割り当てる（例:
    /// 大学 → 大学図書館）用途を優先する。
    private static let placeWords: [String] = [
        // 屋外の自然
        "公園", "海", "山", "川", "湖", "森", "ビーチ",
        // 交通・宗教
        "空港", "駅", "港", "神社", "寺", "教会",
        // 施設・公共
        "図書館", "病院", "歯医者", "銀行", "郵便局", "役所", "警察署", "市役所",
        // 買い物
        "スーパー", "コンビニ", "デパート", "モール", "ドラッグストア", "本屋",
        // 飲食
        "カフェ", "レストラン", "居酒屋", "バー", "食堂",
        // 運動・娯楽
        "ジム", "スタジオ", "プール", "温泉", "銭湯",
        "映画館", "美術館", "博物館", "動物園", "水族館",
    ]

    private static func extractWhere(_ text: String, consumed: inout [Range<String.Index>], into result: inout Result) {
        guard result.whereHint == nil else { return }
        let sorted = placeWords.sorted { $0.count > $1.count }
        for word in sorted {
            guard result.whereHint == nil else { return }
            for r in standaloneMatches(in: text, word: word, avoiding: consumed) {
                result.whereHint = word
                result.chips.append((.where_, word))
                consumed.append(r)
                return
            }
        }
    }

    // MARK: - Date part (今日 / 明日 / 来週火曜 / 5月10日 …)

    private static func extractDatePart(_ text: String, now: Date, calendar: Calendar, consumed: inout [Range<String.Index>], into result: inout Result, date: inout Date?) {
        let startOfToday = calendar.startOfDay(for: now)

        // 3日単位相対（明々後日 = 3日後）
        if takeFirst(text, pattern: #"明々後日|明明後日"#, consumed: &consumed, chipsInto: &result, label: "明々後日") {
            date = calendar.date(byAdding: .day, value: 3, to: startOfToday); return
        }
        if takeFirst(text, pattern: #"明後日"#, consumed: &consumed, chipsInto: &result, label: "明後日") {
            date = calendar.date(byAdding: .day, value: 2, to: startOfToday); return
        }
        if takeFirst(text, pattern: #"明日"#, consumed: &consumed, chipsInto: &result, label: "明日") {
            date = calendar.date(byAdding: .day, value: 1, to: startOfToday); return
        }
        if takeFirst(text, pattern: #"今日"#, consumed: &consumed, chipsInto: &result, label: "今日") {
            date = startOfToday; return
        }
        if takeFirst(text, pattern: #"一昨日"#, consumed: &consumed, chipsInto: &result, label: "一昨日") {
            date = calendar.date(byAdding: .day, value: -2, to: startOfToday); return
        }
        if takeFirst(text, pattern: #"昨日"#, consumed: &consumed, chipsInto: &result, label: "昨日") {
            date = calendar.date(byAdding: .day, value: -1, to: startOfToday); return
        }

        // 来週<曜日> / 今週<曜日> / 再来週<曜日>
        for (prefix, weekOffset) in [("再来週", 2), ("来週", 1), ("今週", 0)] {
            if let hit = matches(in: text, pattern: "\(prefix)([月火水木金土日])曜?", avoiding: consumed).first,
               let jp = hit.groups[1], let code = weekdayCode(jp) {
                date = weekdayInOffsetWeek(code: code, weekOffset: weekOffset, from: now, calendar: calendar)
                result.chips.append((.when, "\(prefix)\(jp)曜"))
                consumed.append(hit.range)
                return
            }
        }

        // 曜日単独: 次に来るその曜日
        if let hit = matches(in: text, pattern: #"([月火水木金土日])曜(日)?"#, avoiding: consumed).first,
           let jp = hit.groups[1], let code = weekdayCode(jp) {
            date = nextWeekday(code: code, from: now, calendar: calendar)
            result.chips.append((.when, "\(jp)曜"))
            consumed.append(hit.range)
            return
        }

        // 再来週 / 来週 / 先週 / 今週 単独
        if takeFirst(text, pattern: #"再来週"#, consumed: &consumed, chipsInto: &result, label: "再来週") {
            date = calendar.date(byAdding: .day, value: 14, to: startOfToday); return
        }
        if takeFirst(text, pattern: #"来週"#, consumed: &consumed, chipsInto: &result, label: "来週") {
            date = calendar.date(byAdding: .day, value: 7, to: startOfToday); return
        }
        if takeFirst(text, pattern: #"先週"#, consumed: &consumed, chipsInto: &result, label: "先週") {
            date = calendar.date(byAdding: .day, value: -7, to: startOfToday); return
        }
        if takeFirst(text, pattern: #"今週"#, consumed: &consumed, chipsInto: &result, label: "今週") {
            date = startOfToday; return
        }

        // 再来月 / 来月 / 先月 / 今月 単独
        if takeFirst(text, pattern: #"再来月"#, consumed: &consumed, chipsInto: &result, label: "再来月") {
            date = calendar.date(byAdding: .month, value: 2, to: startOfToday); return
        }
        if takeFirst(text, pattern: #"来月"#, consumed: &consumed, chipsInto: &result, label: "来月") {
            date = calendar.date(byAdding: .month, value: 1, to: startOfToday); return
        }
        if takeFirst(text, pattern: #"先月"#, consumed: &consumed, chipsInto: &result, label: "先月") {
            date = calendar.date(byAdding: .month, value: -1, to: startOfToday); return
        }
        if takeFirst(text, pattern: #"今月"#, consumed: &consumed, chipsInto: &result, label: "今月") {
            date = startOfToday; return
        }

        // M月D日
        if let hit = matches(in: text, pattern: #"(\#(anyDigits))月(\#(anyDigits))日"#, avoiding: consumed).first,
           let m = toInt(hit.groups[1]), let d = toInt(hit.groups[2]),
           (1...12).contains(m), (1...31).contains(d) {
            date = dateForMonthDay(month: m, day: d, from: now, calendar: calendar)
            result.chips.append((.when, "\(m)月\(d)日"))
            consumed.append(hit.range)
            return
        }
        // M/D
        if let hit = matches(in: text, pattern: #"([0-9]{1,2})/([0-9]{1,2})"#, avoiding: consumed).first,
           let m = toInt(hit.groups[1]), let d = toInt(hit.groups[2]),
           (1...12).contains(m), (1...31).contains(d) {
            date = dateForMonthDay(month: m, day: d, from: now, calendar: calendar)
            result.chips.append((.when, "\(m)/\(d)"))
            consumed.append(hit.range)
            return
        }
        // D日 単独（月省略）
        if let hit = matches(in: text, pattern: #"(\#(anyDigits))日"#, avoiding: consumed).first,
           let d = toInt(hit.groups[1]), (1...31).contains(d) {
            date = nextDayOfMonth(day: d, from: now, calendar: calendar)
            result.chips.append((.when, "\(d)日"))
            consumed.append(hit.range)
            return
        }
    }

    // MARK: - Time parts (14:00 / 14時半 / 午後2時 / 朝)

    private static func extractTimeParts(_ text: String, consumed: inout [Range<String.Index>], into result: inout Result, times: inout [(hour: Int, minute: Int)]) {
        // 数字表現（アラビア数字/全角数字/漢数字 いずれか）。漢数字は一〜二十三の範囲まで（三文字上限）。
        // (?!間) は「一時間」等の duration 表現に 時 の位置で誤マッチしないための否定先読み。
        let hourDigits = #"[0-9０-９]{1,2}|[一二三四五六七八九十]{1,3}"#
        let minuteDigits = hourDigits

        // 午前 / 午後 明示
        for hit in matches(in: text, pattern: #"(午前|午後)(\#(hourDigits))時(?!間)(半|(\#(minuteDigits))分)?"#, avoiding: consumed) {
            guard let ampm = hit.groups[1], var h = toInt(hit.groups[2]), (0...12).contains(h) else { continue }
            if ampm == "午後" && h < 12 { h += 12 }
            if ampm == "午前" && h == 12 { h = 0 }
            var m = 0
            if let g3 = hit.groups[3], g3 == "半" { m = 30 }
            else if let g4 = hit.groups[4], let mm = toInt(g4), (0...59).contains(mm) { m = mm }
            times.append((h, m))
            result.chips.append((.when, "\(ampm)\(h % 12 == 0 ? 12 : h % 12)時" + (m > 0 ? "\(m)分" : "")))
            consumed.append(hit.range)
        }

        // HH:MM
        for hit in matches(in: text, pattern: #"([0-9]{1,2}):([0-9]{2})"#, avoiding: consumed) {
            guard let h = toInt(hit.groups[1]), let m = toInt(hit.groups[2]),
                  (0...23).contains(h), (0...59).contains(m) else { continue }
            times.append((h, m))
            result.chips.append((.when, String(format: "%d:%02d", h, m)))
            consumed.append(hit.range)
        }

        // H時 (半 | N分)?   ※ (?!間) で 「一時間」誤マッチを排除
        for hit in matches(in: text, pattern: #"(\#(hourDigits))時(?!間)(半|(\#(minuteDigits))分)?"#, avoiding: consumed) {
            guard let h = toInt(hit.groups[1]), (0...25).contains(h) else { continue }
            var m = 0
            if let g2 = hit.groups[2], g2 == "半" { m = 30 }
            else if let g3 = hit.groups[3], let mm = toInt(g3), (0...59).contains(mm) { m = mm }
            times.append((h, m))
            result.chips.append((.when, "\(h)時" + (m > 0 ? "\(m)分" : "")))
            consumed.append(hit.range)
        }

        // 語彙時刻: 朝 = 09:00, 昼 = 12:00, 夕方 = 17:00, 夜 = 20:00, 深夜 = 23:00
        // ponytail: 誤検出防止で厳しい単語境界を要求（空白/ASCII/文頭文末で挟まれる時のみ）。
        // 「朝食」「夜ジョギング」等の複合はマッチしない。ユーザーは空白を入れるか「20時」等を使う。
        for (word, hour) in [("深夜", 23), ("夕方", 17), ("朝", 9), ("昼", 12), ("夜", 20)] {
            for r in standaloneMatches(in: text, word: word, avoiding: consumed) {
                times.append((hour, 0))
                result.chips.append((.when, word))
                consumed.append(r)
            }
        }
    }

    // MARK: - Compose

    private static func composeStart(relative: Date?, datePart: Date?, rruleImplied: Date?, firstTime: (hour: Int, minute: Int)?, now: Date, calendar: Calendar) -> Date? {
        if let r = relative { return r }
        let base = datePart ?? rruleImplied
        if let t = firstTime {
            let target = base ?? now
            let withTime = calendar.date(bySettingHour: t.hour, minute: t.minute, second: 0, of: target) ?? target
            // datePart も rruleImplied も無く時刻だけの場合、その時刻が既に過ぎていれば翌日を使う。
            if base == nil, withTime < now {
                return calendar.date(byAdding: .day, value: 1, to: withTime) ?? withTime
            }
            return withTime
        }
        return base
    }

    // MARK: - Regex helpers

    private struct RegexHit {
        let range: Range<String.Index>
        let groups: [String?]
    }

    private static func matches(in text: String, pattern: String, avoiding: [Range<String.Index>]) -> [RegexHit] {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return [] }
        let full = NSRange(text.startIndex..<text.endIndex, in: text)
        return re.matches(in: text, range: full).compactMap { m in
            guard let range = Range(m.range, in: text) else { return nil }
            if avoiding.contains(where: { $0.overlaps(range) }) { return nil }
            var groups: [String?] = []
            for i in 0..<m.numberOfRanges {
                let r = m.range(at: i)
                if r.location == NSNotFound {
                    groups.append(nil)
                } else if let rr = Range(r, in: text) {
                    groups.append(String(text[rr]))
                } else {
                    groups.append(nil)
                }
            }
            return RegexHit(range: range, groups: groups)
        }
    }

    /// pattern の最初のマッチを消費し、chip を追加する簡易ラッパー。
    private static func takeFirst(_ text: String, pattern: String, consumed: inout [Range<String.Index>], chipsInto result: inout Result, label: String) -> Bool {
        guard let hit = matches(in: text, pattern: pattern, avoiding: consumed).first else { return false }
        result.chips.append((.when, label))
        consumed.append(hit.range)
        return true
    }

    /// 単一字/短語彙が「単語として独立している」箇所だけを返す（複合語 "朝食" を排除するため）。
    private static func standaloneMatches(in text: String, word: String, avoiding: [Range<String.Index>]) -> [Range<String.Index>] {
        var hits: [Range<String.Index>] = []
        var cursor = text.startIndex
        while cursor < text.endIndex, let r = text.range(of: word, range: cursor..<text.endIndex) {
            defer { cursor = r.upperBound }
            if avoiding.contains(where: { $0.overlaps(r) }) { continue }
            let before: Character? = r.lowerBound > text.startIndex ? text[text.index(before: r.lowerBound)] : nil
            let after: Character? = r.upperBound < text.endIndex ? text[r.upperBound] : nil
            guard isStandaloneBoundary(before), isStandaloneBoundary(after) else { continue }
            hits.append(r)
        }
        return hits
    }

    private static func isStandaloneBoundary(_ c: Character?) -> Bool {
        guard let c else { return true }
        if c.isWhitespace { return true }
        if let s = c.unicodeScalars.first {
            // ASCII 記号（英数字ではない）は境界扱い
            if s.value < 0x80 { return !c.isLetter && !c.isNumber }
            // 平仮名は境界扱い（助詞 と/に/の/へ/を/が が続く自然な用法）
            if (0x3040...0x309F).contains(s.value) { return true }
        }
        // 漢字・カタカナが続くなら複合語の可能性があるので境界とみなさない
        return false
    }

    private static func toInt(_ s: String?) -> Int? {
        guard let s else { return nil }
        let trimmed = s.trimmingCharacters(in: .whitespaces)
        let half = trimmed.applyingTransform(.fullwidthToHalfwidth, reverse: false) ?? trimmed
        if let n = Int(half) { return n }
        return parseKanjiInt(trimmed)
    }

    /// 漢数字 → 整数。0〜99 まで対応（時刻は 0〜23、分は 0〜59 の範囲で使う）。
    /// 一〜九 / 十 / 十一 / 二十 / 二十三 / 三十 / 五十九 等。
    private static func parseKanjiInt(_ s: String) -> Int? {
        let single: [Character: Int] = ["一":1, "二":2, "三":3, "四":4, "五":5, "六":6, "七":7, "八":8, "九":9]
        guard !s.isEmpty else { return nil }
        // 単字（一〜九、十）
        if s.count == 1 {
            if s == "十" { return 10 }
            return single[s.first!]
        }
        // 十X（十一〜十九）
        if s.count == 2, s.first == "十" {
            return single[s.last!].map { 10 + $0 }
        }
        // X十（二十〜九十）
        if s.count == 2, s.last == "十" {
            return single[s.first!].map { $0 * 10 }
        }
        // X十Y（二十一〜九十九）
        if s.count == 3, s[s.index(after: s.startIndex)] == "十" {
            guard let tens = single[s.first!], let ones = single[s.last!] else { return nil }
            return tens * 10 + ones
        }
        return nil
    }

    private static func mergeRanges(_ ranges: [Range<String.Index>]) -> [Range<String.Index>] {
        let sorted = ranges.sorted { $0.lowerBound < $1.lowerBound }
        var merged: [Range<String.Index>] = []
        for r in sorted {
            if let last = merged.last, r.lowerBound <= last.upperBound {
                merged[merged.count - 1] = last.lowerBound..<max(last.upperBound, r.upperBound)
            } else {
                merged.append(r)
            }
        }
        return merged
    }

    // MARK: - Calendar helpers

    private static let weekdayCodeMap: [String: String] = [
        "日": "SU", "月": "MO", "火": "TU", "水": "WE",
        "木": "TH", "金": "FR", "土": "SA"
    ]
    private static let weekdayCodesInOrder = ["SU", "MO", "TU", "WE", "TH", "FR", "SA"]

    private static func weekdayCode(_ jp: String) -> String? { weekdayCodeMap[jp] }

    /// 指定コードの曜日で「今日以降で最も近い日」を返す（今日該当ならその日）。時刻は 00:00。
    private static func nextWeekday(code: String, from date: Date, calendar: Calendar) -> Date {
        guard let targetIdx = weekdayCodesInOrder.firstIndex(of: code) else { return date }
        let currentIdx = calendar.component(.weekday, from: date) - 1
        var delta = targetIdx - currentIdx
        if delta < 0 { delta += 7 }
        let start = calendar.startOfDay(for: date)
        return calendar.date(byAdding: .day, value: delta, to: start) ?? start
    }

    /// 指定コード群のうち最も早い曜日を返す（今日該当ならその日）。
    private static func nextWeekdayInSet(codes: [String], from date: Date, calendar: Calendar) -> Date {
        let start = calendar.startOfDay(for: date)
        for i in 0..<7 {
            guard let d = calendar.date(byAdding: .day, value: i, to: start) else { continue }
            let idx = calendar.component(.weekday, from: d) - 1
            if codes.contains(weekdayCodesInOrder[idx]) { return d }
        }
        return start
    }

    /// 「今週 / 来週 / 再来週 の <曜日>」を返す。週の起点は calendar.firstWeekday。
    private static func weekdayInOffsetWeek(code: String, weekOffset: Int, from date: Date, calendar: Calendar) -> Date {
        guard let targetIdx = weekdayCodesInOrder.firstIndex(of: code) else { return date }
        let firstWeekday = calendar.firstWeekday - 1
        let currentIdx = calendar.component(.weekday, from: date) - 1
        let deltaToWeekStart = -((currentIdx - firstWeekday + 7) % 7)
        let startOfWeek = calendar.date(byAdding: .day, value: deltaToWeekStart, to: calendar.startOfDay(for: date)) ?? date
        var delta = (targetIdx - firstWeekday + 7) % 7
        delta += weekOffset * 7
        return calendar.date(byAdding: .day, value: delta, to: startOfWeek) ?? startOfWeek
    }

    private static func nextDayOfMonth(day: Int, from date: Date, calendar: Calendar) -> Date {
        var comps = calendar.dateComponents([.year, .month, .day], from: date)
        let today = comps.day ?? 1
        comps.day = day
        var candidate = calendar.date(from: comps) ?? date
        if day < today {
            comps.month = (comps.month ?? 1) + 1
            candidate = calendar.date(from: comps) ?? candidate
        }
        return calendar.startOfDay(for: candidate)
    }

    private static func lastDayOfMonth(from date: Date, calendar: Calendar) -> Date {
        guard let range = calendar.range(of: .day, in: .month, for: date) else { return date }
        var comps = calendar.dateComponents([.year, .month], from: date)
        comps.day = range.upperBound - 1
        return calendar.date(from: comps).map { calendar.startOfDay(for: $0) } ?? date
    }

    private static func todayAt(hour: Int, minute: Int, now: Date, calendar: Calendar) -> Date {
        calendar.date(bySettingHour: hour, minute: minute, second: 0, of: now) ?? now
    }

    private static func dateForMonthDay(month: Int, day: Int, from now: Date, calendar: Calendar) -> Date {
        var comps = calendar.dateComponents([.year, .month, .day], from: now)
        comps.month = month
        comps.day = day
        var candidate = calendar.date(from: comps) ?? now
        if candidate < calendar.startOfDay(for: now) {
            comps.year = (comps.year ?? 0) + 1
            candidate = calendar.date(from: comps) ?? candidate
        }
        return calendar.startOfDay(for: candidate)
    }
}
