//
//  p4-selfcheck.swift — Phase 4 の自己チェック（HourglassStateMachine と FocusSession.record）
//
//  実行方法（macOS、リポジトリルートで）:
//    DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swiftc -parse-as-library \
//      "str(8) ToDo/Enums.swift" "str(8) ToDo/TaskItem.swift" \
//      "str(8) ToDo/SupportingModels.swift" "str(8) ToDo/BandModels.swift" \
//      "str(8) ToDo/Color+Hex.swift" "str(8) ToDo/FocusSession.swift" \
//      "str(8) ToDo/Subject.swift" \
//      "str(8) ToDo/HourglassMotion.swift" p4-selfcheck.swift -o /tmp/p4check && /tmp/p4check
//
//  アプリターゲットには含めない（pbxproj 未登録）。ロジックが壊れたら assert で落ちる。
//

import Foundation
import SwiftData

@main
@MainActor
struct P4SelfCheck {
    static func main() throws {
        // --- ステートマシン ---
        var machine = HourglassStateMachine()

        // portrait では setting のまま
        machine.ingest(gravityZ: 0.1, gyroPeak: false, at: 0.0)
        machine.ingest(gravityZ: 0.1, gyroPeak: false, at: 0.5)
        assert(machine.phase == .setting, "portrait では setting のまま")

        // faceUp 0.29 秒では遷移しない（デバウンス）
        machine.ingest(gravityZ: -0.9, gyroPeak: false, at: 1.0)
        machine.ingest(gravityZ: -0.9, gyroPeak: false, at: 1.29)
        assert(machine.phase == .setting, "0.29秒では armed に遷移しない")

        // 0.3 秒継続で armed
        machine.ingest(gravityZ: -0.9, gyroPeak: false, at: 1.30)
        assert(machine.phase == .armed, "faceUp 0.3秒継続で armed")

        // gyroPeak なしの faceDown では running にならない（置き直し）
        machine.ingest(gravityZ: 0.9, gyroPeak: false, at: 2.0)
        machine.ingest(gravityZ: 0.9, gyroPeak: false, at: 2.31)
        assert(machine.phase == .armed, "gyroPeak なしでは running にならない")

        // faceUp に戻して armed のまま → gyroPeak 付き faceDown で running
        machine.ingest(gravityZ: -0.9, gyroPeak: false, at: 3.0)
        machine.ingest(gravityZ: -0.9, gyroPeak: false, at: 3.31)
        assert(machine.phase == .armed)
        machine.ingest(gravityZ: 0.9, gyroPeak: true, at: 4.0)   // 意図的フリップ
        machine.ingest(gravityZ: 0.9, gyroPeak: false, at: 4.31)
        assert(machine.phase == .running, "faceDown+gyroPeak で running")

        // ヒステリシス: z=0.7（exit 0.6 < z < enter 0.75）は faceDown 維持帯
        machine.ingest(gravityZ: 0.7, gyroPeak: false, at: 5.0)
        machine.ingest(gravityZ: 0.7, gyroPeak: false, at: 5.31)
        assert(machine.phase == .running && machine.posture == .faceDown,
               "z=0.7 は維持帯（faceDown のまま）")

        // running 中 faceUp 0.3 秒で paused（決定#7）
        machine.ingest(gravityZ: -0.9, gyroPeak: false, at: 6.0)
        machine.ingest(gravityZ: -0.9, gyroPeak: false, at: 6.31)
        assert(machine.phase == .paused, "running 中に起こすと paused")

        // 再 faceDown（gyroPeak 不要）で running 再開
        machine.ingest(gravityZ: 0.9, gyroPeak: false, at: 7.0)
        machine.ingest(gravityZ: 0.9, gyroPeak: false, at: 7.31)
        assert(machine.phase == .running, "paused から faceDown で再開（gyroPeak 不要）")

        // ヒステリシスの抜け: z=0.5 で faceDown から抜ける（→ paused ではなく portrait なので running 維持）
        machine.ingest(gravityZ: 0.5, gyroPeak: false, at: 8.0)
        machine.ingest(gravityZ: 0.5, gyroPeak: false, at: 8.31)
        assert(machine.posture == .portrait, "z=0.5 で faceDown から抜ける")
        assert(machine.phase == .running, "portrait では running のまま（paused は faceUp のみ）")

        // reset
        machine.reset()
        assert(machine.phase == .setting, "reset() で setting に戻る")

        // --- FocusSession.record ---
        let schema = Schema([TaskItem.self, Category.self, PlaceTag.self, DayStat.self,
                             Band.self, BandTemplate.self, BandAssignment.self, FocusSession.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: config)
        let ctx = container.mainContext

        let task = TaskItem(title: "集中対象")
        ctx.insert(task)

        let start = Date(timeIntervalSinceReferenceDate: 1_000_000)
        let end = start.addingTimeInterval(25 * 60)

        // nil → 経過
        FocusSession.record(start: start, end: end, task: task, context: ctx)
        assert(task.actualDuration == 25 * 60, "actualDuration nil→経過")
        var sessions = try ctx.fetch(FetchDescriptor<FocusSession>())
        assert(sessions.count == 1 && sessions[0].taskID == task.id && sessions[0].subjectID == nil,
               "FocusSession が insert される")

        // 既存値 → 累積
        FocusSession.record(start: end, end: end.addingTimeInterval(5 * 60), task: task, context: ctx)
        assert(task.actualDuration == 30 * 60, "actualDuration 累積")
        sessions = try ctx.fetch(FetchDescriptor<FocusSession>())
        assert(sessions.count == 2)

        // task なしでも insert される
        FocusSession.record(start: start, end: end, task: nil, context: ctx)
        sessions = try ctx.fetch(FetchDescriptor<FocusSession>())
        assert(sessions.count == 3 && sessions.contains { $0.taskID == nil })

        // --- TimerRestore.decide ---
        let baseTime = Date(timeIntervalSinceReferenceDate: 2_000_000)
        let taskID = UUID()
        let alarmID = UUID()

        // 実行中・期限内→ .resume
        let sessionStart = baseTime
        let runStartedAt = baseTime.addingTimeInterval(5)
        let totalSecs = 25 * 60
        let accumulated: TimeInterval = 10 * 60
        let plannedEnd = runStartedAt.addingTimeInterval(TimeInterval(totalSecs) - accumulated)
        let snapshot1: [String: Any] = [
            "sessionStart": sessionStart.timeIntervalSinceReferenceDate,
            "accumulated": accumulated,
            "runStartedAt": runStartedAt.timeIntervalSinceReferenceDate,
            "selectedMinutes": 25,
            "linkedTaskID": taskID.uuidString,
            "alarmID": alarmID.uuidString
        ]
        let decision1 = TimerRestore.decide(snapshot: snapshot1, now: plannedEnd.addingTimeInterval(-1))
        if case .resume = decision1 { } else {
            fatalError("実行中・期限内は .resume")
        }

        // 実行中・期限超過→ .autoFinish(end: plannedEnd)
        let decision2 = TimerRestore.decide(snapshot: snapshot1, now: plannedEnd.addingTimeInterval(1))
        if case .autoFinish(let autFinishStart, let autoFinishEnd, _, _, _) = decision2 {
            assert(autFinishStart == sessionStart, "autoFinish の sessionStart は復元元と同じ")
            assert(autoFinishEnd == plannedEnd, "autoFinish の end は plannedEnd")
        } else {
            fatalError("実行中・期限超過は .autoFinish")
        }

        // 一時停止中（runStartedAt なし）→ .resume（何日経過でも自動finish しない）
        let snapshot2: [String: Any] = [
            "sessionStart": sessionStart.timeIntervalSinceReferenceDate,
            "accumulated": accumulated,
            "runStartedAt": NSNull(),
            "selectedMinutes": 25,
            "linkedTaskID": taskID.uuidString,
            "alarmID": alarmID.uuidString
        ]
        let decision3 = TimerRestore.decide(snapshot: snapshot2, now: sessionStart.addingTimeInterval(24 * 3600))
        if case .resume = decision3 { } else {
            fatalError("一時停止中は .resume（自動finish しない）")
        }

        // selectedMinutes = 0→ .invalid
        var snapshot3 = snapshot1
        snapshot3["selectedMinutes"] = 0
        let decision4 = TimerRestore.decide(snapshot: snapshot3, now: baseTime)
        assert(decision4 == .invalid, "selectedMinutes=0 は invalid")

        // accumulated < 0→ .invalid
        var snapshot4 = snapshot1
        snapshot4["accumulated"] = -1.0
        let decision5 = TimerRestore.decide(snapshot: snapshot4, now: baseTime)
        assert(decision5 == .invalid, "accumulated<0 は invalid")

        // accumulated > totalDuration→ .invalid
        var snapshot5 = snapshot1
        snapshot5["accumulated"] = 30.0 * 60
        let decision6 = TimerRestore.decide(snapshot: snapshot5, now: baseTime)
        assert(decision6 == .invalid, "accumulated>totalDuration は invalid")

        // キー欠落（sessionStart）→ .invalid
        var snapshot6 = snapshot1
        snapshot6.removeValue(forKey: "sessionStart")
        let decision7 = TimerRestore.decide(snapshot: snapshot6, now: baseTime)
        assert(decision7 == .invalid, "sessionStart 欠落は invalid")

        // plannedEnd < sessionStart（不正セッション）→ .invalid
        // runStartedAt + (25*60 - 10*60) = runStartedAt + 900 < sessionStart
        // ∴ runStartedAt < sessionStart - 900
        let badRunStartedAt = sessionStart.addingTimeInterval(-950)
        var snapshot7 = snapshot1
        snapshot7["runStartedAt"] = badRunStartedAt.timeIntervalSinceReferenceDate
        let decision8 = TimerRestore.decide(snapshot: snapshot7, now: baseTime)
        assert(decision8 == .invalid, "plannedEnd<sessionStart は invalid（end<start セッション防止）")

        // runStartedAt キーが存在しない（一時停止状態の復元）→ .resume
        var snapshot8 = snapshot1
        snapshot8.removeValue(forKey: "runStartedAt")
        let decision9 = TimerRestore.decide(snapshot: snapshot8, now: baseTime)
        if case .resume(_, let accum, let runStarted, _, _, _, _) = decision9 {
            assert(runStarted == nil, "runStartedAt 欠落は nil として復元")
            assert(accum == accumulated, "accumulated は保持される")
        } else {
            fatalError("runStartedAt 欠落は .resume（一時停止状態）")
        }

        // linkedTaskID キーが存在しない（紐付けなし）→ .resume（linkedTaskID = nil）
        var snapshot9 = snapshot1
        snapshot9.removeValue(forKey: "linkedTaskID")
        let decision10 = TimerRestore.decide(snapshot: snapshot9, now: plannedEnd.addingTimeInterval(-1))
        if case .resume(_, _, _, _, let linkedID, _, _) = decision10 {
            assert(linkedID == nil, "linkedTaskID 欠落は nil として復元")
        } else {
            fatalError("linkedTaskID 欠落は .resume")
        }

        print("P4 self-check: ALL PASS")
    }
}
