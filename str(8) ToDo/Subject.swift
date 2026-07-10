//
//  Subject.swift
//  str8ToDo
//
//  科目（学習対象）。フォーカスセッションに紐付けて集中時間を追跡する。
//

import Foundation
import SwiftData

@Model
final class Subject {
    @Attribute(.unique) var id: UUID
    var name: String
    var colorHex: String
    /// 日次の学習目標（分）
    var dailyGoalMinutes: Int
    /// 週次の学習目標（分）
    var weeklyGoalMinutes: Int
    /// ポモドーロのデフォルト実行時間（分）
    var pomodoroMinutes: Int

    init(
        id: UUID = UUID(),
        name: String,
        colorHex: String,
        dailyGoalMinutes: Int = 60,
        weeklyGoalMinutes: Int = 300,
        pomodoroMinutes: Int = 25
    ) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
        self.dailyGoalMinutes = dailyGoalMinutes
        self.weeklyGoalMinutes = weeklyGoalMinutes
        self.pomodoroMinutes = pomodoroMinutes
    }
}

// MARK: - 学習統計ヘルパー

enum StudyStats {
    /// セッションの集中秒数。end<start（時計変更等）の負値と巨大値を 0〜24h にクランプ。
    /// FocusSession.record の actualDuration クランプと同じ防御を集計側にも効かせる。
    private static func clampedSeconds(_ session: FocusSession) -> Int {
        let duration = session.end.timeIntervalSince(session.start)
        return Int(max(0, min(duration, 24 * 3600)))
    }

    /// 日ごとの集中時間（秒）。キー = その日の startOfDay、値 = Σ秒
    /// ponytail: 0秒セッション（end<start 等）は日のキーを作らない。幽霊キー排除で streak/hasSession/byDay が一貫。
    static func focusSecondsByDay(
        _ sessions: [FocusSession],
        calendar: Calendar = .current
    ) -> [Date: Int] {
        var result: [Date: Int] = [:]
        for session in sessions {
            let clampedSec = clampedSeconds(session)
            guard clampedSec > 0 else { continue }  // 0秒は活動日ではない
            let dayStart = calendar.startOfDay(for: session.end)
            result[dayStart, default: 0] += clampedSec
        }
        return result
    }

    /// 指定区間内の集中時間合計（秒）。session.end が interval に含まれるセッションを対象。
    static func totalFocusSeconds(_ sessions: [FocusSession], in interval: DateInterval) -> Int {
        sessions
            .filter { interval.contains($0.end) }
            .reduce(0) { $0 + clampedSeconds($1) }
    }

    /// 科目ごとの集中時間（秒）。キー = subject.id（nil はスキップ）、値 = Σ秒
    static func focusSecondsBySubject(_ sessions: [FocusSession]) -> [UUID: Int] {
        var result: [UUID: Int] = [:]
        for session in sessions {
            guard let subjectID = session.subjectID else { continue }
            result[subjectID, default: 0] += clampedSeconds(session)
        }
        return result
    }

    /// その日（startOfDay 一致）にセッション記録があるか。0秒のセッションは非活動日として除外。
    static func hasSession(
        on day: Date,
        _ sessions: [FocusSession],
        calendar: Calendar = .current
    ) -> Bool {
        let dayStart = calendar.startOfDay(for: day)
        return sessions.contains {
            calendar.startOfDay(for: $0.end) == dayStart && clampedSeconds($0) > 0
        }
    }

    /// 指定科目の、interval 内の集中時間合計（秒）。session.end が interval に含まれ、subjectID が一致するセッションのみ対象。
    static func focusSeconds(
        forSubject subjectID: UUID,
        in interval: DateInterval,
        _ sessions: [FocusSession]
    ) -> Int {
        sessions
            .filter { $0.subjectID == subjectID && interval.contains($0.end) }
            .reduce(0) { $0 + clampedSeconds($1) }
    }

    /// グローバルストリーク（連続日数）。最終セッション日が today か前日であれば活動中。
    /// today から遡って連続して「その日にセッションがある」日数を数える。gap で切れる。
    static func currentStreakDays(
        _ sessions: [FocusSession],
        asOf today: Date,
        calendar: Calendar = .current
    ) -> Int {
        guard !sessions.isEmpty else { return 0 }

        let sessionsByDay = focusSecondsByDay(sessions, calendar: calendar)
        guard let mostRecentDay = sessionsByDay.keys.max() else { return 0 }

        let todayStart = calendar.startOfDay(for: today)
        let yesterdayStart = calendar.date(byAdding: .day, value: -1, to: todayStart) ?? todayStart

        // Stale check: most recent session must be from today or yesterday
        guard mostRecentDay >= yesterdayStart else { return 0 }

        // Count consecutive days backwards from most recent day
        var streak = 0
        var currentDay = mostRecentDay

        while sessionsByDay[currentDay] != nil {
            streak += 1
            currentDay = calendar.date(byAdding: .day, value: -1, to: currentDay) ?? currentDay
        }

        return streak
    }
}
