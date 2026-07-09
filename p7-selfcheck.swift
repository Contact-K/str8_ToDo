//
//  p7-selfcheck.swift — Phase 7 の自己チェック（日の出日の入り + 出発逆算ゲート + DayRow マージ）
//
//  実行方法（macOS、リポジトリルートで）:
//    cd "/Users/konnotakuto/Swift_PRJS/str(8)_ToDo/str(8) ToDo" && \
//    DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swiftc -parse-as-library \
//      "str(8) ToDo/Enums.swift" "str(8) ToDo/TaskItem.swift" \
//      "str(8) ToDo/SupportingModels.swift" "str(8) ToDo/BandModels.swift" \
//      "str(8) ToDo/Color+Hex.swift" "str(8) ToDo/DayRowBuilder.swift" \
//      "str(8) ToDo/SunCalc.swift" "str(8) ToDo/DepartureService.swift" \
//      "str(8) ToDo/AppSettings.swift" \
//      p7-selfcheck.swift -o /tmp/p7check && /tmp/p7check
//
//  アプリターゲットには含めない（pbxproj 未登録）。
//

import Foundation

// MARK: - 共通ヘルパー

/// Asia/Tokyo 固定の Calendar。
func tokyoCalendar() -> Calendar {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "Asia/Tokyo")!
    return cal
}

/// JST の年月日から startOfDay を作る。
func jstDay(_ year: Int, _ month: Int, _ day: Int, calendar: Calendar) -> Date {
    calendar.date(from: DateComponents(year: year, month: month, day: day))!
}

/// JST の "HH:mm" 文字列（比較用）。
func jstHHmm(_ date: Date, calendar: Calendar) -> (hour: Int, minute: Int) {
    (calendar.component(.hour, from: date), calendar.component(.minute, from: date))
}

/// 期待時刻との誤差（分）。
func minuteDiff(_ date: Date, expectedHour: Int, expectedMinute: Int, calendar: Calendar) -> Int {
    let (h, m) = jstHHmm(date, calendar: calendar)
    return abs((h * 60 + m) - (expectedHour * 60 + expectedMinute))
}

// MARK: - Test 1: SunCalc 参照値（東京 ±1分、JST）

func testSunCalc() {
    let cal = tokyoCalendar()
    let tokyoLat = 35.6762
    let tokyoLon = 139.6503

    // 2026-01-01: 日の出 06:51 / 日の入り 16:39
    let jan1 = jstDay(2026, 1, 1, calendar: cal)
    guard let winter = SunCalc.sunTimes(on: jan1, latitude: tokyoLat, longitude: tokyoLon, calendar: cal) else {
        assertionFailure("東京 2026-01-01: 日の出/日の入りが計算できるべき")
        return
    }
    assert(minuteDiff(winter.sunrise, expectedHour: 6, expectedMinute: 51, calendar: cal) <= 1,
           "東京 2026-01-01 日の出 期待06:51 実際\(jstHHmm(winter.sunrise, calendar: cal))")
    assert(minuteDiff(winter.sunset, expectedHour: 16, expectedMinute: 39, calendar: cal) <= 1,
           "東京 2026-01-01 日の入り 期待16:39 実際\(jstHHmm(winter.sunset, calendar: cal))")

    // 2026-07-01: 日の出 04:29 / 日の入り 19:01
    let jul1 = jstDay(2026, 7, 1, calendar: cal)
    guard let summer = SunCalc.sunTimes(on: jul1, latitude: tokyoLat, longitude: tokyoLon, calendar: cal) else {
        assertionFailure("東京 2026-07-01: 日の出/日の入りが計算できるべき")
        return
    }
    assert(minuteDiff(summer.sunrise, expectedHour: 4, expectedMinute: 29, calendar: cal) <= 1,
           "東京 2026-07-01 日の出 期待04:29 実際\(jstHHmm(summer.sunrise, calendar: cal))")
    assert(minuteDiff(summer.sunset, expectedHour: 19, expectedMinute: 1, calendar: cal) <= 1,
           "東京 2026-07-01 日の入り 期待19:01 実際\(jstHHmm(summer.sunset, calendar: cal))")

    print("testSunCalc: passed（東京2日付 ±1分）")
}

// MARK: - Test 2: 白夜（トロムソ 2026-06-21）は nil

func testMidnightSun() {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "Europe/Oslo")!
    let solstice = cal.date(from: DateComponents(year: 2026, month: 6, day: 21))!

    let result = SunCalc.sunTimes(on: solstice, latitude: 69.65, longitude: 18.96, calendar: cal)
    assert(result == nil, "トロムソ 2026-06-21（白夜）: nil を返すべき（実際: \(String(describing: result))）")

    print("testMidnightSun: passed（白夜 nil）")
}

// MARK: - Test 3: DepartureGate.shouldRequestRoute（ルート要求の唯一の判定点）

func testDepartureGate() {
    let now = Date()
    let in12h = now.addingTimeInterval(12 * 3600)

    assert(DepartureGate.shouldRequestRoute(start: in12h, hasCoordinates: true, isTimePinned: true, now: now),
           "12h先+座標+時刻固定: true")
    assert(!DepartureGate.shouldRequestRoute(start: now.addingTimeInterval(25 * 3600),
                                             hasCoordinates: true, isTimePinned: true, now: now),
           "25h先: false")
    assert(!DepartureGate.shouldRequestRoute(start: now.addingTimeInterval(-3600),
                                             hasCoordinates: true, isTimePinned: true, now: now),
           "過去: false")
    assert(!DepartureGate.shouldRequestRoute(start: in12h, hasCoordinates: false, isTimePinned: true, now: now),
           "座標なし: false")
    assert(!DepartureGate.shouldRequestRoute(start: in12h, hasCoordinates: true, isTimePinned: false, now: now),
           "isTimePinned=false: false")
    assert(!DepartureGate.shouldRequestRoute(start: nil, hasCoordinates: true, isTimePinned: true, now: now),
           "start=nil: false")

    print("testDepartureGate: passed（ゲート条件6件）")
}

// MARK: - Test 4: DayRowBuilder（sun/travel 行の位置・順序、既定値の互換性）

func testDayRowBuilder() {
    let cal = tokyoCalendar()
    let day = jstDay(2026, 7, 1, calendar: cal)

    // 10:00 開始・1h のタスク（時刻固定・移動対象）
    let task = TaskItem(title: "会議", startDate: day.addingTimeInterval(10 * 3600),
                        duration: 3600, isTimePinned: true)

    let sunTimes = (sunrise: day.addingTimeInterval(4 * 3600 + 29 * 60),   // 04:29
                    sunset: day.addingTimeInterval(19 * 3600 + 1 * 60))    // 19:01
    let departure = day.addingTimeInterval(9 * 3600 + 30 * 60)             // 09:30（ETA 30分）
    let travel: [(task: TaskItem, departure: Date, eta: TimeInterval)] = [(task, departure, 1800)]

    let rows = DayRowBuilder.buildRows(
        day: day, allDayTasks: [], timedTasks: [task], bands: [],
        now: nil, calendar: cal, sunTimes: sunTimes, travel: travel
    )

    // 期待順序: sunrise(04:29) → travel(09:30) → task(10:00) → sunset(19:01)
    let ids = rows.map(\.id)
    assert(rows.count == 4, "行数 4（sunrise/travel/task/sunset）実際 \(rows.count)")

    guard case .sun(let isSunrise0, _) = rows[0], isSunrise0 else {
        assertionFailure("行0 は sunrise（実際: \(ids[0])）"); return
    }
    guard case .travel(let tTask, let tDep, let tEta) = rows[1] else {
        assertionFailure("行1 は travel（実際: \(ids[1])）"); return
    }
    assert(tTask.id == task.id && tDep == departure && tEta == 1800, "travel の中身が一致")
    guard case .task(let rowTask) = rows[2], rowTask.id == task.id else {
        assertionFailure("行2 は task（travel の直後）（実際: \(ids[2])）"); return
    }
    guard case .sun(let isSunrise3, _) = rows[3], !isSunrise3 else {
        assertionFailure("行3 は sunset（実際: \(ids[3])）"); return
    }

    // 既定値呼び出し（sunTimes/travel 省略）は従来と同じ行列を返す
    let legacy = DayRowBuilder.buildRows(
        day: day, allDayTasks: [], timedTasks: [task], bands: [], now: nil, calendar: cal
    )
    assert(legacy.count == 1, "既定値呼び出し: task のみ1行（実際 \(legacy.count)）")
    guard case .task(let legacyTask) = legacy[0], legacyTask.id == task.id else {
        assertionFailure("既定値呼び出し: 行0 は task"); return
    }

    print("testDayRowBuilder: passed（sun/travel 位置・既定値互換）")
}

// MARK: - Test 5: travelRefreshKey（5分粒度の再計算トリガー）

func testTravelRefreshKey() {
    let cal = tokyoCalendar()
    let date = jstDay(2026, 7, 1, calendar: cal)
    // 5分バケット境界に依存しないよう、バケット先頭の時刻を基準にする
    let bucketStart = Date(timeIntervalSinceReferenceDate:
        (Date().timeIntervalSinceReferenceDate / 300).rounded(.down) * 300)

    let key0 = DayRowBuilder.travelRefreshKey(date: date, now: bucketStart, calendar: cal)
    assert(key0 == DayRowBuilder.travelRefreshKey(date: date, now: bucketStart, calendar: cal),
           "同一時刻: 同キー")
    assert(key0 == DayRowBuilder.travelRefreshKey(date: date, now: bucketStart.addingTimeInterval(299), calendar: cal),
           "4分59秒後: キー不変")
    assert(key0 != DayRowBuilder.travelRefreshKey(date: date, now: bucketStart.addingTimeInterval(300), calendar: cal),
           "5分後: キー変化")
    let nextDay = jstDay(2026, 7, 2, calendar: cal)
    assert(key0 != DayRowBuilder.travelRefreshKey(date: nextDay, now: bucketStart, calendar: cal),
           "date 変更: キー変化")

    print("testTravelRefreshKey: passed（5分粒度トリガー）")
}

// MARK: - Test 6: cacheTTL（出発直前は鮮度優先）

@MainActor
func testCacheTTL() {
    let now = Date()
    assert(DepartureService.cacheTTL(start: now.addingTimeInterval(3599), now: now) == 300,
           "59分59秒先: TTL 5分")
    assert(DepartureService.cacheTTL(start: now.addingTimeInterval(3601), now: now) == 1800,
           "1時間1秒先: TTL 30分")
    // 過去でもクラッシュしない（1時間以内扱いで 5分）
    assert(DepartureService.cacheTTL(start: now.addingTimeInterval(-3600), now: now) == 300,
           "過去: クラッシュせず TTL 5分")

    print("testCacheTTL: passed（TTL 境界）")
}

// MARK: - Main

@main
@MainActor
struct P7SelfCheck {
    static func main() {
        testSunCalc()
        testMidnightSun()
        testDepartureGate()
        testDayRowBuilder()
        testTravelRefreshKey()
        testCacheTTL()

        print("p7-selfcheck: all passed")
    }
}
