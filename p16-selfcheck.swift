// Run: DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swiftc -parse-as-library "str(8) ToDo/WHCategory.swift" "str(8) ToDo/PhraseAlias.swift" "str(8) ToDo/JPRuleLayer.swift" "str(8) ToDo/PhraseParser.swift" p16-selfcheck.swift -o /tmp/p16check && /tmp/p16check

import Foundation

@main
struct P16SelfCheck {
    static func main() {
        // Test 1: 日時 + PhraseAlias（where_）+ タイトル残り
        // 「明日 14:00 大学でレポート」→ 日時認識、"大学"→"大学図書館"（場所ヒント）、
        // 残り語（"レポート" 等）は titleRemainder に保持される。
        do {
            let alias = PhraseAlias(keyword: "大学", whCategory: .where_, replacement: "大学図書館")
            let result = PhraseParser.parse("明日 14:00 大学でレポート", aliases: [alias])
            assert(result.startDate != nil, "「明日 14:00」は日時として認識されるべき")
            assert(result.placeHint == "大学図書館", "「大学」エイリアスが場所ヒントに反映されるべき, got \(result.placeHint ?? "nil")")
            assert(result.titleRemainder.contains("レポート"), "認識できない語はタイトル残りに保持されるべき, got \(result.titleRemainder)")
            assert(result.recognizedChips.contains { $0.0 == .where_ && $0.1 == "大学図書館" }, "where_ チップが記録されるべき")
        }

        // Test 2: how（所要時間）エイリアス
        // 「ポモ 勉強する」→ "ポモ"→"25分" で duration=1500秒
        do {
            let alias = PhraseAlias(keyword: "ポモ", whCategory: .how, replacement: "25分")
            let result = PhraseParser.parse("ポモ 勉強する", aliases: [alias])
            assert(result.duration == 1500, "「ポモ」→「25分」は 1500秒 になるべき, got \(String(describing: result.duration))")
        }

        // Test 3: エイリアスなし・平文 → 何も認識されずタイトル残りのみ（情報を握りつぶさない）
        do {
            let result = PhraseParser.parse("部屋の掃除をする", aliases: [])
            assert(result.startDate == nil, "日時表現が無ければ startDate は nil")
            assert(result.placeHint == nil && result.categoryHint == nil, "エイリアス無しならヒントは無い")
            assert(!result.titleRemainder.isEmpty, "認識できない語はすべてタイトル残りに保持されるべき")
            assert(!result.unrecognizedWords.isEmpty, "unrecognizedWords も保持されるべき")
        }

        // Test 4: which（分類）エイリアス
        do {
            let alias = PhraseAlias(keyword: "会社", whCategory: .which, replacement: "会社")
            let result = PhraseParser.parse("会社で打ち合わせ", aliases: [alias])
            assert(result.categoryHint == "会社", "「会社」エイリアスが分類ヒントに反映されるべき")
        }

        // Test 5: isEnabled=false のエイリアスは無視される
        do {
            let disabled = PhraseAlias(keyword: "大学", whCategory: .where_, replacement: "大学図書館", isEnabled: false)
            let result = PhraseParser.parse("大学でレポート", aliases: [disabled])
            assert(result.placeHint == nil, "isEnabled=false のエイリアスは適用されないべき")
            assert(result.titleRemainder.contains("大学"), "無効化されたエイリアスの語はタイトル残りに残るべき")
        }

        // Test 6: 自己参照的なエイリアス（"無限"→"無限"、when カテゴリ）でも再帰は最大2段で止まり
        // ハング/クラッシュしないこと（再帰ガードの検証）。
        do {
            let selfRef = PhraseAlias(keyword: "無限", whCategory: .when, replacement: "無限")
            let result = PhraseParser.parse("無限ループ注意", aliases: [selfRef])
            _ = result.titleRemainder // 完了すれば無限再帰していないことの証明
        }

        // MARK: - Phase 16 拡張: JPRuleLayer 日本語規則パーステスト
        // 固定 now = 2026-07-16 (木) 10:00 JST で決定論的に検証。

        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        let now = date(cal, y: 2026, m: 7, d: 16, h: 10, min: 0)!  // 2026-07-16 (Thu) 10:00 JST

        // JP01: 「明日 14時半 レポート」→ 明日14:30, remainder=レポート
        do {
            let r = JPRuleLayer.extract("明日 14時半 レポート", now: now, calendar: cal)
            let expected = date(cal, y: 2026, m: 7, d: 17, h: 14, min: 30)!
            assertEqual(r.startDate, expected, "JP01 明日 14時半")
            let remainder = JPRuleLayer.remainder(from: "明日 14時半 レポート", consumed: r.consumed)
            assert(remainder.contains("レポート"), "JP01 remainder に レポート が残るべき, got \(remainder)")
        }

        // JP02: 「来週火曜 3時から5時 打ち合わせ」→ 来週火 03:00, duration=7200
        do {
            let r = JPRuleLayer.extract("来週火曜 3時から5時 打ち合わせ", now: now, calendar: cal)
            // now は 2026-07-16 (木). 今週火曜は 2026-07-14, 来週火曜は 2026-07-21.
            let expected = date(cal, y: 2026, m: 7, d: 21, h: 3, min: 0)!
            assertEqual(r.startDate, expected, "JP02 来週火曜 3時")
            assert(r.duration == 7200, "JP02 duration=7200, got \(String(describing: r.duration))")
        }

        // JP03: 「毎週水曜 21時 掃除」→ rrule=WEEKLY;BYDAY=WE, startDate=次の水曜 21:00
        do {
            let r = JPRuleLayer.extract("毎週水曜 21時 掃除", now: now, calendar: cal)
            assert(r.rrule == "FREQ=WEEKLY;BYDAY=WE", "JP03 rrule, got \(r.rrule ?? "nil")")
            // now=2026-07-16(木). 次の水曜は 2026-07-22.
            let expected = date(cal, y: 2026, m: 7, d: 22, h: 21, min: 0)!
            assertEqual(r.startDate, expected, "JP03 次の水曜 21:00")
        }

        // JP04: 「平日 朝 ストレッチ」→ rrule=WEEKLY;BYDAY=MO..FR, startDate=翌平日 09:00
        do {
            let r = JPRuleLayer.extract("平日 朝 ストレッチ", now: now, calendar: cal)
            assert(r.rrule == "FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR", "JP04 rrule, got \(r.rrule ?? "nil")")
            // now=2026-07-16(木). 平日なのでその日=木曜 09:00.
            let expected = date(cal, y: 2026, m: 7, d: 16, h: 9, min: 0)!
            assertEqual(r.startDate, expected, "JP04 今日(平日) 09:00")
        }

        // JP05: 「10分前と1時間前に通知 明日15時」→ reminderOffsets=[10,60], startDate=明日15:00
        do {
            let r = JPRuleLayer.extract("10分前と1時間前に通知 明日15時", now: now, calendar: cal)
            assert(r.reminderOffsets.sorted() == [10, 60], "JP05 reminder, got \(r.reminderOffsets)")
            let expected = date(cal, y: 2026, m: 7, d: 17, h: 15, min: 0)!
            assertEqual(r.startDate, expected, "JP05 明日15:00")
        }

        // JP06: 「! 重要 明日提出」→ isImportant=true, startDate=明日00:00
        do {
            let r = JPRuleLayer.extract("! 重要 明日提出", now: now, calendar: cal)
            assert(r.isImportant == true, "JP06 isImportant")
            let expected = date(cal, y: 2026, m: 7, d: 17, h: 0, min: 0)!
            assertEqual(r.startDate, expected, "JP06 明日00:00")
        }

        // JP07: 「1時間後 コンビニ」→ startDate=now+3600
        do {
            let r = JPRuleLayer.extract("1時間後 コンビニ", now: now, calendar: cal)
            let expected = now.addingTimeInterval(3600)
            assertEqual(r.startDate, expected, "JP07 1時間後")
        }

        // JP08: 「5/10 15:00 面談」→ startDate=2027-05-10 15:00 (今年5/10は既に過ぎているので来年)
        do {
            let r = JPRuleLayer.extract("5/10 15:00 面談", now: now, calendar: cal)
            let expected = date(cal, y: 2027, m: 5, d: 10, h: 15, min: 0)!
            assertEqual(r.startDate, expected, "JP08 5/10 15:00 spillover to next year")
        }

        // JP09: 「毎月10日 家賃」→ rrule=MONTHLY;BYMONTHDAY=10, startDate=次の10日
        do {
            let r = JPRuleLayer.extract("毎月10日 家賃", now: now, calendar: cal)
            assert(r.rrule == "FREQ=MONTHLY;BYMONTHDAY=10", "JP09 rrule, got \(r.rrule ?? "nil")")
            // now=2026-07-16(木). 今月の10日は過ぎているので次は 2026-08-10.
            let expected = date(cal, y: 2026, m: 8, d: 10, h: 0, min: 0)!
            assertEqual(r.startDate, expected, "JP09 次の10日")
        }

        // JP10: 「〆切 金曜まで」→ startDate=次の金曜（now=木曜なので明日金曜）
        do {
            let r = JPRuleLayer.extract("〆切 金曜まで", now: now, calendar: cal)
            // now=2026-07-16(木). 次の金曜は 2026-07-17.
            let expected = date(cal, y: 2026, m: 7, d: 17, h: 0, min: 0)!
            assertEqual(r.startDate, expected, "JP10 金曜")
        }

        // JP11: 「30分後 会議」→ startDate=now+1800
        do {
            let r = JPRuleLayer.extract("30分後 会議", now: now, calendar: cal)
            assertEqual(r.startDate, now.addingTimeInterval(1800), "JP11 30分後")
        }

        // JP12: 「毎日 21時 日記」→ rrule=DAILY, startDate=今日21:00
        do {
            let r = JPRuleLayer.extract("毎日 21時 日記", now: now, calendar: cal)
            assert(r.rrule == "FREQ=DAILY", "JP12 rrule DAILY, got \(r.rrule ?? "nil")")
            assertEqual(r.startDate, date(cal, y: 2026, m: 7, d: 16, h: 21, min: 0)!, "JP12 今日21:00")
        }

        // JP13: 午後の絶対表現「午後3時 打ち合わせ」→ 今日15:00 (過去なら翌日)
        do {
            let r = JPRuleLayer.extract("午後3時 打ち合わせ", now: now, calendar: cal)
            // now=10:00, 15:00 は未来なので今日
            assertEqual(r.startDate, date(cal, y: 2026, m: 7, d: 16, h: 15, min: 0)!, "JP13 午後3時 (今日)")
        }

        // MARK: - Phase 16.5 追加テスト

        // JP14: 「１ヶ月後 面談」→ startDate = +1 month (2026-08-16 10:00)
        do {
            let r = JPRuleLayer.extract("１ヶ月後 面談", now: now, calendar: cal)
            let expected = date(cal, y: 2026, m: 8, d: 16, h: 10, min: 0)!
            assertEqual(r.startDate, expected, "JP14 １ヶ月後")
        }

        // JP15: 「２年後 旅行」→ startDate = +2 years
        do {
            let r = JPRuleLayer.extract("２年後 旅行", now: now, calendar: cal)
            let expected = date(cal, y: 2028, m: 7, d: 16, h: 10, min: 0)!
            assertEqual(r.startDate, expected, "JP15 ２年後")
        }

        // JP16: 「友達と映画」→ whoHint = 友達
        do {
            let r = JPRuleLayer.extract("友達と映画", now: now, calendar: cal)
            assert(r.whoHint == "友達", "JP16 whoHint 友達, got \(r.whoHint ?? "nil")")
        }

        // JP17: 「母と病院」→ whoHint = 母
        do {
            let r = JPRuleLayer.extract("母と病院", now: now, calendar: cal)
            assert(r.whoHint == "母", "JP17 whoHint 母, got \(r.whoHint ?? "nil")")
        }

        // JP18: 「お母さんと買い物」→ whoHint = お母さん (長い語優先)
        do {
            let r = JPRuleLayer.extract("お母さんと買い物", now: now, calendar: cal)
            assert(r.whoHint == "お母さん", "JP18 whoHint お母さん, got \(r.whoHint ?? "nil")")
        }

        // JP19: PhraseParser 統合 —「１ヶ月後に友達とマグロ漁」
        // startDate = +1M, whoHint=友達, titleRemainder に「マグロ漁」が 1 語で残る
        do {
            let r = PhraseParser.parse("１ヶ月後に友達とマグロ漁", aliases: [])
            let expected = date(cal, y: 2026, m: 8, d: 16, h: 10, min: 0)!
            _ = expected  // now は PhraseParser 側で .now が使われる（テスト用注入不可のため、時刻は非検証）
            assert(r.startDate != nil, "JP19 startDate 非nil, got nil")
            assert(r.whoHint == "友達", "JP19 whoHint 友達, got \(r.whoHint ?? "nil")")
            assert(r.titleRemainder.contains("マグロ漁"),
                   "JP19 titleRemainder に マグロ漁 が 1 語で残るべき, got '\(r.titleRemainder)'")
        }

        // JP20: 複合名詞回帰 —「就職活動を頑張る」 → titleRemainder に 就職活動 が 1 語
        do {
            let r = PhraseParser.parse("就職活動を頑張る", aliases: [])
            assert(r.titleRemainder.contains("就職活動"),
                   "JP20 titleRemainder に 就職活動 が 1 語で残るべき, got '\(r.titleRemainder)'")
        }

        // JP21: 過剰マージ回帰 —「大学 図書館」（空白あり）→ 分離維持
        // 「大学」は placeWords 対象外で titleRemainder に残り、「図書館」は placeWords に含まれる
        // ので whereHint→placeHint に抜ける。両者が「大学図書館」1 語に merge されないことを確認。
        do {
            let r = PhraseParser.parse("大学 図書館", aliases: [])
            assert(r.placeHint == "図書館", "JP21 図書館 → placeHint, got \(r.placeHint ?? "nil")")
            assert(r.titleRemainder.contains("大学"), "JP21 大学 残るべき, got '\(r.titleRemainder)'")
            assert(!r.titleRemainder.contains("大学図書館"),
                   "JP21 「大学図書館」1 語には結合しないべき, got '\(r.titleRemainder)'")
        }

        // JP22: 助詞・動詞語尾を merge しない回帰 —「掃除をする」→ unrecognizedWords に「掃除」が
        // 別トークンとして残り、辞書登録サジェスト対象になる（「掃除をする」1 語に潰れない）。
        do {
            let r = PhraseParser.parse("掃除をする", aliases: [])
            assert(r.unrecognizedWords.contains("掃除"),
                   "JP22 掃除 が独立トークンで残るべき, got \(r.unrecognizedWords)")
            assert(!r.unrecognizedWords.contains("掃除をする"),
                   "JP22 「掃除をする」1 語には結合しないべき, got \(r.unrecognizedWords)")
        }

        // JP23: 場所語彙 —「公園に行く」→ whereHint = 公園
        do {
            let r = JPRuleLayer.extract("公園に行く", now: now, calendar: cal)
            assert(r.whereHint == "公園", "JP23 whereHint 公園, got \(r.whereHint ?? "nil")")
        }

        // JP24: 場所語彙 —「海で泳ぐ」→ whereHint = 海
        do {
            let r = JPRuleLayer.extract("海で泳ぐ", now: now, calendar: cal)
            assert(r.whereHint == "海", "JP24 whereHint 海, got \(r.whereHint ?? "nil")")
        }

        // JP25: 場所語彙 長い順 —「映画館」→ whereHint = 映画館（館 単独にはならない）
        do {
            let r = JPRuleLayer.extract("明日 映画館 デート", now: now, calendar: cal)
            assert(r.whereHint == "映画館", "JP25 whereHint 映画館, got \(r.whereHint ?? "nil")")
        }

        // JP26: 場所語彙とユーザー alias の共存回帰 —「大学」は placeWords に無いので
        // PhraseAlias が動く。Test 1 と重複するが Phase 16.5 での明示的な確認。
        do {
            let alias = PhraseAlias(keyword: "大学", whCategory: .where_, replacement: "大学図書館")
            let r = PhraseParser.parse("明日 大学で勉強", aliases: [alias])
            assert(r.placeHint == "大学図書館", "JP26 大学→大学図書館 alias 優先, got \(r.placeHint ?? "nil")")
        }

        // JP27: PhraseParser 統合 —「1時間後 公園 友達と散歩」
        // startDate=+1h, whereHint→placeHint=公園, whoHint=友達
        do {
            let r = PhraseParser.parse("1時間後 公園 友達と散歩", aliases: [])
            assert(r.startDate != nil, "JP27 startDate 非nil")
            assert(r.placeHint == "公園", "JP27 placeHint 公園, got \(r.placeHint ?? "nil")")
            assert(r.whoHint == "友達", "JP27 whoHint 友達, got \(r.whoHint ?? "nil")")
        }

        // JP28: 漢数字時刻 —「午後一時」→ 13:00 (今日)
        do {
            let r = JPRuleLayer.extract("午後一時 打ち合わせ", now: now, calendar: cal)
            assertEqual(r.startDate, date(cal, y: 2026, m: 7, d: 16, h: 13, min: 0)!, "JP28 午後一時")
        }

        // JP29: 漢数字時刻半 —「午後一時半」→ 13:30
        do {
            let r = JPRuleLayer.extract("午後一時半", now: now, calendar: cal)
            assertEqual(r.startDate, date(cal, y: 2026, m: 7, d: 16, h: 13, min: 30)!, "JP29 午後一時半")
        }

        // JP30: 24h 漢数字 —「十四時」→ 14:00 (今日)
        do {
            let r = JPRuleLayer.extract("十四時 会議", now: now, calendar: cal)
            assertEqual(r.startDate, date(cal, y: 2026, m: 7, d: 16, h: 14, min: 0)!, "JP30 十四時")
        }

        // JP31: 漢数字時刻＋午前 —「午前十時」→ 10:00
        do {
            let r = JPRuleLayer.extract("午前十時", now: now, calendar: cal)
            assertEqual(r.startDate, date(cal, y: 2026, m: 7, d: 16, h: 10, min: 0)!, "JP31 午前十時")
        }

        // JP32: 「一時間後」→ 「一時」誤マッチせず「一時間後」= now+3600
        do {
            let r = JPRuleLayer.extract("一時間後", now: now, calendar: cal)
            assertEqual(r.startDate, now.addingTimeInterval(3600), "JP32 一時間後")
        }

        // JP33: 「一週間後」→ now+7日
        do {
            let r = JPRuleLayer.extract("一週間後 面談", now: now, calendar: cal)
            assertEqual(r.startDate, cal.date(byAdding: .day, value: 7, to: now)!, "JP33 一週間後")
        }

        // JP34: 「三日後」→ now+3日
        do {
            let r = JPRuleLayer.extract("三日後 会議", now: now, calendar: cal)
            assertEqual(r.startDate, cal.date(byAdding: .day, value: 3, to: now)!, "JP34 三日後")
        }

        // JP35: 「三十分前」→ reminderOffsets=[30]
        do {
            let r = JPRuleLayer.extract("三十分前 明日15時", now: now, calendar: cal)
            assert(r.reminderOffsets == [30], "JP35 三十分前, got \(r.reminderOffsets)")
        }

        // JP36: 「毎月十日」→ rrule=MONTHLY;BYMONTHDAY=10
        do {
            let r = JPRuleLayer.extract("毎月十日 家賃", now: now, calendar: cal)
            assert(r.rrule == "FREQ=MONTHLY;BYMONTHDAY=10", "JP36 毎月十日, got \(r.rrule ?? "nil")")
        }

        print("P16 self-check: ALL PASS")
    }

    // MARK: - Test helpers

    static func date(_ cal: Calendar, y: Int, m: Int, d: Int, h: Int, min: Int) -> Date? {
        var comps = DateComponents()
        comps.year = y; comps.month = m; comps.day = d
        comps.hour = h; comps.minute = min; comps.second = 0
        return cal.date(from: comps)
    }

    static func assertEqual(_ actual: Date?, _ expected: Date, _ label: String, file: StaticString = #file, line: UInt = #line) {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm z"
        f.timeZone = TimeZone(identifier: "Asia/Tokyo")
        let a = actual.map(f.string) ?? "nil"
        let e = f.string(from: expected)
        assert(actual == expected, "\(label): expected \(e), got \(a)", file: file, line: line)
    }
}
