//
//  TimerActivity.swift
//  str(8) ToDo
//
//  Handoff 08c: 集中タイマーの Live Activity 属性。app / widget 両ターゲットで共有される。
//  ContentState は毎秒の再描画は避け、pause/resume/end イベント時のみ更新する
//  （残時間は endDate との差分で widget 側が算出）。
//

import Foundation
import ActivityKit

@available(iOS 16.1, *)
struct TimerAttributes: ActivityAttributes {
    /// タイマー固有情報（開始時に確定）。
    let subjectName: String?          // 「統計学」等（nil で未設定）
    let taskTitle: String             // 「レポート下書き」等

    /// 動的パート（fire 時と pause/resume でしか変えない）。
    struct ContentState: Codable, Hashable {
        /// 予定終了時刻（絶対）。remain は endDate.timeIntervalSinceNow で widget が計算。
        let endDate: Date
        /// 元の総時間（分）。バー進捗の分母。
        let totalMinutes: Int
        /// 一時停止中か。true のとき Widget 側は残時間表示を凍結。
        let isPaused: Bool
        /// 一時停止時に残っていた秒数（isPaused=true のときのみ有効）。
        let pausedRemainingSec: Int
    }
}
