//
//  EventKitService.swift
//  str8ToDo
//
//  EventKit の「読み取り専用ミラー」。
//  オフライン主義のため書き戻し・双方向同期はしない。
//  端末カレンダーのイベントを TaskItem(isFromEventKit: true) として occurrence 単位でミラーし、
//  複合キー "eventIdentifier#開始秒"（eventKitID に保存）で upsert する
//  （繰り返しイベントは同一 eventIdentifier で複数 occurrence が返るため）。
//

import Foundation
import EventKit
import SwiftData
import Observation

@MainActor
@Observable
final class EventKitService {

    enum AuthState {
        case unknown, denied, authorized
    }

    private let store = EKEventStore()
    private(set) var authState: AuthState = .unknown
    @ObservationIgnored
    nonisolated(unsafe) private var changeObserver: NSObjectProtocol?
    /// 外部変更時の再同期先。observeChanges の呼び出し元と常に同一の ModelContext
    /// （呼び出し側は毎回 modelContext を渡している）。closure に直接 ModelContext を
    /// capture すると非 Sendable 型の capture 警告になるため、MainActor 上のプロパティ経由にする。
    private var syncContext: ModelContext?

    /// 取り込み対象の期間（前後）。
    private let pastDays = 7
    private let futureDays = 60

    var eventCalendars: [EKCalendar] {
        store.calendars(for: .event)
    }

    init() {
        refreshAuthState()
    }

    deinit {
        if let changeObserver {
            NotificationCenter.default.removeObserver(changeObserver)
        }
    }

    // MARK: - 権限

    private func refreshAuthState() {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess:
            authState = .authorized
        case .denied, .restricted, .writeOnly:
            authState = .denied
        default:
            authState = .unknown
        }
    }

    /// フルアクセスを要求する。許可されたら true。
    @discardableResult
    func requestAccess() async -> Bool {
        do {
            let granted = try await store.requestFullAccessToEvents()
            authState = granted ? .authorized : .denied
            return granted
        } catch {
            authState = .denied
            return false
        }
    }

    // MARK: - 同期

    /// 端末カレンダーを読み取り、SwiftData にミラーする。
    /// - Parameter context: 書き込み先の ModelContext。
    func sync(into context: ModelContext) {
        guard UserDefaults.standard.bool(forKey: AppSettingsKey.syncSystemCalendar) else { return }
        guard authState == .authorized else { return }

        let now = Date.now
        let cal = Calendar.current
        guard
            let start = cal.date(byAdding: .day, value: -pastDays, to: now),
            let end = cal.date(byAdding: .day, value: futureDays, to: now)
        else { return }

        let excluded = Set(UserDefaults.standard.stringArray(forKey: AppSettingsKey.excludedCalendarIDs) ?? [])
        let calendars = store.calendars(for: .event).filter { !excluded.contains($0.calendarIdentifier) }
        let events = calendars.isEmpty ? [] : store.events(matching: store.predicateForEvents(withStart: start, end: end, calendars: calendars))

        // 既存ミラーを複合キー（eventIdentifier#開始秒）で索引化。
        // 同一キーが複数あれば最初の1件を残して掃除（過去の増殖分の後始末）。
        let existing = (try? context.fetch(
            FetchDescriptor<TaskItem>(predicate: #Predicate { $0.isFromEventKit })
        )) ?? []
        var byKey: [String: TaskItem] = [:]
        for t in existing {
            guard let key = t.eventKitID else { continue }
            if byKey[key] != nil {
                context.delete(t)
            } else {
                byKey[key] = t
            }
        }

        var seen = Set<String>()

        for event in events {
            let eid = event.eventIdentifier ?? ""
            guard !eid.isEmpty else { continue }
            let key = "\(eid)#\(Int(event.startDate.timeIntervalSinceReferenceDate))"
            seen.insert(key)

            let duration = event.endDate.timeIntervalSince(event.startDate)

            if let task = byKey[key] {
                // upsert: 既存を更新（カレンダー由来は時刻固定扱い、終日は除く）
                task.title = event.title ?? "(無題)"
                task.startDate = event.startDate
                task.duration = max(duration, 0)
                task.isAllDay = event.isAllDay
                task.isTimePinned = !event.isAllDay
            } else {
                // 新規ミラー（カレンダー由来は時刻固定扱い、終日は除く）
                let task = TaskItem(
                    title: event.title ?? "(無題)",
                    startDate: event.startDate,
                    duration: max(duration, 0),
                    isAllDay: event.isAllDay,
                    phase: .today,
                    eventKitID: key,
                    isFromEventKit: true,
                    isTimePinned: !event.isAllDay
                )
                context.insert(task)
            }
        }

        // 端末側で消えたミラーは削除。fetch ウィンドウ内の occurrence に限定する。
        // ponytail: ウィンドウ外は判断保留（完了・承認履歴を消さない）
        for (key, task) in byKey where !seen.contains(key) {
            guard let taskStart = task.startDate, taskStart >= start, taskStart < end else { continue }
            context.delete(task)
        }

        try? context.save()
    }

    func purgeMirrors(from context: ModelContext) {
        let mirrors = (try? context.fetch(FetchDescriptor<TaskItem>(predicate: #Predicate { $0.isFromEventKit }))) ?? []
        for t in mirrors { context.delete(t) }
        try? context.save()
    }

    /// 日本の祝日を EventKit の購読カレンダーから取得。指定期間内の祝日 startOfDay を Set で返す。
    /// タイトル一致（"日本の祝日" or "Japanese Holiday" 含む）または `.birthday` 以外のシステム購読カレンダーを対象。
    /// 権限未取得なら空セット。ponytail: 名前一致は雑だが iOS 26 でも祝日カレンダーの命名は安定。
    func fetchJapaneseHolidays(in range: Range<Date>) -> Set<Date> {
        guard authState == .authorized else { return [] }
        let calendars = store.calendars(for: .event).filter { cal in
            let title = cal.title
            return title.contains("日本の休日")
                || title.contains("日本の祝日")
                || title.contains("Japanese Holiday")
                || title.contains("Holidays in Japan")
        }
        guard !calendars.isEmpty else { return [] }
        let predicate = store.predicateForEvents(withStart: range.lowerBound, end: range.upperBound, calendars: calendars)
        let events = store.events(matching: predicate)
        var result: Set<Date> = []
        let jaCal = Calendar(identifier: .gregorian)
        for ev in events {
            result.insert(jaCal.startOfDay(for: ev.startDate))
        }
        return result
    }

    /// 外部変更（.EKEventStoreChanged）を購読して自動再同期する。
    func observeChanges(into context: ModelContext) {
        guard changeObserver == nil else { return }
        syncContext = context
        changeObserver = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged,
            object: store,
            queue: .main
        ) { _ in
            Task { @MainActor [weak self] in
                guard let self, let ctx = self.syncContext else { return }
                self.sync(into: ctx)
            }
        }
    }
}
