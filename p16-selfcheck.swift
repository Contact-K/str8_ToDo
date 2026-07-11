// Run: DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swiftc -parse-as-library "str(8) ToDo/WHCategory.swift" "str(8) ToDo/PhraseAlias.swift" "str(8) ToDo/PhraseParser.swift" p16-selfcheck.swift -o /tmp/p16check && /tmp/p16check

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

        print("P16 self-check: ALL PASS")
    }
}
