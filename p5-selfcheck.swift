//
//  p5-selfcheck.swift — Phase 5 の自己チェック（ChopStateMachine、承認境界、ApprovalMessage）
//
//  実行方法（macOS、リポジトリルートで）:
//    cd "/Users/konnotakuto/Swift_PRJS/str(8)_ToDo/str(8) ToDo" && \
//    DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swiftc -parse-as-library \
//      "str(8) ToDo/Enums.swift" "str(8) ToDo/TaskItem.swift" \
//      "str(8) ToDo/SupportingModels.swift" "str(8) ToDo/BandModels.swift" \
//      "str(8) ToDo/Color+Hex.swift" "str(8) ToDo/FocusSession.swift" "str(8) ToDo/ChopDetector.swift" \
//      "str(8) ToDo/Subject.swift" \
//      "str(8) ToDo/ApprovalMessage.swift" p5-selfcheck.swift -o /tmp/p5check && /tmp/p5check
//
//  アプリターゲットには含めない（pbxproj 未登録）。ロジックが壊れたら assert で落ちる。
//

import Foundation
import SwiftData

// テスト関数を分割して、各ケースで状態をリセット
func testPeakToStillnessDetection() {
    var machine = ChopStateMachine()

    // ピーク検出
    machine.ingest(accelerationMagnitude: 2.5, at: 0.0)
    assert(machine.state == .peaked, "Peak: 加速度 > peakThreshold で peaked")

    // 静止開始（まだ持続時間不足）
    let r1 = machine.ingest(accelerationMagnitude: 0.1, at: 0.1)
    assert(r1 == false && machine.state == .peaked,
           "Peak->Still (0.1s): chopDetected=false, state=peaked")

    // 静止継続で確定
    let r2 = machine.ingest(accelerationMagnitude: 0.1, at: 0.3)
    assert(r2 == true && machine.state == .cooldown,
           "Peak->Still (0.2s): chopDetected=true, state=cooldown")
}

func testPeakWithoutStillness() {
    var machine = ChopStateMachine()

    // ピーク検出
    machine.ingest(accelerationMagnitude: 2.5, at: 0.0)

    // 加速度が続く
    machine.ingest(accelerationMagnitude: 1.5, at: 0.2)
    assert(machine.state == .peaked, "Move after peak: state=peaked")

    // stillWindow を超える → リセット
    machine.ingest(accelerationMagnitude: 1.5, at: 0.6)
    assert(machine.state == .idle, "Exceeded stillWindow: state=idle")
}

func testStillnessWithoutPeak() {
    var machine = ChopStateMachine()

    // 静止だけ
    machine.ingest(accelerationMagnitude: 0.1, at: 0.0)
    machine.ingest(accelerationMagnitude: 0.1, at: 0.3)
    assert(machine.state == .idle, "Stillness without peak: state=idle, no chop")
}

func testCooldownIgnoresPeak() {
    var machine = ChopStateMachine()

    // チョップを確定させる
    machine.ingest(accelerationMagnitude: 2.5, at: 0.0)
    machine.ingest(accelerationMagnitude: 0.1, at: 0.1)
    let chopConfirmed = machine.ingest(accelerationMagnitude: 0.1, at: 0.3)
    assert(chopConfirmed == true && machine.state == .cooldown, "First chop confirmed")

    // cooldown 中のピークを無視
    let ignored = machine.ingest(accelerationMagnitude: 3.0, at: 0.5)
    assert(ignored == false && machine.state == .cooldown, "Peak during cooldown: ignored")
}

func testRedetectAfterCooldown() {
    var machine = ChopStateMachine()

    // 最初のチョップ (t=0.0～0.3)
    machine.ingest(accelerationMagnitude: 2.5, at: 0.0)
    machine.ingest(accelerationMagnitude: 0.1, at: 0.1)
    machine.ingest(accelerationMagnitude: 0.1, at: 0.3)
    assert(machine.state == .cooldown, "First chop done, in cooldown (peakSince=0.3)")

    // cooldown 中（t=0.3～1.3）
    machine.ingest(accelerationMagnitude: 1.5, at: 0.5)
    assert(machine.state == .cooldown, "Still in cooldown window (t=0.5, 1.1-0.3=0.8 < 1.0)")

    // cooldown 中のピークを無視
    machine.ingest(accelerationMagnitude: 2.5, at: 1.1)
    assert(machine.state == .cooldown, "Peak at t=1.1 is still ignored (1.1-0.3=0.8 < 1.0)")

    // cooldown 終了（t=1.4）→ idle に遷移
    machine.ingest(accelerationMagnitude: 0.1, at: 1.4)
    assert(machine.state == .idle, "Cooldown expired at t=1.4, transitioned to idle")

    // 新しいピークを検出
    machine.ingest(accelerationMagnitude: 2.5, at: 1.41)
    assert(machine.state == .peaked, "New peak detected after idle")

    // 2番目のチョップを確定
    machine.ingest(accelerationMagnitude: 0.1, at: 1.51)
    let secondChop = machine.ingest(accelerationMagnitude: 0.1, at: 1.71)
    assert(secondChop == true && machine.state == .cooldown, "Second chop confirmed")
}

// MARK: - Approval boundary cases

@MainActor
func testApprovalLockFuture() {
    let schema = Schema([TaskItem.self, Category.self, PlaceTag.self, DayStat.self,
                         Band.self, BandTemplate.self, BandAssignment.self, FocusSession.self])
    let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: schema, configurations: config)
    let ctx = container.mainContext

    let task = TaskItem(title: "未来ロック")
    task.status = .done
    task.completedAt = .now
    task.unlockDate = Date.now.addingTimeInterval(24 * 3600)  // 24時間後
    ctx.insert(task)

    // unlockDate が未来なら approve は false
    let result = task.approve(by: "self-future", context: ctx)
    assert(result == false, "done+unlockDate=未来 → approve は false")
    assert(task.status == .done, "承認失敗時は done のまま")
}

@MainActor
func testApprovalUnlockPast() {
    let schema = Schema([TaskItem.self, Category.self, PlaceTag.self, DayStat.self,
                         Band.self, BandTemplate.self, BandAssignment.self, FocusSession.self])
    let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: schema, configurations: config)
    let ctx = container.mainContext

    let task = TaskItem(title: "過去ロック")
    task.status = .done
    task.completedAt = .now
    task.unlockDate = Date.now.addingTimeInterval(-3600)  // 1時間前
    ctx.insert(task)

    let result = task.approve(by: "self-future", context: ctx)
    assert(result == true, "done+unlockDate=過去 → approve は true")
    assert(task.status == .approved, "承認成功で approved")
    assert(task.approverID == "self-future", "approverID が設定される")

    // DayStat の確認（当日のカウント +1）
    let day = Calendar.current.startOfDay(for: .now)
    let descriptor = FetchDescriptor<DayStat>(predicate: #Predicate { $0.day == day })
    let stats = try! ctx.fetch(descriptor)
    assert(stats.count == 1 && stats[0].completedCount == 1, "DayStat が upsert される")
}

@MainActor
func testApprovalPeerBypassLock() {
    let schema = Schema([TaskItem.self, Category.self, PlaceTag.self, DayStat.self,
                         Band.self, BandTemplate.self, BandAssignment.self, FocusSession.self])
    let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: schema, configurations: config)
    let ctx = container.mainContext

    let task = TaskItem(title: "ペア承認")
    task.status = .done
    task.completedAt = .now
    task.unlockDate = Date.now.addingTimeInterval(24 * 3600)  // まだロック中
    ctx.insert(task)

    // ペア（bypassesLock: true）は即確定
    let result = task.approve(by: "peer-device-name", context: ctx, bypassesLock: true)
    assert(result == true, "done+unlockDate=未来でもペアは承認可能（bypassesLock: true）")
    assert(task.status == .approved, "即確定で approved")
    assert(task.approverID == "peer-device-name", "approverID が相手デバイス名")

    // DayStat の確認（1回だけカウント）
    let day = Calendar.current.startOfDay(for: .now)
    let descriptor = FetchDescriptor<DayStat>(predicate: #Predicate { $0.day == day })
    let stats = try! ctx.fetch(descriptor)
    assert(stats.count == 1 && stats[0].completedCount == 1, "DayStat は1回だけ加算")
}

@MainActor
func testApprovalNoDubleCount() {
    let schema = Schema([TaskItem.self, Category.self, PlaceTag.self, DayStat.self,
                         Band.self, BandTemplate.self, BandAssignment.self, FocusSession.self])
    let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: schema, configurations: config)
    let ctx = container.mainContext

    let task = TaskItem(title: "二重確認防止")
    task.status = .done
    task.completedAt = .now
    task.unlockDate = Date.now.addingTimeInterval(-3600)
    ctx.insert(task)

    // 最初の承認
    let result1 = task.approve(by: "self-future", context: ctx)
    assert(result1 == true, "1回目の承認成功")

    // 再承認は no-op
    let result2 = task.approve(by: "other-approver", context: ctx)
    assert(result2 == false, "approved 状態への承認は false（no-op）")
    assert(task.approverID == "self-future", "approverID は変わらない")

    // DayStat の確認（1回だけ）
    let day = Calendar.current.startOfDay(for: .now)
    let descriptor = FetchDescriptor<DayStat>(predicate: #Predicate { $0.day == day })
    let stats = try! ctx.fetch(descriptor)
    assert(stats.count == 1 && stats[0].completedCount == 1, "DayStat は二重加算されない")
}

@MainActor
func testApprovalActiveTaskFails() {
    let schema = Schema([TaskItem.self, Category.self, PlaceTag.self, DayStat.self,
                         Band.self, BandTemplate.self, BandAssignment.self, FocusSession.self])
    let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: schema, configurations: config)
    let ctx = container.mainContext

    let task = TaskItem(title: "アクティブ", status: .active)
    ctx.insert(task)

    let result = task.approve(by: "approver", context: ctx)
    assert(result == false, "active タスクは approve できない")
    assert(task.status == .active, "status は変わらない")
}

// MARK: - ApprovalMessage Codable tests

func testApprovalMessageRequest() {
    let msg = ApprovalMessage.request(taskID: UUID(uuidString: "12345678-1234-5678-1234-567812345678")!, title: "Test")
    let encoder = JSONEncoder()
    let decoder = JSONDecoder()

    let data = try! encoder.encode(msg)
    let decoded = try! decoder.decode(ApprovalMessage.self, from: data)
    assert(msg == decoded, "request ラウンドトリップ失敗")
}

func testApprovalMessageApproved() {
    let msg = ApprovalMessage.approved(taskID: UUID(uuidString: "87654321-4321-8765-4321-876543218765")!)
    let encoder = JSONEncoder()
    let decoder = JSONDecoder()

    let data = try! encoder.encode(msg)
    let decoded = try! decoder.decode(ApprovalMessage.self, from: data)
    assert(msg == decoded, "approved ラウンドトリップ失敗")
}

func testApprovalMessageNIToken() {
    let tokenData = "token".data(using: .utf8)!
    let msg = ApprovalMessage.niToken(tokenData)
    let encoder = JSONEncoder()
    let decoder = JSONDecoder()

    let data = try! encoder.encode(msg)
    let decoded = try! decoder.decode(ApprovalMessage.self, from: data)
    assert(msg == decoded, "niToken ラウンドトリップ失敗")
}

@main
@MainActor
struct P5SelfCheck {
    static func main() throws {
        // ChopStateMachine tests
        testPeakToStillnessDetection()
        testPeakWithoutStillness()
        testStillnessWithoutPeak()
        testCooldownIgnoresPeak()
        testRedetectAfterCooldown()

        // Approval boundary tests
        testApprovalLockFuture()
        testApprovalUnlockPast()
        testApprovalPeerBypassLock()
        testApprovalNoDubleCount()
        testApprovalActiveTaskFails()

        // ApprovalMessage Codable tests
        testApprovalMessageRequest()
        testApprovalMessageApproved()
        testApprovalMessageNIToken()

        print("P5 self-check: ALL PASS")
    }
}
