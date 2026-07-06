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
