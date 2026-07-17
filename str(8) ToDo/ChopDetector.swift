//
//  ChopDetector.swift
//  str8ToDo
//
//  振り下ろし（chop）検出。
//  - ChopStateMachine: 純 Foundation のステートマシン（p5-selfcheck で検証、macOS でもコンパイル可）
//  - ChopMotionService: CoreMotion を 60Hz で回してステートマシンに流す（実機のみ）
//
//  Tuning は実機の「手で持ちながらハンコを振り下ろす」ジェスチャに合わせて緩めてある：
//   - stillThreshold=0.4G: 手の常時微振動（0.1〜0.3G）を許容
//   - stillDuration=0.08s: 人間の反応時間より短く、振り下ろし直後の一瞬の停止で確定
//   - stillWindow=0.8s: 腕の惰性で 200ms 以内に静止しないケースを許容
//

import Foundation

// MARK: - ステートマシン（純粋ロジック）

/// idle → peaked（|加速度| > peakThreshold）→ stillness 検出で chop 確定
/// ピーク後 stillWindow 内に静止なし→ idle にリセット（誤振り対策）
/// chop 確定後は cooldown 中にピークを無視。
struct ChopStateMachine {
    enum State { case idle, peaked, cooldown }

    /// 実機チューニングで触るのはここだけ。
    enum Tuning {
        /// 下向きの加速度ピーク判定（g）。
        static let peakThreshold = 2.0
        /// ピーク後、この秒数以内に静止が必要。
        static let stillWindow: TimeInterval = 0.8
        /// 静止と判定する加速度の上限（g）。手の微振動を許容するため 0.4 まで緩めた。
        static let stillThreshold = 0.4
        /// 静止と判定するための継続時間（秒）。人間の反応時間より短く。
        static let stillDuration: TimeInterval = 0.08
        /// chop 確定後、次のピークを無視する時間（秒）。
        static let cooldown: TimeInterval = 1.0
    }

    private(set) var state: State = .idle
    private var peakTime: TimeInterval = 0
    private var peakSince: TimeInterval = 0
    private var stillStartTime: TimeInterval = 0
    private var isInStill: Bool = false

    mutating func reset() {
        state = .idle
        peakTime = 0
        peakSince = 0
        stillStartTime = 0
        isInStill = false
    }

    /// 加速度の大きさと現在時刻を入力。chop 確定の瞬間だけ true を返す。
    @discardableResult
    mutating func ingest(accelerationMagnitude: Double, at time: TimeInterval) -> Bool {
        // ponytail: 浮動小数点誤差対策の小さな許容値（タイマーのティック粒度より小さい）
        let epsilon: TimeInterval = 0.001

        switch state {
        case .idle:
            // ピーク検出
            if accelerationMagnitude > Tuning.peakThreshold {
                state = .peaked
                peakTime = time
                isInStill = false
                return false
            }
            return false

        case .peaked:
            // peakTime から stillWindow を超えたらリセット（誤振り対策）
            if time - peakTime > Tuning.stillWindow {
                state = .idle
                isInStill = false
                return false
            }

            // 静止中か判定
            if accelerationMagnitude < Tuning.stillThreshold {
                if !isInStill {
                    // 静止開始
                    isInStill = true
                    stillStartTime = time
                    return false
                }
                // 静止継続中
                if time - stillStartTime >= Tuning.stillDuration - epsilon {
                    // chop 確定
                    state = .cooldown
                    peakSince = time
                    isInStill = false
                    return true
                }
                return false
            } else {
                // 加速度があるので静止状態を抜ける
                isInStill = false
                return false
            }

        case .cooldown:
            // cooldown の間、次のピークを無視
            if time - peakSince >= Tuning.cooldown - epsilon {
                state = .idle
            }
            return false
        }
    }
}

// MARK: - CoreMotion サービス（実機のみ。macOS の selfcheck コンパイルでは除外）

#if canImport(CoreMotion) && os(iOS)
import CoreMotion
import SwiftUI

@MainActor
@Observable
final class ChopMotionService {
    private let manager = CMMotionManager()
    private(set) var machine = ChopStateMachine()
    private(set) var accelerationMagnitude: Double = 0

    var isAvailable: Bool { manager.isDeviceMotionAvailable }
    var onChop: (() -> Void)?

    func start() {
        guard isAvailable, !manager.isDeviceMotionActive else { return }
        manager.deviceMotionUpdateInterval = 1.0 / 60.0
        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let motion else { return }
            MainActor.assumeIsolated {
                guard let self else { return }
                let accel = motion.userAcceleration
                self.accelerationMagnitude = sqrt(accel.x * accel.x + accel.y * accel.y + accel.z * accel.z)
                if self.machine.ingest(accelerationMagnitude: self.accelerationMagnitude, at: motion.timestamp) {
                    self.onChop?()
                }
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

#endif
