import SwiftUI
import SwiftData

struct WeekView: View {
    @Binding var selectedDate: Date
    var morph: Namespace.ID? = nil
    var categoryFilter: Set<UUID>? = nil
    var onSelectTask: ((TaskItem) -> Void)? = nil
    var onPickDay: (Date) -> Void

    @Query private var tasks: [TaskItem]
    @Query private var fixedSchedules: [FixedSchedule]

    @AppStorage(AppSettingsKey.weekStartMinutes) private var weekStartMinutes: Int = 0
    @AppStorage(AppSettingsKey.weekEndMinutes) private var weekEndMinutes: Int = 1440
    @AppStorage(AppSettingsKey.weekBandIntervalHours) private var weekBandIntervalHours: Int = 3

    private let weekCalendar: Calendar = {
        var c = Calendar.current
        c.firstWeekday = 1
        return c
    }()

    // すべてのマス目で共有する寸法（これでヘッダ/時間ラベル/イベントのマスが完全一致する）
    private let timeColWidth: CGFloat = 40
    private let headerHeight: CGFloat = 60
    private let bandHeight: CGFloat = 56
    private let dayWidth: CGFloat = 96
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
        return days
    }

    private var weekBands: [WeekBand] {
        makeWeekBands(startMinute: weekStartMinutes, endMinute: weekEndMinutes, intervalMinutes: weekBandIntervalHours * 60)
    }

    private func isToday(_ date: Date) -> Bool { weekCalendar.isDateInToday(date) }

    private func dayString(_ date: Date) -> String {
        let weekday = weekCalendar.component(.weekday, from: date)
        return ["日", "月", "火", "水", "木", "金", "土"][weekday - 1]
    }

    private func dayNumber(_ date: Date) -> Int { weekCalendar.component(.day, from: date) }

    private func weekdayColor(_ date: Date) -> Color {
        let weekday = weekCalendar.component(.weekday, from: date)
        if weekday == 1 { return .red }
        if weekday == 7 { return .blue }
        return .gray
    }

    private func tasksForDayAndBand(_ date: Date, band: WeekBand) -> [TaskItem] {
        let targetKey = dayKey(date, weekCalendar)
        return tasks.filter { task in
            guard task.phase != .someday else { return false }
            guard let startDate = task.startDate else { return false }
            guard dayKey(startDate, weekCalendar) == targetKey else { return false }
            if let catFilter = categoryFilter {
                if let taskCat = task.category {
                    guard catFilter.contains(taskCat.id) else { return false }
                } else {
                    return false
                }
            }
            if task.isAllDay { return true }
            let startMinute = weekCalendar.component(.hour, from: startDate) * 60 + weekCalendar.component(.minute, from: startDate)
            return startMinute >= band.startMinute && startMinute < band.endMinute
        }
    }

    private func fixedScheduleColorForDayAndBand(_ date: Date, band: WeekBand) -> Color? {
        let zeroBasedWeekday = weekCalendar.component(.weekday, from: date) - 1
        let bandStartSeconds = band.startMinute * 60
        let bandEndSeconds = band.endMinute * 60
        for fs in fixedSchedules {
            guard fs.weekdays.contains(zeroBasedWeekday) else { continue }
            if fs.startSeconds < bandEndSeconds && fs.endSeconds > bandStartSeconds {
                return Color(hex: fs.colorHex)
            }
        }
        return nil
    }

    var body: some View {
        // 縦スクロール：表全体が縦に伸びてもタブバーに被らずスクロールする。
        // 左の時間列と日カラムは同じ縦スクロール内にあるので行は常に揃う。
        ScrollView(.vertical, showsIndicators: true) {
            HStack(alignment: .top, spacing: 0) {
                // 左固定の時間ラベル列（横スクロールしない）
                VStack(spacing: 0) {
                    cell(width: timeColWidth, height: headerHeight) { EmptyView() }
                    ForEach(weekBands, id: \.id) { band in
                        cell(width: timeColWidth, height: bandHeight) {
                            Text(band.label)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .minimumScaleFactor(0.7)
                                .padding(.horizontal, 2)
                        }
                    }
                }

                // 日カラムだけ横スクロール（ヘッダ＋バンドが1列で一緒に動く）
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 0) {
                        ForEach(weekDays, id: \.timeIntervalSinceReferenceDate) { day in
                            VStack(spacing: 0) {
                                dayHeaderCell(day)
                                ForEach(weekBands, id: \.id) { band in
                                    bandCell(day: day, band: band)
                                }
                            }
                        }
                    }
                }
            }
            .padding(.bottom, 8)
        }
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - セル部品（すべて固定サイズ＝マス目が揃う）

    /// 固定サイズの枠つきセル。中身は内側に収める（外側サイズは width×height で固定）。
    private func cell<Content: View>(width: CGFloat, height: CGFloat, @ViewBuilder content: () -> Content) -> some View {
        content()
            .frame(width: width, height: height, alignment: .center)
            .border(gridLine, width: 0.5)
    }

    private func dayHeaderCell(_ day: Date) -> some View {
        let header = VStack(spacing: 4) {
            HStack(spacing: 3) {
                Image(systemName: "cloud.sun")
                    .font(.system(size: 12))
                    .foregroundStyle(.gray.opacity(0.5))
                Text(dayString(day))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(isToday(day) ? Color.accentColor : weekdayColor(day))
            }
            Text("\(dayNumber(day))")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(isToday(day) ? Color.accentColor : Color.primary)
        }
        .frame(width: dayWidth, height: headerHeight)
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

    private func bandCell(day: Date, band: WeekBand) -> some View {
        let cellTasks = tasksForDayAndBand(day, band: band)
        return VStack(alignment: .leading, spacing: 2) {
            ForEach(cellTasks.prefix(3), id: \.id) { task in
                taskChip(task)
            }
            if cellTasks.count > 3 {
                Text("+\(cellTasks.count - 3)")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 3)   // パディングは frame の内側（外側サイズは変えない）
        .padding(.vertical, 3)
        .frame(width: dayWidth, height: bandHeight, alignment: .topLeading)
        .background(
            ZStack {
                Color.gray.opacity(0.05)
                if let fsColor = fixedScheduleColorForDayAndBand(day, band: band) {
                    fsColor.opacity(0.12)
                }
            }
        )
        .border(gridLine, width: 0.5)
        .clipped()
    }

    @ViewBuilder
    private func taskChip(_ task: TaskItem) -> some View {
        let chip = HStack(spacing: 3) {
            Circle().fill(task.effectiveColor).frame(width: 7, height: 7)
            Text(task.title)
                .font(.system(size: 10))
                .lineLimit(1)
                .truncationMode(.tail)
            if task.isImportant {
                Image(systemName: "star.fill")
                    .font(.system(size: 7))
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

        if let morph {
            chip.matchedGeometryEffect(id: "evt-\(task.id.uuidString)", in: morph)
        } else {
            chip
        }
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
