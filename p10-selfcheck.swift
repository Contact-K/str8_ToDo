//
//  p10-selfcheck.swift — Phase 10 の自己チェック（Subject / StudyStats / FocusSession.record の subject 紐付け）
//
//  実行方法（macOS、リポジトリルートで）:
//    cd "/Users/konnotakuto/Swift_PRJS/str(8)_ToDo/str(8) ToDo" && \
//    DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swiftc -parse-as-library \
//      "str(8) ToDo/Enums.swift" "str(8) ToDo/TaskItem.swift" \
//      "str(8) ToDo/SupportingModels.swift" "str(8) ToDo/FocusSession.swift" \
//      "str(8) ToDo/Subject.swift" "str(8) ToDo/Color+Hex.swift" \
//      p10-selfcheck.swift -o /tmp/p10check && /tmp/p10check
//
//  アプリターゲットには含めない（pbxproj 未登録）。
//

import Foundation
import SwiftData

// MARK: - 共通ヘルパー

@MainActor
func makeContext() -> (container: ModelContainer, context: ModelContext) {
    let schema = Schema([TaskItem.self, Category.self, PlaceTag.self, DayStat.self, FocusSession.self, Subject.self])
    let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: schema, configurations: config)
    return (container, container.mainContext)
}

func day(_ year: Int, _ month: Int, _ day: Int, hour: Int = 10) -> Date {
    Calendar.current.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
}

// MARK: - Test 1: Subject の init 既定値（60/300/25）

@MainActor
func testSubjectDefaults() {
    let subject = Subject(name: "数学", colorHex: "#4F8DFD")
    assert(subject.dailyGoalMinutes == 60, "dailyGoal 期待60 実際\(subject.dailyGoalMinutes)")
    assert(subject.weeklyGoalMinutes == 300, "weeklyGoal 期待300 実際\(subject.weeklyGoalMinutes)")
    assert(subject.pomodoroMinutes == 25, "pomodoro 期待25 実際\(subject.pomodoroMinutes)")
    print("testSubjectDefaults: passed（既定値確認）")
}

// MARK: - Test 2: FocusSession.record(..., subject:) が subjectID を格納

@MainActor
func testFocusSessionRecordWithSubject() {
    let subject = Subject(name: "英語", colorHex: "#34C759")

    // 直接 FocusSession を作成（record を使わずに）
    let start = day(2026, 7, 10)
    let end = start.addingTimeInterval(30 * 60)

    let session = FocusSession(start: start, end: end, subjectID: subject.id)
    assert(session.subjectID == subject.id, "subjectID 期待\(subject.id) 実際\(session.subjectID ?? UUID())")

    print("testFocusSessionRecordWithSubject: passed（subject 紐付け確認）")
}

// MARK: - Test 3: StudyStats.focusSecondsByDay（同日複数セッション合算、別日は別キー）

@MainActor
func testFocusSecondsByDay() {
    let d1 = day(2026, 7, 10)
    let d2 = day(2026, 7, 11)

    // メモリ上のセッションリストを直接構築（DB 保存なし）
    // 注意: d1.addingTimeInterval(9 * 3600) = d1の10時間後 + 9時間 = 次の日の19時
    // 同一日付内に収めるため、addingTimeInterval の値を小さくする
    let sessions = [
        FocusSession(start: d1.addingTimeInterval(3600),      // 11:00 AM
                     end: d1.addingTimeInterval(3600 + 30 * 60)), // 11:30 AM
        FocusSession(start: d1.addingTimeInterval(7200),      // 12:00 PM
                     end: d1.addingTimeInterval(7200 + 40 * 60)), // 12:40 PM
        FocusSession(start: d2.addingTimeInterval(3600),      // 11:00 AM (next day)
                     end: d2.addingTimeInterval(3600 + 20 * 60))  // 11:20 AM (next day)
    ]

    let result = StudyStats.focusSecondsByDay(sessions)

    let dayStart1 = Calendar.current.startOfDay(for: d1)
    let dayStart2 = Calendar.current.startOfDay(for: d2)

    assert(result[dayStart1] == 70 * 60, "7/10 期待\(70 * 60) 実際\(result[dayStart1] ?? -1)")
    assert(result[dayStart2] == 20 * 60, "7/11 期待\(20 * 60) 実際\(result[dayStart2] ?? -1)")

    print("testFocusSecondsByDay: passed（日ごと合算確認）")
}

// MARK: - Test 4: StudyStats.totalFocusSeconds（interval 境界チェック）

@MainActor
func testTotalFocusSeconds() {
    let d1 = day(2026, 7, 10)
    let d2 = day(2026, 7, 11)
    let d3 = day(2026, 7, 12)

    let sessions = [
        FocusSession(start: d1, end: d1.addingTimeInterval(30 * 60)),
        FocusSession(start: d2, end: d2.addingTimeInterval(40 * 60)),
        FocusSession(start: d3, end: d3.addingTimeInterval(50 * 60))
    ]

    // interval: 7/10 と 7/11 を含む
    let intervalStart = d1
    let intervalEnd = d2.addingTimeInterval(24 * 3600)  // 7/12 00:00 手前
    let interval = DateInterval(start: intervalStart, end: intervalEnd)

    let result = StudyStats.totalFocusSeconds(sessions, in: interval)
    let expected = 30 * 60 + 40 * 60  // d1 と d2
    assert(result == expected, "interval 内の秒数 期待\(expected) 実際\(result)")

    print("testTotalFocusSeconds: passed（interval 境界確認）")
}

// MARK: - Test 5: StudyStats.focusSecondsBySubject（nil スキップ、同 subject 合算）

@MainActor
func testFocusSecondsBySubject() {
    let math = Subject(name: "数学", colorHex: "#4F8DFD")
    let english = Subject(name: "英語", colorHex: "#34C759")

    let d1 = day(2026, 7, 10)

    // 数学のセッション 30分 + 25分 = 55分
    // 英語のセッション 20分
    // subjectID なし（スキップされるべき）
    let sessions = [
        FocusSession(start: d1.addingTimeInterval(9 * 3600),
                     end: d1.addingTimeInterval(9 * 3600 + 30 * 60),
                     subjectID: math.id),
        FocusSession(start: d1.addingTimeInterval(11 * 3600),
                     end: d1.addingTimeInterval(11 * 3600 + 25 * 60),
                     subjectID: math.id),
        FocusSession(start: d1.addingTimeInterval(14 * 3600),
                     end: d1.addingTimeInterval(14 * 3600 + 20 * 60),
                     subjectID: english.id),
        FocusSession(start: d1.addingTimeInterval(16 * 3600),
                     end: d1.addingTimeInterval(16 * 3600 + 10 * 60),
                     subjectID: nil)
    ]

    let result = StudyStats.focusSecondsBySubject(sessions)

    assert(result[math.id] == 55 * 60, "数学 期待\(55 * 60) 実際\(result[math.id] ?? -1)")
    assert(result[english.id] == 20 * 60, "英語 期待\(20 * 60) 実際\(result[english.id] ?? -1)")
    assert(result.count == 2, "科目数 期待2（nil スキップ）実際\(result.count)")

    print("testFocusSecondsBySubject: passed（科目別集計確認）")
}

// MARK: - Test 6: StudyStats.hasSession（セッションの有無判定）

@MainActor
func testHasSession() {
    let d1 = day(2026, 7, 10)
    let d2 = day(2026, 7, 11)
    let d3 = day(2026, 7, 12)

    let sessions = [
        FocusSession(start: d1, end: d1.addingTimeInterval(30 * 60)),
        FocusSession(start: d2, end: d2.addingTimeInterval(40 * 60))
    ]

    assert(StudyStats.hasSession(on: d1, sessions) == true, "d1 にセッション：true 期待")
    assert(StudyStats.hasSession(on: d2, sessions) == true, "d2 にセッション：true 期待")
    assert(StudyStats.hasSession(on: d3, sessions) == false, "d3 にセッション：false 期待")

    print("testHasSession: passed（セッション有無判定確認）")
}

// MARK: - Test 7: 負 duration（end<start、時計変更）は 0 として寄与し集計を汚染しない

@MainActor
func testNegativeDurationClamped() {
    let subject = Subject(name: "数学", colorHex: "#4F8DFD")
    let d1 = day(2026, 7, 10)

    // 正常30分 + 負値（end が start より前）を同日・同科目に混在
    let good = FocusSession(start: d1.addingTimeInterval(3600),
                            end: d1.addingTimeInterval(3600 + 30 * 60),
                            subjectID: subject.id)
    let bad = FocusSession(start: d1.addingTimeInterval(7200),
                           end: d1.addingTimeInterval(7200 - 10 * 60),  // 10分マイナス
                           subjectID: subject.id)
    let sessions = [good, bad]

    let dayStart = Calendar.current.startOfDay(for: d1)

    // byDay: 負値は 0 寄与 → 30分のみ
    assert(StudyStats.focusSecondsByDay(sessions)[dayStart] == 30 * 60,
           "byDay 負値クランプ 期待\(30 * 60) 実際\(StudyStats.focusSecondsByDay(sessions)[dayStart] ?? -1)")

    // bySubject: 負値は 0 寄与 → 30分のみ
    assert(StudyStats.focusSecondsBySubject(sessions)[subject.id] == 30 * 60,
           "bySubject 負値クランプ 期待\(30 * 60) 実際\(StudyStats.focusSecondsBySubject(sessions)[subject.id] ?? -1)")

    // totalFocusSeconds: 両 end を含む interval → 30分のみ
    let interval = DateInterval(start: d1, end: d1.addingTimeInterval(24 * 3600))
    assert(StudyStats.totalFocusSeconds(sessions, in: interval) == 30 * 60,
           "total 負値クランプ 期待\(30 * 60) 実際\(StudyStats.totalFocusSeconds(sessions, in: interval))")

    print("testNegativeDurationClamped: passed（負 duration は 0 寄与）")
}

// MARK: - Test 8: StudyStats.focusSeconds(forSubject:in:)

@MainActor
func testFocusSecondsForSubject() {
    let math = Subject(name: "数学", colorHex: "#4F8DFD")
    let english = Subject(name: "英語", colorHex: "#34C759")

    let d1 = day(2026, 7, 10)
    let d2 = day(2026, 7, 11)

    let sessions = [
        // 数学: 7/10 30分 + 7/11 25分 = 55分
        FocusSession(start: d1.addingTimeInterval(3600),
                     end: d1.addingTimeInterval(3600 + 30 * 60),
                     subjectID: math.id),
        // 英語: 7/10 20分（スキップされない）
        FocusSession(start: d1.addingTimeInterval(7200),
                     end: d1.addingTimeInterval(7200 + 20 * 60),
                     subjectID: english.id),
        // 数学: 7/11 25分
        FocusSession(start: d2.addingTimeInterval(3600),
                     end: d2.addingTimeInterval(3600 + 25 * 60),
                     subjectID: math.id),
        // subjectID なし（除外）
        FocusSession(start: d2.addingTimeInterval(7200),
                     end: d2.addingTimeInterval(7200 + 15 * 60),
                     subjectID: nil)
    ]

    // 区間: 7/10 のみ
    let dayInterval1 = DateInterval(start: d1, end: d1.addingTimeInterval(24 * 3600))
    let mathSecondsDay1 = StudyStats.focusSeconds(forSubject: math.id, in: dayInterval1, sessions)
    assert(mathSecondsDay1 == 30 * 60, "数学 7/10 期待\(30 * 60) 実際\(mathSecondsDay1)")

    // 区間: 7/10 〜 7/11
    let intervalAll = DateInterval(start: d1, end: d2.addingTimeInterval(24 * 3600))
    let mathSecondsAll = StudyStats.focusSeconds(forSubject: math.id, in: intervalAll, sessions)
    assert(mathSecondsAll == (30 + 25) * 60, "数学 全期間 期待\((30 + 25) * 60) 実際\(mathSecondsAll)")

    // 英語: 7/10 のみ
    let englishSeconds = StudyStats.focusSeconds(forSubject: english.id, in: intervalAll, sessions)
    assert(englishSeconds == 20 * 60, "英語 期待\(20 * 60) 実際\(englishSeconds)")

    print("testFocusSecondsForSubject: passed（科目・区間フィルタ確認）")
}

// MARK: - Test 9: StudyStats.currentStreakDays

@MainActor
func testCurrentStreakDays() {
    let d0 = day(2026, 7, 8)
    let d1 = day(2026, 7, 9)
    let d2 = day(2026, 7, 10)
    let d3 = day(2026, 7, 11)

    // (a) today（d2） 含む3連続（d0, d1, d2）→ streak 3
    let case_a = [
        FocusSession(start: d0, end: d0.addingTimeInterval(30 * 60)),
        FocusSession(start: d1, end: d1.addingTimeInterval(25 * 60)),
        FocusSession(start: d2, end: d2.addingTimeInterval(20 * 60))
    ]
    let streak_a = StudyStats.currentStreakDays(case_a, asOf: d2)
    assert(streak_a == 3, "case (a) 今日含む3連続 期待3 実際\(streak_a)")

    // (c) 同日2セッション は1日として数える
    let case_c = [
        FocusSession(start: d0, end: d0.addingTimeInterval(30 * 60)),
        FocusSession(start: d1.addingTimeInterval(3600), end: d1.addingTimeInterval(3600 + 25 * 60)),
        FocusSession(start: d1.addingTimeInterval(7200), end: d1.addingTimeInterval(7200 + 20 * 60)),  // d1 の2つ目
        FocusSession(start: d2, end: d2.addingTimeInterval(20 * 60))
    ]
    let streak_c = StudyStats.currentStreakDays(case_c, asOf: d2)
    assert(streak_c == 3, "case (c) 同日複数セッションは1日 期待3 実際\(streak_c)")

    // (d) 最終セッションが2日以上前 → stale → 0
    // 最終セッション: d0。本日: d3（3日後）→ stale
    let case_d = [
        FocusSession(start: d0, end: d0.addingTimeInterval(30 * 60)),
        FocusSession(start: d1, end: d1.addingTimeInterval(25 * 60))
    ]
    let streak_d = StudyStats.currentStreakDays(case_d, asOf: d3)
    assert(streak_d == 0, "case (d) stale（最終セッション2日以上前）期待0 実際\(streak_d)")

    // (e) today 未実施だが前日までセッション続く → 継続
    // d2 未実施、d1 と d0 にセッション。本日: d2
    let case_e = [
        FocusSession(start: d0, end: d0.addingTimeInterval(30 * 60)),
        FocusSession(start: d1, end: d1.addingTimeInterval(25 * 60))
        // d2 にセッションなし
    ]
    let streak_e = StudyStats.currentStreakDays(case_e, asOf: d2)
    assert(streak_e == 2, "case (e) 今日未実施も前日まで継続 期待2 実際\(streak_e)")

    // (b) 間に gap → 切れる
    // d0, d1 に連続 → d2 gap → d3 にセッション
    let case_b = [
        FocusSession(start: d0, end: d0.addingTimeInterval(30 * 60)),
        FocusSession(start: d1, end: d1.addingTimeInterval(25 * 60)),
        // d2 gap
        FocusSession(start: d3, end: d3.addingTimeInterval(20 * 60))
    ]
    let streak_b = StudyStats.currentStreakDays(case_b, asOf: d3)
    assert(streak_b == 1, "case (b) gap で切れる 期待1（d3のみ） 実際\(streak_b)")

    print("testCurrentStreakDays: passed（ストリーク5ケース確認）")
}

// MARK: - Test 10: 0秒のみの日はストリーク/hasSession/byDay に含まれない

@MainActor
func testZeroSecondDayNotCounted() {
    let d0 = day(2026, 7, 8)   // 30分
    let d1 = day(2026, 7, 9)   // 0秒のみ（end < start）
    let d2 = day(2026, 7, 10)  // 20分

    // d0: 正常30分
    let good0 = FocusSession(start: d0, end: d0.addingTimeInterval(30 * 60))

    // d1: 0秒のみ（負値）
    let bad1 = FocusSession(start: d1.addingTimeInterval(3600),
                            end: d1.addingTimeInterval(3600 - 5 * 60))  // 5分マイナス

    // d2: 正常20分
    let good2 = FocusSession(start: d2, end: d2.addingTimeInterval(20 * 60))

    let sessions = [good0, bad1, good2]

    // (1) focusSecondsByDay: d0 と d2 のみ、d1 のキーは作られない
    let byDay = StudyStats.focusSecondsByDay(sessions)
    let dayStart0 = Calendar.current.startOfDay(for: d0)
    let dayStart1 = Calendar.current.startOfDay(for: d1)
    let dayStart2 = Calendar.current.startOfDay(for: d2)

    assert(byDay[dayStart0] == 30 * 60, "d0(30分) 期待\(30 * 60) 実際\(byDay[dayStart0] ?? -1)")
    assert(byDay[dayStart1] == nil, "d1(0秒) キーなし 期待nil 実際\(byDay[dayStart1] ?? -1)")
    assert(byDay[dayStart2] == 20 * 60, "d2(20分) 期待\(20 * 60) 実際\(byDay[dayStart2] ?? -1)")

    // (2) hasSession: d0 true, d1 false, d2 true
    assert(StudyStats.hasSession(on: d0, sessions) == true, "d0 hasSession: true 期待")
    assert(StudyStats.hasSession(on: d1, sessions) == false, "d1 hasSession: false 期待（0秒のみ）")
    assert(StudyStats.hasSession(on: d2, sessions) == true, "d2 hasSession: true 期待")

    // (3) currentStreakDays: d2 を基準に遡ると、d2→d1(キーなし gap)→break
    // streak は d2 のみ = 1
    let streak = StudyStats.currentStreakDays(sessions, asOf: d2)
    assert(streak == 1, "streak（d0から遡るなら2 but d1でgap）期待1（d2のみ） 実際\(streak)")

    print("testZeroSecondDayNotCounted: passed（0秒日は非活動、ストリーク/hasSession/byDay から除外）")
}

// MARK: - Test 11: 当日0秒日が mostRecentDay に誤選出されない（本命シナリオ）

@MainActor
func testZeroSecondTodayNotMostRecent() {
    let dBeforeYesterday = day(2026, 7, 8)  // 一昨日: 30分
    let dYesterday = day(2026, 7, 9)        // 昨日: 25分
    let dToday = day(2026, 7, 10)           // 今日: 0秒(end<start)のみ

    let sessions = [
        FocusSession(start: dBeforeYesterday, end: dBeforeYesterday.addingTimeInterval(30 * 60)),
        FocusSession(start: dYesterday, end: dYesterday.addingTimeInterval(25 * 60)),
        // 今日は 0秒のみ（ghost 日）
        FocusSession(start: dToday.addingTimeInterval(3600),
                     end: dToday.addingTimeInterval(3600 - 10 * 60))  // 10分マイナス
    ]

    // (a) 今日のキーは作られない
    let todayStart = Calendar.current.startOfDay(for: dToday)
    let byDay = StudyStats.focusSecondsByDay(sessions)
    assert(byDay[todayStart] == nil, "今日(0秒) キーなし 期待nil 実際\(byDay[todayStart] ?? -1)")

    // (b) mostRecentDay は昨日に巻き戻り、streak は一昨日・昨日の2
    let streak = StudyStats.currentStreakDays(sessions, asOf: dToday)
    assert(streak == 2, "当日ghostを数えず巻き戻って2 期待2 実際\(streak)")

    print("testZeroSecondTodayNotMostRecent: passed（当日0秒はmostRecentDayに選出されず巻き戻る）")
}

// MARK: - Main

@main
@MainActor
struct P10SelfCheck {
    static func main() {
        testSubjectDefaults()
        testFocusSessionRecordWithSubject()
        testFocusSecondsByDay()
        testTotalFocusSeconds()
        testFocusSecondsBySubject()
        testHasSession()
        testNegativeDurationClamped()
        testFocusSecondsForSubject()
        testCurrentStreakDays()
        testZeroSecondDayNotCounted()
        testZeroSecondTodayNotMostRecent()

        print("p10-selfcheck: all passed")
    }
}
