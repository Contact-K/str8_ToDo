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
    @Environment(\.colorScheme) private var scheme
    private var c: S8Palette { S8Palette.of(scheme) }
    @Query private var tasks: [TaskItem]
    @AppStorage(AppSettingsKey.weekShowSevenDays) private var showSevenDays = AppSettingsKey.weekShowSevenDaysDefault
    @State private var bandFrames: [BandFrameInfo] = []
    @State private var travelETAs: [UUID: TimeInterval] = [:]

    // Dynamic Type に追随する行高パラメータ
    @ScaledMetric private var rowMinHeight: CGFloat = 44
    @ScaledMetric private var rowMaxHeight: CGFloat = 140
    @ScaledMetric private var rowBaseHeight: CGFloat = 30
    @ScaledMetric private var rowPerChip: CGFloat = 20
    @ScaledMetric private var headerHeight: CGFloat = 60
    @ScaledMetric private var allDayRowHeight: CGFloat = 26

    /// WeekMath と週境界を統一（showSevenDays に連動。ハードコードしない）。
    private var weekCalendar: Calendar {
        var c = Calendar.current
        c.firstWeekday = WeekMath.firstWeekday(showSevenDays: showSevenDays)
        return c
    }

    /// Handoff 01b: 罫線は S8 line 系。当日ハイライトは accent-wash。

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

    /// 時刻軸カラムの幅（左端に固定）。
    private let timeAxisWidth: CGFloat = 30

    var body: some View {
        GeometryReader { geo in
            let days = weekDays
            let gridAvailableWidth = max(0, geo.size.width - timeAxisWidth)
            let dayWidth: CGFloat = showSevenDays ? max(72, gridAvailableWidth / CGFloat(max(days.count, 1))) : max(64, gridAvailableWidth / CGFloat(max(days.count, 1)))
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
            let rawHeights = bandRowHeights(chipCounts: chipCounts, minHeight: rowMinHeight,
                                            maxHeight: rowMaxHeight, base: rowBaseHeight, perChip: rowPerChip)

            // 画面いっぱいに引き伸ばすためのスケーラ。toggle バー・ヘッダ・allDay 行を差し引いた高さに揃える。
            let toggleBarH: CGFloat = 36 + 16   // ざっくり segment 高＋vertical padding
            let availableH = max(1, geo.size.height - toggleBarH - headerHeight - allDayRowHeight - 8)
            let rowSum = max(1, rawHeights.reduce(0, +))
            let scale: CGFloat = rowSum > 0 ? max(0.6, min(2.5, availableH / rowSum)) : 1
            let rowHeights = rawHeights.map { $0 * scale }

            // 時刻軸カラム用の代表バンド（最初の日の band を採用）と対応 frame。
            let axisBands = bandsByDay.first ?? []
            let axisFrames: [BandRowFrame] = {
                var frames: [BandRowFrame] = []
                var y: CGFloat = 0
                for (i, band) in axisBands.enumerated() {
                    let h = i < rowHeights.count ? rowHeights[i] : rowMinHeight
                    frames.append(BandRowFrame(startMinute: band.startMinutes,
                                                endMinute: band.endMinutes,
                                                minY: y, maxY: y + h))
                    y += h
                }
                return frames
            }()

            VStack(spacing: 0) {
                // Handoff 01b: [7日 | 平日] のピル型トグル（右寄せ）
                HStack {
                    Spacer()
                    HStack(spacing: 0) {
                        weekToggleSegment("7日", on: showSevenDays)
                            .onTapGesture { showSevenDays = true }
                        Rectangle().fill(c.lineStrong).frame(width: 1, height: 20)
                        weekToggleSegment("平日", on: !showSevenDays)
                            .onTapGesture { showSevenDays = false }
                    }
                    .overlay(Capsule().stroke(c.lineStrong, lineWidth: 1))
                    .clipShape(Capsule())
                    // ponytail: 設定はホイール6番目タブへ移設したのでここには置かない
                }
                .padding(.horizontal, 24).padding(.vertical, 8)

                HStack(alignment: .top, spacing: 0) {
                    // 左端 固定 時刻軸カラム
                    timeAxisColumn(frames: axisFrames)
                        .frame(width: timeAxisWidth)

                    // 日ごとのグリッド（横スクロール）
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
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .task(id: DayRowBuilder.travelRefreshKey(date: selectedDate, now: .now, calendar: weekCalendar)) {
            // 出発逆算 ETA を取得（週切替＋5分粒度で再実行。ゲートが24h以内に絞るので実質数件、実要求は30分キャッシュが抑える）
            await refreshTravelETAs()
        }
    }

    /// 左端の時刻軸カラム。0/3/6/9/12/15/18/21/24 時のラベルを band に沿って配置。
    private func timeAxisColumn(frames: [BandRowFrame]) -> some View {
        let hours = [0, 3, 6, 9, 12, 15, 18, 21, 24]
        let totalH = frames.last?.maxY ?? 0
        return VStack(spacing: 0) {
            // 曜日ヘッダ + allDay 行と揃えるため空スペース
            Color.clear.frame(height: headerHeight + allDayRowHeight)
            ZStack(alignment: .topLeading) {
                Rectangle().fill(c.surface2.opacity(0.5))
                if !frames.isEmpty {
                    ForEach(hours, id: \.self) { hour in
                        let y = capsuleY(forMinute: hour * 60, rows: frames)
                        HStack(spacing: 0) {
                            Text(String(format: "%02d", hour))
                                .font(S8Font.mono(9, .bold))
                                .foregroundColor(c.fg3)
                                .frame(width: timeAxisWidth - 6, alignment: .trailing)
                                .padding(.trailing, 3)
                        }
                        .position(x: timeAxisWidth / 2, y: y)
                    }
                }
                Rectangle().fill(c.line).frame(width: 1).frame(maxWidth: .infinity, alignment: .trailing)
            }
            .frame(height: totalH)
        }
    }

    /// 週内の時刻固定タスクの ETA を取得（ゲート判定は DepartureService.eta が唯一の判定点）。
    @MainActor
    private func refreshTravelETAs() async {
        let candidates = weekDays.flatMap { pinnedTasks(on: $0) }
        travelETAs = await DepartureService.shared.etas(for: candidates, now: .now)
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

    /// Handoff 01b: 曜日 + 日付。当日は accent-wash 背景 + accent-ink 文字。
    private func dayHeaderCell(_ day: Date, width: CGFloat) -> some View {
        let today = isToday(day)
        let hcolor = today ? c.accentInk : weekdayColor(day)
        let hbg = today ? c.accentWash : Color.clear
        let header = VStack(spacing: 1) {
            Text(dayString(day))
                .font(S8Font.jp(11, .bold))
                .foregroundColor(hcolor)
            Text("\(weekCalendar.component(.day, from: day))")
                .font(S8Font.mono(12.5, .bold))
                .foregroundColor(hcolor)
        }
        .frame(width: width, height: headerHeight)
        .background(hbg)
        .overlay(Rectangle().stroke(c.line, lineWidth: 0.5))
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

    /// Handoff 01b: 7日/平日 セグメント。
    private func weekToggleSegment(_ label: String, on: Bool) -> some View {
        Text(label)
            .font(S8Font.jp(11, on ? .bold : .medium))
            .foregroundColor(on ? c.fg1 : c.fg3)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(on ? c.surface2 : Color.clear)
    }

    private func allDayRow(_ day: Date, width: CGFloat) -> some View {
        let allDay = weekTasks(on: day).filter { $0.isAllDay }
        return HStack(spacing: 2) {
            ForEach(allDay.prefix(2), id: \.id) { task in
                taskChip(task, day: day)
            }
            if allDay.count > 2 {
                Text("+\(allDay.count - 2)")
                    .font(S8Font.mono(9))
                    .foregroundColor(c.fg3)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 3)
        .frame(width: width, height: allDayRowHeight, alignment: .leading)
        .overlay(Rectangle().stroke(c.line, lineWidth: 0.5))
        .clipped()
    }

    /// Handoff 01b: 枠セル。上部に mono BAND ラベル、下にチップ列。
    /// band が非 nil のときだけ BandFramePreferenceKey を発行する
    /// （キャプセル座標は枠セルのフレームのみから作る非対称を維持）。
    private func gridCell(day: Date, title: String, band: Band?, rowIndex: Int,
                          cellTasks: [TaskItem], width: CGFloat, height: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(S8Font.mono(8, .bold))
                .tracking(0.8)
                .foregroundColor(c.fg3)

            ForEach(cellTasks.prefix(5), id: \.id) { task in
                taskChip(task, day: day)
            }
            if cellTasks.count > 5 {
                Text("+\(cellTasks.count - 5)")
                    .font(S8Font.mono(9))
                    .foregroundColor(c.fg3)
            }
            Spacer(minLength: 0)
        }
        .padding(3)
        .frame(width: width, height: height, alignment: .topLeading)
        .background(c.surface)
        .overlay(Rectangle().stroke(c.line, lineWidth: 0.5))
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

    /// Handoff 01b: チップ = カテゴリドット + タイトル + 時刻 mono + STAR。
    /// 完了は取り消し線、色は task.effectiveColor 14% 塗り。
    @ViewBuilder
    private func taskChip(_ task: TaskItem, day: Date) -> some View {
        let taskColor = task.effectiveColor ?? c.accent
        let chip = HStack(spacing: 3) {
            Circle().fill(taskColor).frame(width: 6, height: 6)
            Text(task.title)
                .font(S8Font.jp(9))
                .foregroundColor(c.fg1)
                .lineLimit(1)
                .truncationMode(.tail)
                .strikethrough(task.isDone)
            if !task.isAllDay, let start = task.startDate {
                Text(hhmmLabel(minuteOfDay(of: start, calendar: weekCalendar)))
                    .font(S8Font.mono(7.5))
                    .foregroundColor(c.fg3)
            }
            if task.isImportant {
                Image(systemName: "star.fill")
                    .font(.system(size: 8))
                    .foregroundStyle(c.accent)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 3)
        .padding(.vertical, 1.5)
        .background(taskColor.opacity(0.14))
        .cornerRadius(3)
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
                    onSelectTask: onSelectTask,
                    travelETAs: travelETAs
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
        if weekday == 1 { return c.danger }   // 日
        if weekday == 7 { return c.info }     // 土
        return c.fg2
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
