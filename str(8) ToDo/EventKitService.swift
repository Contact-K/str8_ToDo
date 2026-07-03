//
//  EventKitService.swift
//  str8ToDo
//
//  EventKit の「読み取り専用ミラー」。
//  オフライン主義のため書き戻し・双方向同期はしない。
//  端末カレンダーのイベントを TaskItem(isFromEventKit: true) として取り込み、
//  eventKitID で upsert する。
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
    nonisolated(unsafe) private var changeObserver: NSObjectProtocol?

    /// 取り込み対象の期間（前後）。
    private let pastDays = 7
    private let futureDays = 60

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
        guard authState == .authorized else { return }

        let now = Date.now
        let cal = Calendar.current
        guard
            let start = cal.date(byAdding: .day, value: -pastDays, to: now),
            let end = cal.date(byAdding: .day, value: futureDays, to: now)
        else { return }

        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        let events = store.events(matching: predicate)

        // 既存ミラーを eventKitID で索引化。
        let existing = (try? context.fetch(
            FetchDescriptor<TaskItem>(predicate: #Predicate { $0.isFromEventKit })
        )) ?? []
        var byID: [String: TaskItem] = [:]
        for t in existing { if let eid = t.eventKitID { byID[eid] = t } }

        var seen = Set<String>()

        for event in events {
            let eid = event.eventIdentifier ?? ""
            guard !eid.isEmpty else { continue }
            seen.insert(eid)

            let duration = event.endDate.timeIntervalSince(event.startDate)

            if let task = byID[eid] {
                // upsert: 既存を更新
                task.title = event.title ?? "(無題)"
                task.startDate = event.startDate
                task.duration = max(duration, 0)
                task.isAllDay = event.isAllDay
            } else {
                // 新規ミラー
                let task = TaskItem(
                    title: event.title ?? "(無題)",
                    startDate: event.startDate,
                    duration: max(duration, 0),
                    isAllDay: event.isAllDay,
                    phase: .today,
                    eventKitID: eid,
                    isFromEventKit: true
                )
                context.insert(task)
            }
        }

        // 端末側で消えたミラーは削除（読み取り専用ミラーの整合）。
        for (eid, task) in byID where !seen.contains(eid) {
            context.delete(task)
        }

        try? context.save()
    }

    /// 外部変更（.EKEventStoreChanged）を購読して自動再同期する。
    func observeChanges(into context: ModelContext) {
        guard changeObserver == nil else { return }
        changeObserver = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged,
            object: store,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.sync(into: context)
            }
        }
    }
}
