//
//  TaskItem.swift
//  str8ToDo
//
//  タスクの中心モデル。カレンダー上の日時固定タスクと、
//  リスト上の浮遊タスク（日付なし）の両方を表現する。
//

import Foundation
import SwiftData
import SwiftUI

@Model
final class TaskItem {
    /// 安定した一意 ID（EventKit ミラーの突合にも使用）。
    @Attribute(.unique) var id: UUID

    var title: String

    /// カテゴリ（任意）。削除時はタスクは残し、関連だけ外す。
    @Relationship(deleteRule: .nullify, inverse: \Category.tasks)
    var category: Category?

    // MARK: - スケジュール

    /// 開始日時。リスト上の浮遊タスク（日付未定）では nil。
    var startDate: Date?

    /// 所要時間（秒）。終日なら無視。
    var duration: TimeInterval

    var isAllDay: Bool

    /// 場所タグ（任意）。
    @Relationship(deleteRule: .nullify, inverse: \PlaceTag.tasks)
    var place: PlaceTag?

    /// 仕分けフェーズ（今すぐ／今日／今週／いつか）。
    var phase: SortPhase

    // MARK: - 承認プロトコル

    /// 承認ステータス（active／done＝自己チェック済み／approved＝確定）。
    var status: TaskStatus

    /// 完了操作をした日時（＝ペンディングに入った時刻）。
    var completedAt: Date?

    /// 承認が確定した日時。
    var approvedAt: Date?

    /// ソロモードのロック解除時刻（＝「未来の自分」に承認を託す時刻、翌日0:00など）。
    var unlockDate: Date?

    /// 承認した相手の識別子。ソロモードでは "self-future" などを入れる想定。
    var approverID: String?

    // MARK: - 繰り返し / 外部連携

    /// RFC5545 RRULE 文字列（例: "FREQ=WEEKLY;BYDAY=MO,WE,FR"）。単発なら nil。
    var rrule: String?

    /// EventKit 由来のイベント識別子。アプリ内で作ったタスクは nil。
    var eventKitID: String?

    /// EventKit ミラーかどうか（読み取り専用扱いにするため）。
    var isFromEventKit: Bool

    var createdAt: Date

    // MARK: - 拡張フィールド

    /// メモ/概要。
    var notes: String = ""

    /// スター（重要）。
    var isImportant: Bool = false

    /// イベント個別の色上書き（nil=カテゴリ色）。
    var colorHex: String? = nil

    /// 開始の何分前に通知するか（複数可。空=通知なし）。
    var notificationOffsets: [Int] = []

    /// イベントのタイムゾーン識別子。
    var timeZoneIdentifier: String? = nil

    /// 金額（支出・サブスクイベント用、P8 で UI 接続）。
    var amount: Decimal? = nil

    /// 支払方法タグ（クレカ名など）。
    var paymentMethod: String? = nil

    /// 実所要時間（秒）。タイマー完了時に記録（P4〜）。空きコマ提案（W2）の学習データ。
    var actualDuration: TimeInterval? = nil

    /// 時刻厳守（開始時刻が動かせない予定）。
    var isTimePinned: Bool = false

    /// リストの並び順。
    var sortIndex: Int = 0

    /// 仕分け済みスタンプ（その日の startOfDay）。デッキの再開判定に使う。
    var lastSortedDay: Date? = nil

    /// 先送り期限。この日時まではデッキに出さない。
    var snoozeUntil: Date? = nil

    /// 紐付き科目（勉強タスク）。任意。
    var subjectID: UUID? = nil

    init(
        id: UUID = UUID(),
        title: String,
        category: Category? = nil,
        startDate: Date? = nil,
        duration: TimeInterval = 0,
        isAllDay: Bool = false,
        place: PlaceTag? = nil,
        phase: SortPhase = .someday,
        status: TaskStatus = .active,
        completedAt: Date? = nil,
        approvedAt: Date? = nil,
        unlockDate: Date? = nil,
        approverID: String? = nil,
        rrule: String? = nil,
        eventKitID: String? = nil,
        isFromEventKit: Bool = false,
        createdAt: Date = .now,
        notes: String = "",
        isImportant: Bool = false,
        colorHex: String? = nil,
        notificationOffsets: [Int] = [],
        timeZoneIdentifier: String? = nil,
        amount: Decimal? = nil,
        paymentMethod: String? = nil,
        actualDuration: TimeInterval? = nil,
        isTimePinned: Bool = false,
        sortIndex: Int = 0,
        lastSortedDay: Date? = nil,
        snoozeUntil: Date? = nil,
        subjectID: UUID? = nil
    ) {
        self.id = id
        self.title = title
        self.category = category
        self.startDate = startDate
        self.duration = duration
        self.isAllDay = isAllDay
        self.place = place
        self.phase = phase
        self.status = status
        self.completedAt = completedAt
        self.approvedAt = approvedAt
        self.unlockDate = unlockDate
        self.approverID = approverID
        self.rrule = rrule
        self.eventKitID = eventKitID
        self.isFromEventKit = isFromEventKit
        self.createdAt = createdAt
        self.notes = notes
        self.isImportant = isImportant
        self.colorHex = colorHex
        self.notificationOffsets = notificationOffsets
        self.timeZoneIdentifier = timeZoneIdentifier
        self.amount = amount
        self.paymentMethod = paymentMethod
        self.actualDuration = actualDuration
        self.isTimePinned = isTimePinned
        self.sortIndex = sortIndex
        self.lastSortedDay = lastSortedDay
        self.snoozeUntil = snoozeUntil
        self.subjectID = subjectID
    }
}

// MARK: - 派生プロパティ / 承認フロー

extension TaskItem {

    /// 自己チェック済みか（done / approved）。打ち消し線などUI上の「完了」条件。
    var isDone: Bool { status != .active }

    /// 終了予定時刻（開始＋所要）。
    var endDate: Date? {
        guard let startDate else { return nil }
        return startDate.addingTimeInterval(duration)
    }

    /// ソロモードで現在ロック中か（未来の自分待ち）。
    var isAwaitingFutureSelf: Bool {
        guard status == .done, let unlockDate else { return false }
        return Date.now < unlockDate
    }

    /// 自己チェック：active → done。UI上は即「完了」。
    /// unlockDate=翌日0:00 をセットし、確定（approved）は「未来の自分」に託す。
    func markDone() {
        guard status == .active else { return }
        status = .done
        completedAt = .now
        unlockDate = TaskItem.nextMidnight()
    }

    /// 承認確定：done → approved。全承認経路（ソロ・ペア・リスト・週報）はここを通す。
    /// ステータス遷移と同時に承認日の DayStat を upsert する（再承認は no-op＝二重カウントなし）。
    /// ペア承認（他人承認）は翌日ロックをバイパスして即確定（オーナー決定#8）。
    /// - Parameters:
    ///   - approverID: 承認した相手の識別子。
    ///   - context: ModelContext。
    ///   - bypassesLock: true のときだけ `isAwaitingFutureSelf` チェックをスキップ。
    /// - Returns: 承認できたら true。
    @discardableResult
    func approve(by approverID: String, context: ModelContext, bypassesLock: Bool = false) -> Bool {
        guard status == .done else { return false }   // 再承認・未完了は no-op
        if !bypassesLock && isAwaitingFutureSelf { return false }      // 未来の自分待ち：その場では承認不可

        // ponytail: Calendar.current 固定。TZ を跨ぐ移動で日キーが割れる天井（対応するなら固定カレンダー注入）
        let day = Calendar.current.startOfDay(for: .now)
        let descriptor = FetchDescriptor<DayStat>(predicate: #Predicate { $0.day == day })
        do {
            if let stat = try context.fetch(descriptor).first {
                stat.completedCount += 1
            } else {
                context.insert(DayStat(day: day, completedCount: 1))
            }
        } catch {
            // fetch 失敗時は状態変更をせず false を返す（「承認済みなのに未集計」状態を防ぐ）。
            // DayStat は再構築可能なキャッシュなので、その回の集計だけスキップする（P9 で rebuild を用意）。
            assertionFailure("DayStat fetch failed: \(error)")
            return false
        }

        status = .approved
        let now = Date.now
        approvedAt = now
        self.approverID = approverID
        return true
    }

    /// 翌日0:00（ソロモードの既定ロック解除時刻）。
    static func nextMidnight(after date: Date = .now, calendar: Calendar = .current) -> Date {
        let start = calendar.startOfDay(for: date)
        return calendar.date(byAdding: .day, value: 1, to: start) ?? date
    }

    /// 表示色：個別色 colorHex が優先、無ければカテゴリ色、どちらも無ければ accentColor。
    var effectiveColor: Color {
        if let hex = colorHex { return Color(hex: hex) }
        if let catHex = category?.colorHex { return Color(hex: catHex) }
        return .accentColor
    }

    /// 最小 RRULE 展開：その日 day に出現するか。startDate 当日は常に true。
    /// rrule ありなら startDate 翌日以降も周期一致で true（開始日より前は false）。
    // ponytail: AddTaskSheet が書く4パターンのみ対応。INTERVAL/UNTIL 等は未対応
    func occurs(on day: Date, calendar: Calendar = .current) -> Bool {
        guard let startDate else { return false }
        if calendar.isDate(startDate, inSameDayAs: day) { return true }
        guard let rrule else { return false }
        guard calendar.startOfDay(for: day) > calendar.startOfDay(for: startDate) else { return false }

        if rrule == "FREQ=DAILY" { return true }
        if rrule.hasPrefix("FREQ=WEEKLY;BYDAY=") {
            let codes = ["SU", "MO", "TU", "WE", "TH", "FR", "SA"]
            let byday = rrule.dropFirst("FREQ=WEEKLY;BYDAY=".count).split(separator: ",").map(String.init)
            return byday.contains(codes[calendar.component(.weekday, from: day) - 1])
        }
        if rrule == "FREQ=WEEKLY" {
            return calendar.component(.weekday, from: day) == calendar.component(.weekday, from: startDate)
        }
        if rrule == "FREQ=MONTHLY" {
            // 月末クランプ: 開始日の day がその月の日数を超える場合は月末日に発生（例: 31日開始→2月は28/29日）
            let startDay = calendar.component(.day, from: startDate)
            let daysInMonth = calendar.range(of: .day, in: .month, for: day)?.count ?? 31
            return calendar.component(.day, from: day) == min(startDay, daysInMonth)
        }
        return false
    }

    /// 浮遊タスクを指定時刻・所要でカレンダーへ昇格（採用）。仕分けの持ち越し状態はクリア。status は変えない（勝手に確定しない）。
    func scheduleAt(start: Date, duration: TimeInterval, context: ModelContext) {
        startDate = start
        self.duration = duration
        snoozeUntil = nil
        lastSortedDay = nil
        do {
            try context.save()
            NotificationService.reschedule(for: self)
        } catch {
            assertionFailure("Failed to schedule task: \(error)")
        }
    }
}
