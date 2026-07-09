//
//  CapsuleOverlay.swift
//  str8ToDo
//
//  週グリッドの横断キャプセル（時刻厳守タスク）。
//  枠セルのフレームを PreferenceKey で収集し、分→Y 補間（WeekLayout.capsuleY）で
//  枠行の上に縦断オーバーレイを描く。座標空間は "weekGrid" 基準。
//

import SwiftUI

/// 枠セル1つ分のフレーム情報（PreferenceKey で収集）。
struct BandFrameInfo: Equatable {
    let dayKey: Int
    let rowIndex: Int
    let startMinute: Int
    let endMinute: Int
    let rect: CGRect
}

struct BandFramePreferenceKey: PreferenceKey {
    static let defaultValue: [BandFrameInfo] = []
    static func reduce(value: inout [BandFrameInfo], nextValue: () -> [BandFrameInfo]) {
        value.append(contentsOf: nextValue())
    }
}

extension BandFrameInfo {
    /// キャプセル補間用の行フレームへ変換。
    var rowFrame: BandRowFrame {
        BandRowFrame(startMinute: startMinute, endMinute: endMinute, minY: rect.minY, maxY: rect.maxY)
    }
}

/// 1日カラム分のキャプセルオーバーレイ。rows / columnMinX は "weekGrid" 座標。
struct CapsuleColumnOverlay: View {
    let tasks: [TaskItem]           // その日の isTimePinned タスク
    let rows: [BandRowFrame]
    let columnMinX: CGFloat
    let columnWidth: CGFloat
    var morph: Namespace.ID? = nil
    /// startDate 当日の出現だけ true（RRULE 展開の重複出現に morph ID を付けないため）。
    var isOrigin: (TaskItem) -> Bool = { _ in true }
    var onSelectTask: ((TaskItem) -> Void)? = nil
    /// ETA があるタスクの移動セグメントを描画するための [taskID: timeInterval]。
    var travelETAs: [UUID: TimeInterval] = [:]

    private let cal = Calendar.current

    var body: some View {
        ForEach(tasks, id: \.id) { task in
            if let start = task.startDate, !rows.isEmpty {
                let startMinute = minuteOfDay(of: start, calendar: cal)
                let endMinute = startMinute + Int(task.duration / 60)
                let startY = capsuleY(forMinute: startMinute, rows: rows)
                let endY = capsuleY(forMinute: endMinute, rows: rows)

                // ponytail: 移動セグメント（departure〜start の範囲で点線ストローク、透明度低め）
                if let eta = travelETAs[task.id] {
                    let departureMinute = startMinute - Int(eta / 60)
                    let departureY = capsuleY(forMinute: departureMinute, rows: rows)

                    Path { path in
                        path.move(to: CGPoint(x: columnMinX + columnWidth / 2, y: departureY))
                        path.addLine(to: CGPoint(x: columnMinX + columnWidth / 2, y: startY))
                    }
                    .stroke(task.effectiveColor.opacity(0.3), style: StrokeStyle(lineWidth: 1.5, dash: [3]))
                }

                capsuleBody(task)
                    .frame(width: max(columnWidth - 8, 20), height: max(endY - startY, 20))
                    .offset(x: columnMinX + 4, y: startY)
            }
        }
    }

    @ViewBuilder
    private func capsuleBody(_ task: TaskItem) -> some View {
        let base = RoundedRectangle(cornerRadius: 6)
            .fill(task.effectiveColor.opacity(0.25))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(task.effectiveColor, lineWidth: 1.5)
            )
            .overlay(alignment: .topLeading) {
                Text(task.title)
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                    .padding(3)
            }
            .contentShape(Rectangle())
            .onTapGesture { onSelectTask?(task) }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("時刻厳守: \(task.title)")

        if let morph, isOrigin(task) {
            base.matchedGeometryEffect(id: "evt-\(task.id.uuidString)", in: morph)
        } else {
            base
        }
    }
}
