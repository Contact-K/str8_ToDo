//
//  WeekView.swift
//  str8ToDo
//
//  週=マイ時間割グリッド。列=日、行=BandAssignment から解決した枠。
//  行高は情報量基準（bandRowHeights）、時刻厳守タスクは CapsuleColumnOverlay で縦断表示。
//

import SwiftUI
import SwiftData

struct WeekView: View {
    @Binding var selectedDate: Date
    var morph: Namespace.ID? = nil
    var categoryFilter: Set<UUID>? = nil
    var onSelectTask: ((TaskItem) -> Void)? = nil
    var onPickDay: (Date) -> Void
    var onOpenSettings: (() -> Void)? = nil

    @Environment(\.modelContext) private var context
    @Query private var tasks: [TaskItem]
    @AppStorage(AppSettingsKey.weekShowSevenDays) private var showSevenDays = AppSettingsKey.weekShowSevenDaysDefault
    @State private var bandFrames: [BandFrameInfo] = []

    // Dynamic Type に追随する行高パラメータ
    @ScaledMetric private var rowMinHeight: CGFloat = 44
    @ScaledMetric private var rowMaxHeight: CGFloat = 140
    @ScaledMetric private var rowBaseHeight: CGFloat = 30
    @ScaledMetric private var rowPerChip: CGFloat = 20
    @ScaledMetric private var headerHeight: CGFloat = 60
    @ScaledMetric private var allDayRowHeight: CGFloat = 26

    private let weekCalendar: Calendar = {
        var c = Calendar.current
        c.firstWeekday = 1
        return c
    }()

    private let gridLine = Color(.systemGray4)

    private var weekDays: [Date] {
        guard let interval = weekCalendar.dateInterval(of: .weekOfMonth, for: selectedDate) else {
            return []
        }
        var days: [Date] = []
        var current = interval.start
        for _ in 0..<7 {
            days.append(current)
            current = weekCalendar.date(byAdding: .day, value: 1, to: current) ?? current
        }
        if showSevenDays { return days }
        return days.filter { (2...6).contains(weekCalendar.component(.weekday, from: $0)) }
    }

    var body: some View {
        GeometryReader { geo in
            let days = weekDays
            let dayWidth: CGFloat = showSevenDays ? 96 : max(64, geo.size.width / CGFloat(max(days.count, 1)))
            let bandsByDay = days.map { orderedBands(for: $0) }
            let chipsByDay = days.map { chipTasks(on: $0) }
            let chipCounts: [[Int]] = zip(bandsByDay, chipsByDay).map { bands, chips in
                var counts = [Int](repeating: 0, count: bands.count)
                for task in chips {
                    if let idx = snapIndex(task, bands: bands) {
                        counts[idx] += 1
                    }
                }
                return counts
            }
            let rowHeights = bandRowHeights(chipCounts: chipCounts, minHeight: rowMinHeight,
                                            maxHeight: rowMaxHeight, base: rowBaseHeight, perChip: rowPerChip)

            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Picker("表示", selection: $showSevenDays) {
                        Text("7日").tag(true)
                        Text("平日").tag(false)
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 220)

                    if let onOpenSettings {
                        Button(action: onOpenSettings) {
                            Image(systemName: "gearshape")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .accessibilityLabel("時間割を編集")
                    }
                }
                .padding(.vertical, 6)

                ScrollView(.vertical, showsIndicators: true) {
                    ScrollViewReader { proxy in
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(alignment: .top, spacing: 0) {
                                ForEach(Array(days.enumerated()), id: \.element.timeIntervalSinceReferenceDate) { dayIdx, day in
                                    dayColumn(day, bands: bandsByDay[dayIdx], chips: chipsByDay[dayIdx],
                                              rowHeights: rowHeights, width: dayWidth)
                                        .id(dayKey(day, weekCalendar))
                                }
                            }
                            .coordinateSpace(name: "weekGrid")
                            .overlay(alignment: .topLeading) {
                                capsuleLayer(days: days)
                            }
                            .onPreferenceChange(BandFramePreferenceKey.self) { bandFrames = $0 }
                        }
                        .onAppear {
                            proxy.scrollTo(dayKey(selectedDate, weekCalendar), anchor: .center)
                        }
                    }
                    .padding(.bottom, 8)
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - タスク抽出

    /// その日に出現する対象タスク（someday 除外・カテゴリフィルタ通過。RRULE は occurs で展開）。
    private func weekTasks(on day: Date) -> [TaskItem] {
        tasks.filter { task in
            guard task.phase != .someday else { return false }
            guard task.occurs(on: day, calendar: weekCalendar) else { return false }
            if let catFilter = categoryFilter {
                guard let cat = task.category, catFilter.contains(cat.id) else { return false }
            }
            return true
        }
    }

    /// チップ表示対象（時刻付き・非終日・非時刻厳守。時刻厳守はキャプセルのみ）。
    private func chipTasks(on day: Date) -> [TaskItem] {
        weekTasks(on: day).filter { !$0.isAllDay && $0.startDate != nil && !$0.isTimePinned }
    }

    /// キャプセル表示対象（時刻厳守）。
    private func pinnedTasks(on day: Date) -> [TaskItem] {
        weekTasks(on: day).filter { !$0.isAllDay && $0.startDate != nil && $0.isTimePinned }
    }

    private func orderedBands(for day: Date) -> [Band] {
        BandAssignment.resolveTemplate(for: day, context: context, calendar: weekCalendar)?.orderedBands ?? []
    }

    private func snapIndex(_ task: TaskItem, bands: [Band]) -> Int? {
        guard let start = task.startDate else { return nil }
        return bandIndex(forStartMinute: minuteOfDay(of: start, calendar: weekCalendar),
                         bands: bands.map { ($0.startMinutes, $0.endMinutes) })
    }

    /// startDate 当日の出現か（RRULE 展開の重複出現に morph ID を付けないための判定）。
    private func isOriginOccurrence(_ task: TaskItem, day: Date) -> Bool {
        guard let start = task.startDate else { return false }
        return weekCalendar.isDate(start, inSameDayAs: day)
    }

    // MARK: - 列と行

    private func dayColumn(_ day: Date, bands: [Band], chips: [TaskItem],
                           rowHeights: [CGFloat], width: CGFloat) -> some View {
        VStack(spacing: 0) {
            dayHeaderCell(day, width: width)
            allDayRow(day, width: width)

            // ponytail: 行は index 整列。テンプレが違う列は自分の枠名を表示
            ForEach(Array(bands.enumerated()), id: \.element.id) { rowIndex, band in
                gridCell(day: day, title: band.name, band: band, rowIndex: rowIndex,
                         cellTasks: chips.filter { snapIndex($0, bands: bands) == rowIndex },
                         width: width,
                         height: rowIndex < rowHeights.count ? rowHeights[rowIndex] : rowMinHeight)
            }

            if bands.isEmpty {
                // ponytail: テンプレ未割当の日は枠なし1セルに全チップ。キャプセルは枠フレームがないと
                // 描けないため、時刻厳守タスクもここではチップとして表示する（タスクを隠さない）
                let visible = chips + pinnedTasks(on: day)
                if !visible.isEmpty {
                    gridCell(day: day, title: "枠なし", band: nil, rowIndex: 0,
                             cellTasks: visible, width: width, height: 88)
                }
            }
        }
        .frame(width: width)
    }

    private func dayHeaderCell(_ day: Date, width: CGFloat) -> some View {
        let header = VStack(spacing: 4) {
            HStack(spacing: 3) {
                Image(systemName: "cloud.sun")
                    .font(.caption)
                    .foregroundStyle(.gray.opacity(0.5))
                Text(dayString(day))
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(isToday(day) ? Color.accentColor : weekdayColor(day))
            }
            Text("\(weekCalendar.component(.day, from: day))")
                .font(.subheadline)
                .fontWeight(.bold)
                .foregroundStyle(isToday(day) ? Color.accentColor : Color.primary)
        }
        .frame(width: width, height: headerHeight)
        .background(isToday(day) ? Color.accentColor.opacity(0.08) : Color.clear)
        .border(gridLine, width: 0.5)
        .contentShape(Rectangle())
        .onTapGesture { onPickDay(day) }

        return Group {
            if let morph {
                header.matchedGeometryEffect(id: dayKey(day, weekCalendar), in: morph)
            } else {
                header
            }
        }
    }

    private func allDayRow(_ day: Date, width: CGFloat) -> some View {
        let allDay = weekTasks(on: day).filter { $0.isAllDay }
        return HStack(spacing: 2) {
            ForEach(allDay.prefix(2), id: \.id) { task in
                taskChip(task, day: day)
            }
            if allDay.count > 2 {
                Text("+\(allDay.count - 2)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 3)
        .frame(width: width, height: allDayRowHeight, alignment: .leading)
        .border(gridLine, width: 0.5)
        .clipped()
    }

    /// 枠セル共通レイアウト。band が非 nil のときだけ BandFramePreferenceKey を発行する
    /// （キャプセル座標は枠セルのフレームのみから作る非対称を維持。落とすと座標が壊れる）。
    private func gridCell(day: Date, title: String, band: Band?, rowIndex: Int,
                          cellTasks: [TaskItem], width: CGFloat, height: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            // 左ラベル列の代わりにセル上部に枠名（列ごとにテンプレが違っても成立）
            Text(title)
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)

            ForEach(cellTasks.prefix(5), id: \.id) { task in
                taskChip(task, day: day)
            }
            if cellTasks.count > 5 {
                Text("+\(cellTasks.count - 5)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(3)
        .frame(width: width, height: height, alignment: .topLeading)
        .background(Color.gray.opacity(0.05))
        .border(gridLine, width: 0.5)
        .clipped()
        .background(
            Group {
                if let band {
                    GeometryReader { geo in
                        Color.clear.preference(key: BandFramePreferenceKey.self, value: [
                            BandFrameInfo(dayKey: dayKey(day, weekCalendar), rowIndex: rowIndex,
                                          startMinute: band.startMinutes, endMinute: band.endMinutes,
                                          rect: geo.frame(in: .named("weekGrid")))
                        ])
                    }
                }
            }
        )
    }

    // MARK: - チップとキャプセル

    @ViewBuilder
    private func taskChip(_ task: TaskItem, day: Date) -> some View {
        let chip = HStack(spacing: 3) {
            Circle().fill(task.effectiveColor).frame(width: 7, height: 7)
            Text(task.title)
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.tail)
                .strikethrough(task.isDone)
            if !task.isAllDay, let start = task.startDate {
                Text(hhmmLabel(minuteOfDay(of: start, calendar: weekCalendar)))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if task.isImportant {
                Image(systemName: "star.fill")
                    .font(.caption2)
                    .foregroundStyle(.yellow)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .background(task.effectiveColor.opacity(0.2))
        .cornerRadius(4)
        .contentShape(Rectangle())
        .onTapGesture { onSelectTask?(task) }
        .accessibilityElement(children: .combine)

        // RRULE 展開の重複出現には morph ID を付けない（ID 重複で Morph が壊れる）
        if let morph, isOriginOccurrence(task, day: day) {
            chip.matchedGeometryEffect(id: "evt-\(task.id.uuidString)", in: morph)
        } else {
            chip
        }
    }

    @ViewBuilder
    private func capsuleLayer(days: [Date]) -> some View {
        ForEach(days, id: \.timeIntervalSinceReferenceDate) { day in
            let key = dayKey(day, weekCalendar)
            let frames = bandFrames.filter { $0.dayKey == key }.sorted { $0.rowIndex < $1.rowIndex }
            if let first = frames.first {
                CapsuleColumnOverlay(
                    tasks: pinnedTasks(on: day),
                    rows: frames.map(\.rowFrame),
                    columnMinX: first.rect.minX,
                    columnWidth: first.rect.width,
                    morph: morph,
                    isOrigin: { isOriginOccurrence($0, day: day) },
                    onSelectTask: onSelectTask
                )
            }
        }
    }

    // MARK: - ヘルパー

    private func isToday(_ date: Date) -> Bool { weekCalendar.isDateInToday(date) }

    private func dayString(_ date: Date) -> String {
        ["日", "月", "火", "水", "木", "金", "土"][weekCalendar.component(.weekday, from: date) - 1]
    }

    private func weekdayColor(_ date: Date) -> Color {
        let weekday = weekCalendar.component(.weekday, from: date)
        if weekday == 1 { return .red }
        if weekday == 7 { return .blue }
        return .gray
    }
}

#Preview {
    NavigationStack {
        WeekView(
            selectedDate: .constant(.now),
            onPickDay: { _ in }
        )
    }
    .modelContainer(PreviewData.container)
}
