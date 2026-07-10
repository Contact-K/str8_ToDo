//
//  MorphCalendar.swift
//  str(8) ToDo
//
//  カレンダーの月⇄週⇄日 Morph 遷移（P1 看板機能）。
//
//  設計（企画書 2026-07-02 準拠）:
//  - トリガーはピル型セレクター＋セル/ヘッダの直接タップに一本化（ピンチは廃止）。
//  - 各スケールで「日ブロック」を matchedGeometryEffect で共有し、
//    共通する日付セルが位置・サイズを保ったままモーフする。
//

import SwiftUI
import SwiftData

// MARK: - スケール定義

enum CalendarScale: Int, CaseIterable, Identifiable {
    case month = 0
    case week  = 1
    case day   = 2

    var id: Int { rawValue }
    var label: String {
        switch self {
        case .month: return "月"
        case .week:  return "週"
        case .day:   return "日"
        }
    }

    /// ズームイン（月→週→日）。端ではそのまま。
    var zoomedIn: CalendarScale { CalendarScale(rawValue: min(rawValue + 1, CalendarScale.day.rawValue))! }
    /// ズームアウト（日→週→月）。
    var zoomedOut: CalendarScale { CalendarScale(rawValue: max(rawValue - 1, CalendarScale.month.rawValue))! }
}

/// matchedGeometryEffect 用の安定キー（その日の yyyymmdd）。
func dayKey(_ date: Date, _ cal: Calendar = .current) -> Int {
    let c = cal.dateComponents([.year, .month, .day], from: date)
    return (c.year ?? 0) * 10000 + (c.month ?? 0) * 100 + (c.day ?? 0)
}

// MARK: - ルート

struct CalendarRootView: View {
    @Environment(\.modelContext) private var context
    @State private var eventKit = EventKitService()

    @State private var scale: CalendarScale = .month
    @State private var selectedDate: Date = Calendar.current.startOfDay(for: .now)
    @Namespace private var morph

    @State private var selectedTask: TaskItem?
    @State private var showSettings = false
    @State private var showYear = false
    @State private var showMoneyBreakdown = false
    @State private var categoryFilter: Set<UUID>? = nil
    @Query(sort: \Category.name) private var categories: [Category]

    private let cal = Calendar.current
    private let morphAnimation: Animation = .spring(response: 0.45, dampingFraction: 0.82)

    var body: some View {
        NavigationStack {
            ZStack {
                switch scale {
                case .month:
                    MonthGrid(selectedDate: $selectedDate, morph: morph, categoryFilter: categoryFilter, showMoneyBreakdown: $showMoneyBreakdown) { day in
                        selectedDate = cal.startOfDay(for: day)
                        zoom(to: .day)
                    } onLongLook: { day in
                        selectedDate = cal.startOfDay(for: day)
                        zoom(to: .week)
                    }
                    .transition(.opacity)
                case .week:
                    WeekView(selectedDate: $selectedDate, morph: morph, categoryFilter: categoryFilter, onSelectTask: { task in
                        selectedTask = task
                    }, onPickDay: { day in
                        selectedDate = cal.startOfDay(for: day)
                        zoom(to: .day)
                    }, onOpenSettings: {
                        showSettings = true
                    })
                    .transition(.opacity)
                case .day:
                    DayPane(date: $selectedDate, morph: morph, categoryFilter: categoryFilter, onSelectTask: { task in
                        selectedTask = task
                    })
                        .transition(.opacity)
                }
            }
            .navigationTitle(titleText)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .sheet(item: $selectedTask) { task in
                NavigationStack {
                    TaskDetailView(task: task)
                }
            }
            .sheet(isPresented: $showSettings) {
                NavigationStack {
                    CalendarSettingsView()
                }
            }
            .sheet(isPresented: $showYear) {
                NavigationStack {
                    YearView()
                }
            }
            .sheet(isPresented: $showMoneyBreakdown) {
                NavigationStack {
                    MoneyBreakdownView(month: selectedDate)
                }
            }
            .task {
                if eventKit.authState == .authorized {
                    eventKit.sync(into: context)
                    eventKit.observeChanges(into: context)
                }
            }
        }
    }

    private func zoom(to target: CalendarScale) {
        guard target != scale else { return }
        withAnimation(morphAnimation) { scale = target }
    }

    // MARK: トリガー: ピル＋ツールバー（＋セル/ヘッダの直接タップ）

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            Picker("表示", selection: pillBinding) {
                ForEach(CalendarScale.allCases) { s in
                    Text(s.label).tag(s)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 150)
        }
        ToolbarItem(placement: .topBarTrailing) {
            HStack(spacing: 12) {
                Menu {
                    Button("すべて表示") {
                        categoryFilter = nil
                    }
                    if !categories.isEmpty {
                        Divider()
                    }
                    ForEach(categories) { cat in
                        Button(action: {
                            if categoryFilter == nil {
                                categoryFilter = Set([cat.id])
                            } else {
                                if categoryFilter!.contains(cat.id) {
                                    categoryFilter!.remove(cat.id)
                                    if categoryFilter!.isEmpty {
                                        categoryFilter = nil
                                    }
                                } else {
                                    categoryFilter!.insert(cat.id)
                                }
                            }
                        }) {
                            HStack {
                                Circle()
                                    .fill(Color(hex: cat.colorHex))
                                    .frame(width: 12, height: 12)
                                Text(cat.name)
                                Spacer()
                                if let filter = categoryFilter, filter.contains(cat.id) {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    ZStack(alignment: .topTrailing) {
                        Image(systemName: categoryFilter == nil ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                        if let filter = categoryFilter, !filter.isEmpty {
                            Text("\(filter.count)")
                                .font(.caption2)
                                .fontWeight(.bold)
                                .foregroundStyle(.white)
                                .frame(width: 18, height: 18)
                                .background(Circle().fill(Color.accentColor))
                                .offset(x: 6, y: -6)
                        }
                    }
                }
                Button {
                    showYear = true
                } label: {
                    Image(systemName: "chart.bar.xaxis")
                }
                Button("今日") {
                    withAnimation(morphAnimation) {
                        selectedDate = cal.startOfDay(for: .now)
                    }
                }
                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "gearshape")
                }
            }
        }
    }

    private var pillBinding: Binding<CalendarScale> {
        Binding(get: { scale }, set: { zoom(to: $0) })
    }

    // MARK: タイトル

    private var titleText: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ja_JP")
        switch scale {
        case .month: f.dateFormat = "yyyy年 M月"
        case .week:  f.dateFormat = "yyyy年 M月 '第'W週"
        case .day:   f.dateFormat = "M月d日 (E)"
        }
        return f.string(from: selectedDate)
    }
}

// MARK: - 共有: 日ブロック

/// 全スケールで共有する「日」の箱。matchedGeometryEffect で位置・サイズをモーフさせる。
struct DayBlock: View {
    let date: Date
    let scale: CalendarScale
    let isSelected: Bool
    let isToday: Bool
    let inFocusMonth: Bool
    let dots: [Color]
    let morph: Namespace.ID
    /// 支出額の短縮表示（例 "¥1490"）。nil なら非表示。let+初期値は memberwise init から消えるので var。
    var amountText: String? = nil

    private var dayNumber: String { "\(Calendar.current.component(.day, from: date))" }
    private var weekday: Int { Calendar.current.component(.weekday, from: date) }

    private var numberColor: Color {
        if isToday { return .accentColor }
        if weekday == 1 { return .red }
        if weekday == 7 { return .blue }
        return .primary
    }

    var body: some View {
        VStack(spacing: 4) {
            Text(dayNumber)
                .font(scale == .month ? .callout : .title3)
                .fontWeight(isToday ? .bold : .regular)
                .foregroundStyle(numberColor)

            HStack(spacing: 3) {
                ForEach(Array(dots.enumerated()), id: \.offset) { _, c in
                    Circle().fill(c).frame(width: 5, height: 5)
                }
            }
            .frame(height: 6)

            if let amountText {
                Text(amountText)
                    .font(.caption2)
                    .foregroundStyle(.green)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: scale == .month ? 52 : 72)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isToday ? Color.accentColor.opacity(0.16) : Color(.secondarySystemBackground))
        }
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.accentColor, lineWidth: 2)
            }
        }
        .opacity(inFocusMonth ? 1 : 0.35)
        .matchedGeometryEffect(id: dayKey(date), in: morph)
    }
}

// MARK: - データ補助

/// 指定日のタスクのカテゴリ色（最大3）。フィルタを適用。
func dotColors(for day: Date, in tasks: [TaskItem], categoryFilter: Set<UUID>? = nil, cal: Calendar = .current) -> [Color] {
    let dayTasks = tasks.filter {
        guard let s = $0.startDate else { return false }
        return cal.isDate(s, inSameDayAs: day)
    }
    let filtered: [TaskItem]
    if let filter = categoryFilter {
        filtered = dayTasks.filter { task in
            guard let catID = task.category?.id else { return false }
            return filter.contains(catID)
        }
    } else {
        filtered = dayTasks
    }
    return filtered.prefix(3).map { $0.category.map { Color(hex: $0.colorHex) } ?? .accentColor }
}

// MARK: - 月グリッド

struct MonthGrid: View {
    @Binding var selectedDate: Date
    var morph: Namespace.ID
    var categoryFilter: Set<UUID>? = nil
    @Binding var showMoneyBreakdown: Bool
    var onPickDay: (Date) -> Void
    var onLongLook: (Date) -> Void

    @Query private var tasks: [TaskItem]
    @Query private var moneystats: [MonthMoneyStat]
    @Environment(\.modelContext) var modelContext
    private let cal = Calendar.current
    private let weekdaySymbols = ["日", "月", "火", "水", "木", "金", "土"]

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 0) {
                ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { idx, sym in
                    Text(sym)
                        .font(.caption2)
                        .foregroundStyle(idx == 0 ? .red : (idx == 6 ? .blue : .secondary))
                        .frame(maxWidth: .infinity)
                }
            }

            // 月別支出ヘッダ
            if let monthlyStat = moneystats.first(where: { stat in
                cal.isDate(stat.month, equalTo: selectedDate, toGranularity: .month)
            }), monthlyStat.totalSpend > 0 {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("サブスク \(currencyText(monthlyStat.subscriptionSpend)) ・ 支出 \(currencyText(monthlyStat.totalSpend))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(Color(.secondarySystemBackground))
                .cornerRadius(6)
                .onTapGesture { showMoneyBreakdown = true }
            }

            let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)
            let spendByDay = dailySpends()
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(monthDays(), id: \.self) { day in
                    DayBlock(
                        date: day,
                        scale: .month,
                        isSelected: cal.isDate(day, inSameDayAs: selectedDate),
                        isToday: cal.isDateInToday(day),
                        inFocusMonth: cal.isDate(day, equalTo: selectedDate, toGranularity: .month),
                        dots: dotColors(for: day, in: tasks, categoryFilter: categoryFilter),
                        morph: morph,
                        amountText: spendByDay[day].map { "¥\(NSDecimalNumber(decimal: $0).intValue)" }
                    )
                    .onTapGesture { onPickDay(day) }
                    .onLongPressGesture { onLongLook(day) }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .onAppear {
            MoneyStats.recompute(month: selectedDate, context: modelContext)
        }
        .onChange(of: selectedDate) {
            MoneyStats.recompute(month: selectedDate, context: modelContext)
        }
    }

    /// フォーカス月の日別支出（startOfDay がキー）。
    private func dailySpends() -> [Date: Decimal] {
        var result: [Date: Decimal] = [:]
        MoneyStats.forEachOccurrence(tasks: tasks, month: selectedDate) { day, task in
            result[day, default: 0] += task.amount ?? 0
        }
        return result
    }

    /// 6週 42 マス（週頭の日曜開始）。
    private func monthDays() -> [Date] {
        guard
            let monthInterval = cal.dateInterval(of: .month, for: selectedDate),
            let firstWeek = cal.dateInterval(of: .weekOfMonth, for: monthInterval.start)
        else { return [] }
        var days: [Date] = []
        var cursor = firstWeek.start
        for _ in 0..<42 {
            days.append(cursor)
            cursor = cal.date(byAdding: .day, value: 1, to: cursor)!
        }
        return days
    }
}

// MARK: - 日ペイン

/// 日スケール：選択日の大ブロック（モーフ着地点）＋ 既存の時間軸タイムライン。
struct DayPane: View {
    @Binding var date: Date
    var morph: Namespace.ID
    var categoryFilter: Set<UUID>? = nil
    var onSelectTask: ((TaskItem) -> Void)? = nil

    @Query private var tasks: [TaskItem]
    private let cal = Calendar.current

    var body: some View {
        VStack(spacing: 0) {
            DayBlock(
                date: date,
                scale: .day,
                isSelected: true,
                isToday: cal.isDateInToday(date),
                inFocusMonth: true,
                dots: dotColors(for: date, in: tasks, categoryFilter: categoryFilter),
                morph: morph
            )
            .frame(maxWidth: 120)
            .padding(.vertical, 8)

            DayView(date: $date, morph: morph, categoryFilter: categoryFilter, onSelectTask: onSelectTask)
        }
    }
}

#Preview {
    CalendarRootView()
        .modelContainer(PreviewData.container)
}
