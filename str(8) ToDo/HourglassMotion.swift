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

/// 仕様反転 2026-07-14: 上部（カメラ側）を床につけた状態 = armed（待機）／ 下部（充電口側）を床につけた状態＝ running（開始）。
/// 旧仕様（下部=armed, 上部=running）を反転。armed 中は画面に「ひっくり返して開始」を 180° 回転描画し、
/// ユーザーが端末を通常方向に戻す（≒ 意図フリップ）と running へ遷移する。
///
/// setting →(faceDown＝上部が下)→ armed →(faceUp＝下部が下＋意図フリップ)→ running
/// running →(faceDown)→ paused →(faceUp)→ running（再開は gyroPeak 不要）。
/// 姿勢はヒステリシス付き、全遷移に 0.3 秒デバウンス。キャンセルは UI 側の長押し（reset()）。
///
/// ponytail: 物理的な検出は「充電口を床につけて端末を垂直に立てた状態＝ faceUp（gravity.y ≈ -1）」を 0°、
/// 「上端を床につけて端末を垂直に立てた状態＝ faceDown（gravity.y ≈ +1）」を 180° と定義。
/// ingest には gravity.y を渡す（旧仕様は gravity.z による画面フリップ検出。仕様修正 2026-07-11）。
/// enum ケース名（faceUp/faceDown）は後方互換のため据え置き。意味は「端末上部が上／下」に置換。
struct HourglassStateMachine {
    enum Posture { case portrait, faceUp, faceDown, other }
    enum Phase { case setting, armed, running, paused }

    /// 実機チューニングで触るのはここだけ。
    enum Tuning {
        /// |gravity.y| がこれを超えたら faceUp/faceDown に入る（端末垂直判定: 上端上 ≈ -1 / 上端下 ≈ +1）。
        /// 完全垂直でなくても拾えるよう 0.75 → 0.65 に緩和。
        static let enter = 0.65
        /// これを下回ったら faceUp/faceDown から抜ける（ヒステリシス）。
        static let exit = 0.5
        /// 姿勢がこの秒数継続して初めて遷移する。反応を早めるため 0.3 → 0.2 に短縮。
        static let debounce: TimeInterval = 0.2
        /// |rotationRate| がこれを超えたら意図的フリップとみなす（rad/s）。
        /// 4.0 → 2.0 → 1.2 と段階的に緩和。手首の返しが軽くても拾える水準。
        /// 机置き誤発火は enter 閾値で二重ガード。
        static let gyroPeakThreshold = 1.2
        /// フリップピークの有効時間（デバウンス経由でも running 判定が拾えるだけの幅）。
        /// debounce 短縮に合わせても余裕を持たせるため 0.8 → 1.5 秒に拡張。
        static let gyroPeakWindow: TimeInterval = 1.5
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

    /// ingest には gravity.y を渡す（端末垂直軸方向の重力成分）。旧引数名 gravityZ は互換のため据え置き。
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
        // 仕様反転 2026-07-14: 上部（カメラ側）を床に向けた state を armed（待機）、
        // 下部（充電口側）を床に向けた state を running（開始）に。
        switch (phase, posture) {
        case (.setting, .faceDown):
            // 上部を下 = ジェスチャ待機状態
            phase = .armed
        case (.armed, .faceUp) where time - lastGyroPeakAt <= Tuning.gyroPeakWindow:
            // 意図的フリップ（gyro ピーク直後の faceUp＝下部を下）で開始。置き直しでは開始しない
            phase = .running
        case (.running, .faceDown):
            // 再び上部を下にしたら一時停止（旧仕様: 起こしたら一時停止 の反転）
            phase = .paused
        case (.paused, .faceUp):
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
    /// 端末垂直軸方向の重力成分。上端上 ≈ -1、上端下（フリップ後）≈ +1。仕様修正 2026-07-11。
    private(set) var gravityY: Double = 0
    private(set) var rotationRateX: Double = 0

    var phase: HourglassStateMachine.Phase { machine.phase }
    /// シミュレータでは false（UI は手動モードにフォールバック）。
    var isAvailable: Bool { manager.isDeviceMotionAvailable }
    /// 現在の端末姿勢が faceDown（上端が床側、gravity.y > 0.75）か否か。
    var isDeviceFaceDown: Bool { gravityY > HourglassStateMachine.Tuning.enter }

    func start() {
        guard isAvailable, !manager.isDeviceMotionActive else { return }
        manager.deviceMotionUpdateInterval = 1.0 / 60.0
        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let motion else { return }
            MainActor.assumeIsolated {
                guard let self else { return }
                self.gravityY = motion.gravity.y
                self.rotationRateX = motion.rotationRate.x
                // ponytail: 旧実装は rotationRate.x だけを見ていたため、フリップ軸が縦方向 (y) や
                // 斜めに寄ると gyroPeak が拾えず armed→running に遷移しなかった。3 軸合成で拾う。
                let rx = motion.rotationRate.x
                let ry = motion.rotationRate.y
                let rz = motion.rotationRate.z
                let magnitude = (rx * rx + ry * ry + rz * rz).squareRoot()
                let peak = magnitude > HourglassStateMachine.Tuning.gyroPeakThreshold
                self.machine.ingest(gravityZ: motion.gravity.y, gyroPeak: peak, at: motion.timestamp)
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
                LabeledContent("gravity.y", value: String(format: "%+.3f", service.gravityY))
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
