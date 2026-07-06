//
//  WeekLayout.swift
//  str8ToDo
//
//  週=マイ時間割グリッドのレイアウト計算（行高・分→Y 補間・枠スナップ）。
//  SwiftUI 非依存の純粋ロジック。p2-selfcheck.swift で検証する。
//

import Foundation
import CoreGraphics

/// 行 index ごとに全日の最大チップ数から行高を決める（情報量基準、実時間比例ではない）。
/// 日ごとに行数が違う場合は最大行数まで（不足行は 0 扱い）。
func bandRowHeights(chipCounts: [[Int]], minHeight: CGFloat = 44, maxHeight: CGFloat = 140,
                    base: CGFloat = 30, perChip: CGFloat = 20) -> [CGFloat] {
    let rowCount = chipCounts.map(\.count).max() ?? 0
    return (0..<rowCount).map { row in
        let maxCount = chipCounts.map { $0.indices.contains(row) ? $0[row] : 0 }.max() ?? 0
        return min(maxHeight, max(minHeight, base + CGFloat(maxCount) * perChip))
    }
}

/// 1行分のフレーム（分範囲と Y 範囲）。キャプセルの分→Y 補間に使う。
struct BandRowFrame {
    let startMinute: Int
    let endMinute: Int
    let minY: CGFloat
    let maxY: CGFloat
}

/// 分→Y。行内は線形補間、行間の隙間は前行 maxY と次行 minY の間に線形、
/// 全行より前は先頭 minY、後は末尾 maxY にクランプ。rows 空なら 0。
func capsuleY(forMinute minute: Int, rows: [BandRowFrame]) -> CGFloat {
    guard let first = rows.first, let last = rows.last else { return 0 }
    if minute <= first.startMinute { return first.minY }
    if minute >= last.endMinute { return last.maxY }

    for (i, row) in rows.enumerated() {
        if minute >= row.startMinute && minute <= row.endMinute {
            let span = row.endMinute - row.startMinute
            guard span > 0 else { return row.minY }
            let t = CGFloat(minute - row.startMinute) / CGFloat(span)
            return row.minY + t * (row.maxY - row.minY)
        }
        if i + 1 < rows.count {
            let next = rows[i + 1]
            if minute > row.endMinute && minute < next.startMinute {
                let span = next.startMinute - row.endMinute
                let t = CGFloat(minute - row.endMinute) / CGFloat(span)
                return row.maxY + t * (next.minY - row.maxY)
            }
        }
    }
    return last.maxY
}

/// 開始時刻の包含判定（start <= m < end）で枠 index を返す。
/// ponytail: 包含外は最近傍スナップ（前なら最初、後なら最後、隙間は近い方）
func bandIndex(forStartMinute minute: Int, bands: [(start: Int, end: Int)]) -> Int? {
    guard !bands.isEmpty else { return nil }
    for (i, band) in bands.enumerated() where band.start <= minute && minute < band.end {
        return i
    }
    var bestIndex = 0
    var bestDistance = Int.max
    for (i, band) in bands.enumerated() {
        let distance: Int
        if minute < band.start {
            distance = band.start - minute
        } else {
            distance = minute - band.end + 1
        }
        if distance < bestDistance {
            bestDistance = distance
            bestIndex = i
        }
    }
    return bestIndex
}

/// 分 → "H:mm" ラベル（旧 AppSettings.hhmm の代替）。
func hhmmLabel(_ minutes: Int) -> String {
    let clamped = min(max(minutes, 0), 1440)
    return String(format: "%d:%02d", clamped / 60, clamped % 60)
}

/// その日の 0:00 からの経過分（時分成分のみ。日相対版は DayRowBuilder 内の別実装）。
func minuteOfDay(of date: Date, calendar: Calendar = .current) -> Int {
    calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)
}
