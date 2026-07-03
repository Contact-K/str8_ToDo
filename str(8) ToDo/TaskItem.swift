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
    @Relationship(deleteRule: .nullify)
    var place: PlaceTag?

    /// 仕分けフェーズ（今すぐ／今日／今週／いつか）。
    var phase: SortPhase

    // MARK: - 承認プロトコル

    /// 承認ステータス（未完了／ペンディング／承認済み）。
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

    init(
        id: UUID = UUID(),
        title: String,
        category: Category? = nil,
        startDate: Date? = nil,
        duration: TimeInterval = 0,
        isAllDay: Bool = false,
        place: PlaceTag? = nil,
        phase: SortPhase = .someday,
        status: TaskStatus = .incomplete,
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
        timeZoneIdentifier: String? = nil
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
    }
}

// MARK: - 派生プロパティ / 承認フロー

extension TaskItem {

    /// チェックを付けられる最終状態か。
    var isDone: Bool { status == .approved }

    /// 終了予定時刻（開始＋所要）。
    var endDate: Date? {
        guard let startDate else { return nil }
        return startDate.addingTimeInterval(duration)
    }

    /// ソロモードで現在ロック中か（未来の自分待ち）。
    var isAwaitingFutureSelf: Bool {
        guard status == .pending, let unlockDate else { return false }
        return Date.now < unlockDate
    }

    /// 完了操作：未完了 → ペンディング。
    /// ソロモードでは unlockDate（翌日0:00）をセットし「未来の自分」に承認を託す。
    func markPending(soloUnlockDate: Date?) {
        guard status == .incomplete else { return }
        status = .pending
        completedAt = .now
        unlockDate = soloUnlockDate
    }

    /// 承認確定：ペンディング → 承認済み。ロック中は拒否する。
    /// - Returns: 承認できたら true。
    @discardableResult
    func approve(by approverID: String) -> Bool {
        guard status == .pending else { return false }
        if isAwaitingFutureSelf { return false }   // 未来の自分待ち：その場では承認不可
        status = .approved
        approvedAt = .now
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
}
