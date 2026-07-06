//
//  SortDeckEngine.swift
//  str8ToDo
//
//  朝の仕分けデッキの純粋ロジック（SwiftUI 非依存）。
//  第1段=完了ゲート（もうやった？）→ 第2段=今日ゲート（今日やる？）。
//  undo/redo はスナップショット方式。p3-selfcheck.swift で検証する。
//

import Foundation
import Observation

@MainActor
@Observable
final class SortDeckEngine {
    enum Stage { case doneGate, todayGate }

    private(set) var queue: [TaskItem]
    private(set) var stage: Stage = .doneGate

    var current: TaskItem? { queue.first }
    var isFinished: Bool { queue.isEmpty }
    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    init(tasks: [TaskItem], today: Date = .now, calendar: Calendar = .current) {
        self.queue = Self.deckTasks(from: tasks, today: today, calendar: calendar)
    }

    /// デッキ対象: 浮遊（startDate なし）の active タスクで、今日まだ仕分けておらず、
    /// 先送り期限が切れているもの。sortIndex 昇順（同値は id で決定的）。
    static func deckTasks(from all: [TaskItem], today: Date = .now, calendar: Calendar = .current) -> [TaskItem] {
        let dayStart = calendar.startOfDay(for: today)
        return all.filter { task in
            guard task.startDate == nil, task.status == .active else { return false }
            if let sorted = task.lastSortedDay, sorted >= dayStart { return false }
            if let snooze = task.snoozeUntil, snooze > today { return false }
            return true
        }
        .sorted { ($0.sortIndex, $0.id.uuidString) < ($1.sortIndex, $1.id.uuidString) }
    }

    // MARK: - 回答

    /// 右スワイプ相当。doneGate=やった（markDone）/ todayGate=今日やる（phase=.today）。
    func answerRight(today: Date = .now, calendar: Calendar = .current) {
        guard let task = current else { return }
        let before = FieldState(of: task)
        let stageBefore = stage

        switch stage {
        case .doneGate:
            task.markDone()
        case .todayGate:
            task.phase = .today
            stage = .doneGate
        }
        stamp(task, today: today, calendar: calendar)
        queue.removeFirst()

        push(Snapshot(task: task, before: before, after: FieldState(of: task),
                      stageBefore: stageBefore, stageAfter: stage, removedFromQueue: true))
    }

    /// 左スワイプ相当。doneGate=まだ（第2問へ）/ todayGate=先送り（+7日 snooze）。
    func answerLeft(today: Date = .now, calendar: Calendar = .current) {
        guard let task = current else { return }
        let before = FieldState(of: task)
        let stageBefore = stage
        var removed = false

        switch stage {
        case .doneGate:
            stage = .todayGate   // 同じカードで第2問へ
        case .todayGate:
            task.snoozeUntil = calendar.date(byAdding: .day, value: 7, to: calendar.startOfDay(for: today))
            task.phase = .someday   // 先送り=「いつか」バケツへ（FieldState が phase を保存するので undo 可）
            stamp(task, today: today, calendar: calendar)
            stage = .doneGate
            queue.removeFirst()
            removed = true
        }

        push(Snapshot(task: task, before: before, after: FieldState(of: task),
                      stageBefore: stageBefore, stageAfter: stage, removedFromQueue: removed))
    }

    // MARK: - undo / redo（スナップショット方式）

    func undo() {
        guard let snapshot = undoStack.popLast() else { return }
        snapshot.before.apply(to: snapshot.task)
        if snapshot.removedFromQueue {
            queue.insert(snapshot.task, at: 0)
        }
        stage = snapshot.stageBefore
        redoStack.append(snapshot)
    }

    func redo() {
        guard let snapshot = redoStack.popLast() else { return }
        snapshot.after.apply(to: snapshot.task)
        if snapshot.removedFromQueue, queue.first === snapshot.task {
            queue.removeFirst()
        }
        stage = snapshot.stageAfter
        undoStack.append(snapshot)
    }

    // MARK: - 内部

    /// タスクの可変フィールド一式（回答の前後状態を丸ごと保存・復元する）。
    private struct FieldState {
        let status: TaskStatus
        let completedAt: Date?
        let unlockDate: Date?
        let phase: SortPhase
        let snoozeUntil: Date?
        let lastSortedDay: Date?

        init(of task: TaskItem) {
            status = task.status
            completedAt = task.completedAt
            unlockDate = task.unlockDate
            phase = task.phase
            snoozeUntil = task.snoozeUntil
            lastSortedDay = task.lastSortedDay
        }

        func apply(to task: TaskItem) {
            task.status = status
            task.completedAt = completedAt
            task.unlockDate = unlockDate
            task.phase = phase
            task.snoozeUntil = snoozeUntil
            task.lastSortedDay = lastSortedDay
        }
    }

    private struct Snapshot {
        let task: TaskItem
        let before: FieldState
        let after: FieldState
        let stageBefore: Stage
        let stageAfter: Stage
        let removedFromQueue: Bool
    }

    private var undoStack: [Snapshot] = []
    private var redoStack: [Snapshot] = []

    private func stamp(_ task: TaskItem, today: Date, calendar: Calendar) {
        task.lastSortedDay = calendar.startOfDay(for: today)
    }

    private func push(_ snapshot: Snapshot) {
        undoStack.append(snapshot)
        redoStack.removeAll()   // 新規回答で redo は破棄（標準挙動）
    }
}
