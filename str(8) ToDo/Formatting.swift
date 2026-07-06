//
//  Formatting.swift
//  str8ToDo
//
//  共有フォーマッタ。所要時間の「2時間30分」形式など。
//

import Foundation

/// 秒 → 「45分」「2時間」「2時間30分」形式。
func durationText(_ seconds: TimeInterval) -> String {
    let minutes = Int(seconds) / 60
    if minutes < 60 {
        return "\(minutes)分"
    }
    let hours = minutes / 60
    let remainder = minutes % 60
    if remainder == 0 {
        return "\(hours)時間"
    }
    return "\(hours)時間\(remainder)分"
}
