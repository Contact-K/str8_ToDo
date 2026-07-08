//
//  AlarmService.swift
//  str8ToDo
//
//  AlarmKit ラッパー。タイマー終了をロック中・サイレント中でも確実に知らせる。
//  権限が拒否された場合やシミュレータで失敗した場合は黙って通常動作（タイマー UI は動く）。
//
//  実機残項目: ロック+サイレントでの発火確認。
//
// ponytail: Live Activity のカスタム表示は P11 の Widget Extension 作成時に接続。ここではアラーム登録のみ
//

import Foundation
import SwiftUI
#if canImport(AlarmKit)
import AlarmKit

/// タイマーアラームの付加情報（現状は空。P11 の Live Activity で拡張）。
struct TimerAlarmMetadata: AlarmMetadata {}
#endif

@MainActor
enum AlarmService {

    /// fireDate に鳴るアラームを登録する。未許可なら要求し、拒否なら何もしない。
    static func schedule(id: UUID, fireDate: Date, title: String) {
        #if canImport(AlarmKit)
        Task {
            do {
                let manager = AlarmManager.shared
                switch manager.authorizationState {
                case .notDetermined:
                    guard try await manager.requestAuthorization() == .authorized else { return }
                case .authorized:
                    break
                default:
                    return
                }

                let stopButton = AlarmButton(text: "停止", textColor: .white, systemImageName: "stop.fill")
                let alert = AlarmPresentation.Alert(
                    title: LocalizedStringResource(stringLiteral: title),
                    stopButton: stopButton
                )
                let attributes = AlarmAttributes<TimerAlarmMetadata>(
                    presentation: AlarmPresentation(alert: alert),
                    tintColor: .blue
                )
                let configuration = AlarmManager.AlarmConfiguration(
                    schedule: .fixed(fireDate),
                    attributes: attributes
                )
                _ = try await manager.schedule(id: id, configuration: configuration)
            } catch {
                // シミュレータ等で失敗しても UI は通常動作
            }
        }
        #endif
    }

    static func cancel(id: UUID) {
        #if canImport(AlarmKit)
        try? AlarmManager.shared.cancel(id: id)
        #endif
    }
}
