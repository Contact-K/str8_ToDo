//
//  HeatmapView.swift
//  str(8) ToDo
//
//  GitHub風 53週×7日 グリッドヒートマップ（再利用可能）。
//  値、色、強度関数、ラベル関数を外部から注入。
//

import SwiftUI

@MainActor
struct HeatmapView: View {
    let year: Int
    let values: [Date: Double]
    let tint: Color
    let intensity: (Double) -> Double
    let labelFor: (Date, Double) -> String

    private let cal = Calendar.current

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 月ラベル行
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 2) {
                    ForEach(0..<53, id: \.self) { weekIdx in
                        VStack(spacing: 0) {
                            if let month = monthForWeek(weekIdx) {
                                if weekIdx == 0 || monthForWeek(weekIdx - 1) != month {
                                    Text("\(month)月")
                                        .font(.caption2)
                                        .fontWeight(.semibold)
                                        .lineLimit(1)
                                        .frame(width: 14, alignment: .center)
                                } else {
                                    Color.clear.frame(width: 14, height: 14)
                                }
                            } else {
                                Color.clear.frame(width: 14, height: 14)
                            }
                        }
                    }
                }
                .padding(.vertical, 4)
            }

            // ヒートマップグリッド
            ScrollView(.horizontal, showsIndicators: true) {
                HStack(spacing: 2) {
                    ForEach(0..<53, id: \.self) { weekIdx in
                        VStack(spacing: 2) {
                            ForEach(0..<7, id: \.self) { dayOfWeek in
                                if let (date, value) = cellDate(weekIdx, dayOfWeek) {
                                    cellView(date: date, value: value)
                                        .frame(width: 12, height: 12)
                                        .accessibilityLabel(labelFor(date, value))
                                } else {
                                    Color.clear
                                        .frame(width: 12, height: 12)
                                }
                            }
                        }
                    }
                }
                .padding(.vertical, 8)
            }
        }
    }

    private func monthForWeek(_ weekIdx: Int) -> Int? {
        guard let yearStart = cal.date(from: DateComponents(year: year, month: 1, day: 1)) else { return nil }
        let jan1Weekday = cal.component(.weekday, from: yearStart) - 1
        let dayOffset = weekIdx * 7 - jan1Weekday
        guard dayOffset >= 0, dayOffset < 366 else { return nil }
        guard let date = cal.date(byAdding: .day, value: dayOffset, to: yearStart) else { return nil }
        guard cal.component(.year, from: date) == year else { return nil }
        return cal.component(.month, from: date)
    }

    private func cellDate(_ weekIdx: Int, _ dayOfWeek: Int) -> (Date, Double)? {
        guard let yearStart = cal.date(from: DateComponents(year: year, month: 1, day: 1)) else { return nil }
        let jan1Weekday = cal.component(.weekday, from: yearStart) - 1
        let dayOffset = weekIdx * 7 + dayOfWeek - jan1Weekday
        guard dayOffset >= 0 else { return nil }
        guard let date = cal.date(byAdding: .day, value: dayOffset, to: yearStart) else { return nil }
        guard cal.component(.year, from: date) == year else { return nil }
        let startOfDay = cal.startOfDay(for: date)
        let value = values[startOfDay] ?? 0.0
        return (startOfDay, value)
    }

    private func cellView(date: Date, value: Double) -> some View {
        let cellOpacity = value > 0 ? intensity(value) : 0.15
        return RoundedRectangle(cornerRadius: 3)
            .fill(tint.opacity(cellOpacity))
    }
}

#Preview {
    let previewValues = Dictionary(uniqueKeysWithValues: (0..<50).map { i in
        (Calendar.current.date(byAdding: .day, value: i, to: Calendar.current.startOfDay(for: .now)) ?? .now, Double(i % 5))
    })

    return VStack {
        HeatmapView(
            year: Calendar.current.component(.year, from: .now),
            values: previewValues,
            tint: .green,
            intensity: { value in
                switch Int(value) {
                case 0: return 0.15
                case 1: return 0.4
                case 2: return 0.6
                case 3: return 0.8
                default: return 1.0
                }
            },
            labelFor: { date, value in
                let formatter = DateFormatter()
                formatter.dateFormat = "M月d日"
                return "\(formatter.string(from: date)) \(Int(value) > 0 ? "\(Int(value))件" : "記録なし")"
            }
        )
        .padding()
    }
}
