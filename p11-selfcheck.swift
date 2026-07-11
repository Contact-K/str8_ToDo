//
//  p11-selfcheck.swift — Phase 11 の自己チェック（ウィジェット・スナップショットの純ロジック）
//
//  実行方法（macOS、リポジトリルートで）:
//    DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swiftc -parse-as-library \
//      "str(8) ToDo/WidgetShared.swift" \
//      p11-selfcheck.swift -o /tmp/p11check && /tmp/p11check
//
//  WidgetShared.swift は純 Foundation なので単体でコンパイルできる（SwiftData/WidgetKit 非依存）。
//  アプリターゲットには含めない（pbxproj 未登録）。ロジックが壊れたら assert で落ちる。
//  検証対象: (1) Codable 往復（アプリ書込⇄ウィジェット読取の契約） (2) 次カード選択 (3) タイムライン境界生成。
//

import Foundation

@main
struct P11SelfCheck {
    static func main() {
        // 秒単位の固定基準（.iso8601 は秒精度なので整数秒で往復が厳密に一致する）。
        let ref = Date(timeIntervalSinceReferenceDate: 800_000_000)
        func t(_ offsetMinutes: Int) -> Date { ref.addingTimeInterval(Double(offsetMinutes) * 60) }

        // --- 0) isStale 検証（生成日時が今日か否かで鮮度を判定）---
        let today = Date()
        let yesterday = today.addingTimeInterval(-86400)
        let dayBeforeYesterday = today.addingTimeInterval(-2 * 86400)

        let snapshotToday = WidgetSnapshot(generatedAt: today, upcoming: [], bands: [], achievementCount: 0, unconfirmedCount: 0)
        assert(snapshotToday.isStale == false, "generatedAt が今日なら isStale==false")

        let snapshotYesterday = WidgetSnapshot(generatedAt: yesterday, upcoming: [], bands: [], achievementCount: 0, unconfirmedCount: 0)
        assert(snapshotYesterday.isStale == true, "generatedAt が昨日なら isStale==true")

        let snapshotOld = WidgetSnapshot(generatedAt: dayBeforeYesterday, upcoming: [], bands: [], achievementCount: 0, unconfirmedCount: 0)
        assert(snapshotOld.isStale == true, "generatedAt が2日前なら isStale==true")

        let snap = WidgetSnapshot(
            generatedAt: t(0),
            upcoming: [
                .init(title: "朝会",   start: t(60),  end: t(90),  colorHex: "#FF0000", isTimePinned: true),
                .init(title: "ランチ", start: t(240), end: t(300), colorHex: nil,       isTimePinned: false)
            ],
            bands: [.init(name: "午前", startMinutes: 540, endMinutes: 720)],
            achievementCount: 3,
            unconfirmedCount: 2
        )

        // --- 1) Codable 往復（.iso8601）---
        // WidgetSnapshotStore が read/write で使う .iso8601 戦略と一致必須。
        // これがズレるとアプリの書き込みをウィジェットが読めず、機能全体が無言で壊れる。
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        let data = try! enc.encode(snap)
        let back = try! dec.decode(WidgetSnapshot.self, from: data)
        assert(back.upcoming.count == 2, "往復: upcoming 2件")
        assert(back.upcoming[0].title == "朝会" && back.upcoming[0].isTimePinned, "往復: カード内容保持")
        assert(back.upcoming[0].colorHex == "#FF0000", "往復: colorHex 保持")
        assert(back.upcoming[1].colorHex == nil, "往復: nil colorHex 保持")
        assert(back.bands.first?.startMinutes == 540, "往復: band 保持")
        assert(back.achievementCount == 3 && back.unconfirmedCount == 2, "往復: カウント保持")
        assert(abs(back.upcoming[0].start.timeIntervalSince(t(60))) < 1.0, "往復: 日時が秒精度で保持")

        // --- 2) currentCard(at:) — 時間経過で次カードへ自動前進 ---
        assert(snap.currentCard(at: t(0))?.title  == "朝会",   "開始前は最初のカード")
        assert(snap.currentCard(at: t(75))?.title == "朝会",   "実行中カードは end まで現在")
        assert(snap.currentCard(at: t(90))?.title == "ランチ", "終了時刻ちょうど以降は次のカード")
        assert(snap.currentCard(at: t(999)) == nil,            "全カード終了後は nil")

        // --- 3) timelineBoundaries(after:cap:) ---
        assert(snap.timelineBoundaries(after: t(0)) == [t(60), t(90), t(240), t(300)],
               "境界=各カードの開始/終了、昇順")
        assert(snap.timelineBoundaries(after: t(100)) == [t(240), t(300)],
               "now より後の境界のみ")

        // 重複除去（隣接カードの end==次の start）
        let dup = WidgetSnapshot(generatedAt: t(0), upcoming: [
            .init(title: "A", start: t(60),  end: t(120), colorHex: nil, isTimePinned: false),
            .init(title: "B", start: t(120), end: t(180), colorHex: nil, isTimePinned: false)
        ], bands: [], achievementCount: 0, unconfirmedCount: 0)
        assert(dup.timelineBoundaries(after: t(0)) == [t(60), t(120), t(180)], "境界の重複除去")

        // cap（近い境界優先で先頭 N 件）
        let many = WidgetSnapshot(generatedAt: t(0), upcoming: (0..<20).map {
            .init(title: "\($0)", start: t(10 + $0 * 10), end: t(15 + $0 * 10), colorHex: nil, isTimePinned: false)
        }, bands: [], achievementCount: 0, unconfirmedCount: 0)
        assert(many.timelineBoundaries(after: t(0), cap: 10).count == 10, "cap=10 で先頭10件")
        assert(many.timelineBoundaries(after: t(0), cap: 3) == [t(10), t(15), t(20)], "cap は近い境界優先")
        // 20カード=40境界。デフォルト cap(48) はこれを切り捨てない（旧 cap=10 からの引き上げを固定）。
        assert(many.timelineBoundaries(after: t(0)).count == 40, "デフォルト cap(48) は40境界を全て残す")

        // --- 4) App Group 未設定環境でも Store が落ちない（swiftc 単体実行＝コンテナ nil）---
        WidgetSnapshotStore.write(snap)              // no-op で例外なし
        _ = WidgetSnapshotStore.read()               // nil で例外なし

        print("P11 self-check: ALL PASS")
    }
}
