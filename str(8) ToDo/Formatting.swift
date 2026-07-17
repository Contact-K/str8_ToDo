//
//  Formatting.swift
//  str8ToDo
//
//  共有フォーマッタ。所要時間の「2時間30分」形式など。
//

import Foundation

/// 秒 → "1h 32m" / "45m" / "12h" 形式。負値は 0 クランプ。
func hmText(_ seconds: TimeInterval) -> String {
    let total = max(0, Int(seconds.rounded()))
    let h = total / 3600
    let m = (total % 3600) / 60
    if h > 0 && m > 0 { return "\(h)h \(m)m" }
    if h > 0 { return "\(h)h" }
    return "\(m)m"
}

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

/// 秒 → 「3:45」形式のカウントダウン表示（負値は 0 にクランプ）。
func countdownText(_ seconds: TimeInterval) -> String {
    let clamped = max(0, Int(seconds))
    return "\(clamped / 60):\(String(format: "%02d", clamped % 60))"
}

/// 金額（Decimal）→ 「¥1,490」形式（ja_JP 通貨）。
func currencyText(_ amount: Decimal) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .currency
    formatter.locale = Locale(identifier: "ja_JP")
    return formatter.string(from: amount as NSDecimalNumber) ?? "¥0"
}
