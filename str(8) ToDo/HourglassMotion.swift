//
//  HourglassMotion.swift
//  str8ToDo
//
//  砂時計タイマーの姿勢検出。
//  - HourglassStateMachine: 純 Foundation のステートマシン（p4-selfcheck で検証、macOS でもコンパイル可）
//  - HourglassMotionService: CoreMotion を 60Hz で回してステートマシンに流す（実機のみ）
//  - MotionHUDView: チューニング用ライブ表示（P5 の chop チューニングでも流用）
//
//  実機残項目: 意図フリップ 10/10 検出、机バンプ誤発火 0、Tuning 値の実機調整。
//

import Foundation

// MARK: - ステートマシン（純粋ロジック）

/// setting →(faceUp)→ armed →(faceDown+意図フリップ)→ running →(faceUp)→ paused →(faceDown)→ running。
/// 姿勢はヒステリシス付き、全遷移に 0.3 秒デバウンス。キャンセルは UI 側の長押し（reset()）。
struct HourglassStateMachine {
    enum Posture { case portrait, faceUp, faceDown, other }
    enum Phase { case setting, armed, running, paused }

    /// 実機チューニングで触るのはここだけ。
    enum Tuning {
        /// |gravity.z| がこれを超えたら faceUp/faceDown に入る（CoreMotion 規約: faceDown ≈ +1 / faceUp ≈ -1）。
        static let enter = 0.75
        /// これを下回ったら faceUp/faceDown から抜ける（ヒステリシス）。
        static let exit = 0.6
        /// 姿勢がこの秒数継続して初めて遷移する。
        static let debounce: TimeInterval = 0.3
        /// |rotationRate| がこれを超えたら意図的フリップとみなす（rad/s）。
        static let gyroPeakThreshold = 4.0
        /// フリップピークの有効時間（デバウンス経由でも running 判定が拾えるだけの幅）。
        static let gyroPeakWindow: TimeInterval = 0.8
    }

    private(set) var phase: Phase = .setting
    private(set) var posture: Posture = .other
    private var candidate: Posture?
    private var candidateSince: TimeInterval = 0
    private var lastGyroPeakAt: TimeInterval = -.infinity

    mutating func reset() {
        phase = .setting
        posture = .other
        candidate = nil
        lastGyroPeakAt = -.infinity
    }

    @discardableResult
    mutating func ingest(gravityZ: Double, gyroPeak: Bool, at time: TimeInterval) -> Phase {
        if gyroPeak { lastGyroPeakAt = time }

        let raw = rawPosture(gravityZ: gravityZ)
        if raw != posture {
            if candidate == raw {
                if time - candidateSince >= Tuning.debounce {
                    posture = raw
                    candidate = nil
                    transition(at: time)
                }
            } else {
                candidate = raw
                candidateSince = time
            }
        } else {
            candidate = nil
        }
        return phase
    }

    /// ヒステリシス付きの生姿勢判定。faceUp/faceDown は exit を下回るまで維持。
    private func rawPosture(gravityZ z: Double) -> Posture {
        switch posture {
        case .faceDown where z > Tuning.exit:
            return .faceDown
        case .faceUp where z < -Tuning.exit:
            return .faceUp
        default:
            if z > Tuning.enter { return .faceDown }
            if z < -Tuning.enter { return .faceUp }
            return .portrait   // ponytail: portrait/other を区別しない（遷移判定に不要）
        }
    }

    private mutating func transition(at time: TimeInterval) {
        switch (phase, posture) {
        case (.setting, .faceUp):
            phase = .armed
        case (.armed, .faceDown) where time - lastGyroPeakAt <= Tuning.gyroPeakWindow:
            // 意図的フリップ（gyro ピーク直後の faceDown）のみ開始。置き直しでは開始しない
            phase = .running
        case (.running, .faceUp):
            phase = .paused          // 決定#7: 起こしたら一時停止
        case (.paused, .faceDown):
            phase = .running         // 再開に gyroPeak は不要
        default:
            break
        }
    }
}

// MARK: - CoreMotion サービス（実機のみ。macOS の selfcheck コンパイルでは除外）

#if canImport(CoreMotion) && os(iOS)
import CoreMotion
import SwiftUI

@MainActor
@Observable
final class HourglassMotionService {
    private let manager = CMMotionManager()
    private(set) var machine = HourglassStateMachine()
    private(set) var gravityZ: Double = 0
    private(set) var rotationRateX: Double = 0

    var phase: HourglassStateMachine.Phase { machine.phase }
    /// シミュレータでは false（UI は手動モードにフォールバック）。
    var isAvailable: Bool { manager.isDeviceMotionAvailable }

    func start() {
        guard isAvailable, !manager.isDeviceMotionActive else { return }
        manager.deviceMotionUpdateInterval = 1.0 / 60.0
        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let motion else { return }
            MainActor.assumeIsolated {
                guard let self else { return }
                self.gravityZ = motion.gravity.z
                self.rotationRateX = motion.rotationRate.x
                let peak = abs(motion.rotationRate.x) > HourglassStateMachine.Tuning.gyroPeakThreshold
                self.machine.ingest(gravityZ: motion.gravity.z, gyroPeak: peak, at: motion.timestamp)
            }
        }
    }

    func stop() {
        manager.stopDeviceMotionUpdates()
    }

    func reset() {
        machine.reset()
    }
}

// MARK: - チューニング HUD

struct MotionHUDView: View {
    let service: HourglassMotionService

    var body: some View {
        List {
            Section("ライブ値") {
                LabeledContent("gravity.z", value: String(format: "%+.3f", service.gravityZ))
                LabeledContent("rotationRate.x", value: String(format: "%+.3f", service.rotationRateX))
                LabeledContent("Phase", value: phaseLabel(service.phase))
                LabeledContent("センサー", value: service.isAvailable ? "利用可" : "利用不可（Sim）")
            }
            Section("Tuning") {
                LabeledContent("enter", value: "\(HourglassStateMachine.Tuning.enter)")
                LabeledContent("exit", value: "\(HourglassStateMachine.Tuning.exit)")
                LabeledContent("debounce", value: "\(HourglassStateMachine.Tuning.debounce)s")
                LabeledContent("gyroPeak", value: "\(HourglassStateMachine.Tuning.gyroPeakThreshold) rad/s")
            }
        }
        .navigationTitle("Motion HUD")
    }

    private func phaseLabel(_ phase: HourglassStateMachine.Phase) -> String {
        switch phase {
        case .setting: return "setting"
        case .armed:   return "armed"
        case .running: return "running"
        case .paused:  return "paused"
        }
    }
}

#endif

// MARK: - スナップショット復元判定（純粋ロジック）

/// 保存されたスナップショット辞書から復元アクションを決める純粋関数。
/// タイマー中に死んだ場合の復元シナリオ: 実行中で期限超過→自動finish / 一時停止中→復元のみ / 壊れたデータ→クリア。
enum TimerRestore: Equatable {
    case invalid
    case resume(sessionStart: Date, accumulated: TimeInterval, runStartedAt: Date?, selectedMinutes: Int, linkedTaskID: UUID?, linkedSubjectID: UUID?, alarmID: UUID)
    case autoFinish(sessionStart: Date, end: Date, linkedTaskID: UUID?, linkedSubjectID: UUID?, alarmID: UUID)

    /// スナップショット辞書から復元アクションを判定する。
    /// - パース失敗・不正値（selectedMinutes ≤ 0、accumulated < 0、キー欠落）は .invalid。
    /// - 実行中で期限内：.resume。
    /// - 実行中で期限超過：.autoFinish(end: plannedEnd)。
    /// - 一時停止中（runStartedAt なし）：.resume。
    static func decide(snapshot: [String: Any], now: Date) -> TimerRestore {
        // パース: 必須キー
        guard let sessionStartRef = snapshot["sessionStart"] as? TimeInterval,
              let accum = snapshot["accumulated"] as? TimeInterval,
              let selectedMin = snapshot["selectedMinutes"] as? Int,
              let alarmIDStr = snapshot["alarmID"] as? String,
              let alarmUUID = UUID(uuidString: alarmIDStr) else {
            return .invalid
        }

        // 妥当性チェック: selectedMinutes > 0、accumulated >= 0
        guard selectedMin > 0 else { return .invalid }
        guard accum >= 0 else { return .invalid }

        let sessionStart = Date(timeIntervalSinceReferenceDate: sessionStartRef)
        let totalDuration = TimeInterval(selectedMin * 60)

        // accumulated <= totalDuration（無限ループ防止）
        guard accum <= totalDuration else { return .invalid }

        // オプションキー
        let restoredRunStartedAt: Date? = (snapshot["runStartedAt"] as? TimeInterval).map { Date(timeIntervalSinceReferenceDate: $0) }
        let restoredLinkedTaskID: UUID? = (snapshot["linkedTaskID"] as? String).flatMap { UUID(uuidString: $0) }
        let restoredLinkedSubjectID: UUID? = (snapshot["linkedSubjectID"] as? String).flatMap { UUID(uuidString: $0) }

        // 実行中の場合のみ期限切れ判定
        if let runStarted = restoredRunStartedAt {
            let remainingTime = totalDuration - accum
            let plannedEnd = runStarted.addingTimeInterval(remainingTime)

            // end < start の不正セッション（復元中に start が進む等で発生可能）を防止
            guard plannedEnd >= sessionStart else { return .invalid }

            // now >= plannedEnd なら自動 finish
            if now >= plannedEnd {
                return .autoFinish(
                    sessionStart: sessionStart,
                    end: plannedEnd,
                    linkedTaskID: restoredLinkedTaskID,
                    linkedSubjectID: restoredLinkedSubjectID,
                    alarmID: alarmUUID
                )
            }
        }

        // 一時停止中 or 実行中で期限内→復元のみ
        return .resume(
            sessionStart: sessionStart,
            accumulated: accum,
            runStartedAt: restoredRunStartedAt,
            selectedMinutes: selectedMin,
            linkedTaskID: restoredLinkedTaskID,
            linkedSubjectID: restoredLinkedSubjectID,
            alarmID: alarmUUID
        )
    }
}
