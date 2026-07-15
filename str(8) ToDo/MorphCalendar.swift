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

extension Notification.Name {
    /// ホイール中心タップ → カレンダーのイベント作成シートを開く。
    static let s8CalAddEvent = Notification.Name("s8.cal.addEvent")
}

// MARK: - スケール定義

enum CalendarScale: Int, CaseIterable, Identifiable {
    case month = 0
    case week  = 1
    case day   = 2
    case year  = 3

    var id: Int { rawValue }
    var label: String {
        switch self {
        case .month: return "月"
        case .week:  return "週"
        case .day:   return "日"
        case .year:  return "年"
        }
    }

    /// ズームイン（月→週→日）。端ではそのまま。年→月へ戻る。
    var zoomedIn: CalendarScale {
        switch self {
        case .year:  return .month
        case .month: return .week
        case .week:  return .day
        case .day:   return .day
        }
    }
    /// ズームアウト（日→週→月→年）。
    var zoomedOut: CalendarScale {
        switch self {
        case .day:   return .week
        case .week:  return .month
        case .month: return .year
        case .year:  return .year
        }
    }
}

/// matchedGeometryEffect 用の安定キー（その日の yyyymmdd）。
func dayKey(_ date: Date, _ cal: Calendar = .current) -> Int {
    let c = cal.dateComponents([.year, .month, .day], from: date)
    return (c.year ?? 0) * 10000 + (c.month ?? 0) * 100 + (c.day ?? 0)
}

// MARK: - ルート

struct CalendarRootView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.colorScheme) private var scheme
    private var c: S8Palette { S8Palette.of(scheme) }
    @State private var eventKit = EventKitService()

    @State private var scale: CalendarScale = .month
    @State private var selectedDate: Date = Calendar.current.startOfDay(for: .now)
    @Namespace private var morph
    /// Handoff 00c: ホイール MODE ダイヤルと連動。
    @AppStorage("wheel.cal.mode") private var wheelCalMode = 0

    @State private var selectedTask: TaskItem?
    @State private var showSettings = false
    @State private var showYear = false
    @State private var showMoneyBreakdown = false
    @State private var showComposer = false
    @State private var categoryFilter: Set<UUID>? = nil
    @Query(sort: \Category.name) private var categories: [Category]

    private let cal = Calendar.current
    private let morphAnimation: Animation = .spring(response: 0.45, dampingFraction: 0.82)

    var body: some View {
        let c = self.c
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                ForEach(CalendarScale.allCases) { s in
                    S8Chip(s.label, selected: scale == s, action: { zoom(to: s) })
                }
                Spacer()
                ZStack(alignment: .topTrailing) {
                    S8IconButton(icon: "filter", accent: categoryFilter != nil) {
                        // Talk 流儀：ホイールを差替えるオーバレイを提示（シートは使わない）。
                        S8WheelOverlayPresenter.shared.present(
                            items: filterItems,
                            selectedIndex: currentFilterIndex,
                            onSelect: { applyFilterSelection($0) }
                        )
                    }
                    .accessibilityLabel("カテゴリフィルター")
                    if let filter = categoryFilter, !filter.isEmpty {
                        Text("\(filter.count)")
                            .font(S8Font.mono(9, .bold))
                            .foregroundColor(c.onAccent)
                            .frame(width: 16, height: 16)
                            .background(Circle().fill(c.accent))
                            .offset(x: 2, y: -2)
                    }
                }
                // 詳細設定（マイ時間割・曜日割当・特定日差替）は Calendar タブへ集約（2026-07-14）。
                S8IconButton(icon: "settings") { showSettings = true }
                    .accessibilityLabel("カレンダー詳細設定")
            }
            .padding(.horizontal, 24).padding(.top, 12).padding(.bottom, 8)

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
                case .year:
                    // Handoff 00c: 年ビューはホイール MODE の一員としてメインペイン化。
                    YearView()
                        .transition(.opacity)
                }
            }
        }
        .background(c.paper.ignoresSafeArea())
        .sheet(item: $selectedTask) { task in
            TaskDetailView(task: task)
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
        .sheet(isPresented: $showComposer) {
            EventComposerView(initialStart: selectedDate)
        }
        .task {
            if eventKit.authState == .authorized {
                eventKit.sync(into: context)
                eventKit.observeChanges(into: context)
            }
        }
        // ホイール MODE ダイヤルからのモード切替を購読（現状は wheel が中心作成発火に切替済で MODE ホイールは開かないが、
        // 将来復活時のために互換）。
        .onAppear {
            if let s = CalendarScale(rawValue: wheelCalMode) { scale = s }
        }
        .onChange(of: wheelCalMode) { _, new in
            if let s = CalendarScale(rawValue: new) {
                withAnimation(morphAnimation) { scale = s }
            }
        }
        .onChange(of: scale) { _, new in
            if wheelCalMode != new.rawValue { wheelCalMode = new.rawValue }
        }
        // 中心タップ → イベント作成
        .onReceive(NotificationCenter.default.publisher(for: .s8CalAddEvent)) { _ in
            showComposer = true
        }
    }

    // MARK: - フィルタホイール（カテゴリ単一選択）

    private var filterItems: [S8WheelFilterItem] {
        var items = [S8WheelFilterItem(id: "all", icon: "filter", label: "すべて")]
        for cat in categories {
            // ユーザーが設定したアイコン（例 "tag.fill"）をそのまま渡す。s8Symbol は `.` 含みを SF Symbol 名として素通しする。
            items.append(S8WheelFilterItem(id: cat.id.uuidString, icon: cat.symbolName, label: cat.name))
        }
        return items
    }

    private var currentFilterIndex: Int {
        guard let filter = categoryFilter, filter.count == 1, let id = filter.first else { return 0 }
        if let i = categories.firstIndex(where: { $0.id == id }) { return i + 1 }
        return 0
    }

    private func applyFilterSelection(_ index: Int) {
        if index == 0 || index > categories.count {
            categoryFilter = nil
        } else {
            let cat = categories[index - 1]
            categoryFilter = Set([cat.id])
        }
    }

    private func zoom(to target: CalendarScale) {
        guard target != scale else { return }
        withAnimation(morphAnimation) { scale = target }
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

    @Environment(\.colorScheme) private var scheme
    private var c: S8Palette { S8Palette.of(scheme) }
    private var dayNumber: String { "\(Calendar.current.component(.day, from: date))" }
    private var weekday: Int { Calendar.current.component(.weekday, from: date) }

    private var numberColor: Color {
        if isToday { return c.accent }
        if weekday == 1 { return c.danger }
        if weekday == 7 { return c.info }
        return c.fg1
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
                    .font(S8Font.mono(13.5))
                    .foregroundStyle(c.ok)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: scale == .month ? 52 : 72)
        .background {
            RoundedRectangle(cornerRadius: S8Radius.lg, style: .continuous)
                .fill(isToday ? c.accentWash : c.surface2)
        }
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: S8Radius.lg, style: .continuous)
                    .strokeBorder(c.accent, lineWidth: 2)
            }
        }
        .opacity(inFocusMonth ? 1 : 0.35)
        .matchedGeometryEffect(id: dayKey(date), in: morph)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(dayAccessibilityLabel)
    }

    private var dayAccessibilityLabel: String {
        var label = "\(dayNumber)日"
        if isToday { label += " 今日" }
        if !dots.isEmpty { label += " \(dots.count)件のタスク" }
        if let amountText { label += " \(amountText)" }
        return label
    }
}

// MARK: - データ補助

/// 指定日のタスクのカテゴリ色（最大3）。フィルタを適用。
func dotColors(for day: Date, in tasks: [TaskItem], categoryFilter: Set<UUID>? = nil, cal: Calendar = .current, fallback: Color) -> [Color] {
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
    return filtered.prefix(3).map { $0.category.map { Color(hex: $0.colorHex) } ?? fallback }
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
    @Environment(\.colorScheme) private var scheme
    private var c: S8Palette { S8Palette.of(scheme) }
    private let cal = Calendar.current
    private let weekdaySymbols = ["日", "月", "火", "水", "木", "金", "土"]

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 0) {
                ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { idx, sym in
                    Text(sym)
                        .font(.caption2)
                        .foregroundStyle(idx == 0 ? c.danger : (idx == 6 ? c.info : c.fg3))
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
                            .foregroundColor(c.fg3)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(c.fg3)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(c.surface2)
                .clipShape(RoundedRectangle(cornerRadius: S8Radius.md))
                .onTapGesture { showMoneyBreakdown = true }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("支出サマリ サブスク \(currencyText(monthlyStat.subscriptionSpend)) 支出 \(currencyText(monthlyStat.totalSpend))")
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
                        dots: dotColors(for: day, in: tasks, categoryFilter: categoryFilter, fallback: c.accent),
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
    @Environment(\.colorScheme) private var scheme
    private let cal = Calendar.current

    var body: some View {
        let c = S8Palette.of(scheme)
        VStack(spacing: 0) {
            DayBlock(
                date: date,
                scale: .day,
                isSelected: true,
                isToday: cal.isDateInToday(date),
                inFocusMonth: true,
                dots: dotColors(for: date, in: tasks, categoryFilter: categoryFilter, fallback: c.accent),
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
