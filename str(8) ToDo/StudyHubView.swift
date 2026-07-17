//
//  StudyHubView.swift
//  str8ToDo
//
//  勉強＝振り返りハブ。ヒーローカード（persona + goal + 3-stat）+ 目標バー + 12週ヒートマップ + 7日バー。
//  タブ切替は廃止し 1 スクロールに統合（デザイン B1）。共有カードは B2 の StudyShareCard を ShareLink で書き出す。
//

import SwiftUI
import SwiftData

extension Notification.Name {
    /// Handoff 00c: 勉強タブ ホイール中心タップ→科目追加シート
    static let s8StudyAddSubject = Notification.Name("s8.study.addSubject")
}

// MARK: - Persona 判定

enum StudyPersona {
    case earlyBird       // 朝型
    case afternoon       // 午後型
    case nightOwl        // 夜型
    case allDay          // 終日均等
    case unknown         // データ不足

    var name: String {
        switch self {
        case .earlyBird:  return "朝型集中タイプ"
        case .afternoon:  return "午後の追い込み型"
        case .nightOwl:   return "夜に伸びるタイプ"
        case .allDay:     return "終日均等タイプ"
        case .unknown:    return "計測中"
        }
    }

    /// Lucide 相当のアイコン名。左のバッジ内に表示。
    var iconName: String {
        switch self {
        case .earlyBird:  return "sunrise"
        case .afternoon:  return "sun"
        case .nightOwl:   return "moon"
        case .allDay:     return "layers"
        case .unknown:    return "hourglass"
        }
    }

    /// Assets.xcassets に格納されたイラストの名前。
    var illustrationName: String {
        switch self {
        case .earlyBird:  return "study-achieve"
        case .afternoon:  return "study-think"
        case .nightOwl:   return "study-focus"
        case .allDay:     return "study-rest"
        case .unknown:    return "study-think"
        }
    }

    /// 直近 30 日のセッション start 時刻から最頻帯を判定。
    static func from(sessions: [FocusSession], now: Date = .now, calendar: Calendar = .current) -> StudyPersona {
        let cutoff = calendar.date(byAdding: .day, value: -30, to: now) ?? now
        let recent = sessions.filter { $0.start >= cutoff }
        var buckets: [StudyPersona: Int] = [.earlyBird: 0, .afternoon: 0, .nightOwl: 0]
        for s in recent {
            let secs = max(0, min(Int(s.end.timeIntervalSince(s.start)), 24 * 3600))
            guard secs > 0 else { continue }
            let h = calendar.component(.hour, from: s.start)
            switch h {
            case 5..<11:  buckets[.earlyBird, default: 0] += secs
            case 11..<18: buckets[.afternoon, default: 0] += secs
            default:      buckets[.nightOwl, default: 0] += secs
            }
        }
        let total = buckets.values.reduce(0, +)
        guard total >= 3600 else { return .unknown }
        if let (top, mins) = buckets.max(by: { $0.value < $1.value }), mins * 10 >= total * 5 {
            return top
        }
        return .allDay
    }
}

// MARK: - StudyHubView

struct StudyHubView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.colorScheme) private var scheme
    private var c: S8Palette { S8Palette.of(scheme) }
    @Query private var sessions: [FocusSession]
    @Query private var subjects: [Subject]

    @State private var showAddSubjectSheet = false
    @State private var shareImage: UIImage?

    private let cal = Calendar.current

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                VStack(spacing: 0) {
                    if sessions.isEmpty {
                        emptyState(icon: "hourglass", title: "集中セッションがありません",
                                   detail: "タイマーから集中セッションを記録しましょう")
                    } else {
                        heroCard
                            .padding(.horizontal, 24).padding(.top, 4)

                        if !subjects.isEmpty {
                            sectionHeader("GOALS", jp: "科目別 目標進捗")
                            subjectGoalBars
                        }

                        sectionHeader("HEATMAP", jp: "集中ヒートマップ", trailing: "12 WEEKS")
                        heatmap12Weeks
                            .padding(.horizontal, 24)

                        sectionHeader("LAST 7 DAYS", jp: "最近7日間")
                        weeklyChart
                    }
                    Color.clear.frame(height: 32)
                }
            }
        }
        .sheet(isPresented: $showAddSubjectSheet) {
            AddSubjectSheet(isPresented: $showAddSubjectSheet, context: context)
        }
        .onReceive(NotificationCenter.default.publisher(for: .s8StudyAddSubject)) { _ in
            showAddSubjectSheet = true
        }
    }

    // MARK: - Header (週レンジ + 共有)

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 3) {
                Text("勉強").font(S8Font.jp(22, .bold)).foregroundColor(c.fg1)
                Text("this week · \(Self.weekRangeText(now: .now, calendar: cal))")
                    .font(S8Font.mono(10)).tracking(1.6).foregroundColor(c.fg3)
            }
            Spacer()
            if !sessions.isEmpty, let img = shareImage {
                ShareLink(item: Image(uiImage: img),
                          preview: SharePreview("集中の振り返り", image: Image(uiImage: img))) {
                    S8Icon(name: "share", size: 18, color: c.fg2)
                        .frame(width: 40, height: 40)
                        .accessibilityLabel("共有カードを書き出す")
                }
            } else if !sessions.isEmpty {
                Button(action: renderShareImage) {
                    S8Icon(name: "share", size: 18, color: c.fg2).frame(width: 40, height: 40)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("共有カードを生成")
            }
        }
        .padding(.horizontal, 24).padding(.top, 14).padding(.bottom, 10)
    }

    /// ImageRenderer で B2 共有カードを PNG 化 → `shareImage` に保存。
    @MainActor
    private func renderShareImage() {
        let card = StudyShareCard(
            weekRange: Self.weekRangeText(now: .now, calendar: cal),
            focusSeconds: weeklyFocusSeconds,
            goalMinutes: totalWeeklyGoalMinutes,
            persona: persona,
            streakDays: streakDays,
            oneLiner: heroOneLiner(remainingMinutes: remainingWeeklyMinutes)
        )
        .environment(\.colorScheme, scheme)
        let renderer = ImageRenderer(content: card)
        renderer.scale = 3
        shareImage = renderer.uiImage
    }

    // MARK: - Hero card (persona + goal + one-liner + 3-stat)

    private var heroCard: some View {
        let focus = weeklyFocusSeconds
        let goalM = totalWeeklyGoalMinutes
        let progress = goalM > 0 ? min(Double(focus / 60) / Double(goalM), 1.0) : 0
        let pct = Int((progress * 100).rounded())

        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: S8Radius.lg).fill(c.surface)
            RoundedRectangle(cornerRadius: S8Radius.lg).strokeBorder(c.lineStrong, lineWidth: 1)

            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 6) {
                    Image(persona.illustrationName)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 108, height: 108)
                        .padding(.leading, -10).padding(.trailing, -2).padding(.top, -4)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("FOCUS PERSONA").font(S8Font.mono(9)).tracking(1.6).foregroundColor(c.fg3)
                        Text(persona.name).font(S8Font.jp(14, .bold)).foregroundColor(c.fg1)
                            .lineLimit(1).minimumScaleFactor(0.85)
                        Text(heroOneLiner(remainingMinutes: remainingWeeklyMinutes))
                            .font(S8Font.jp(13, .bold)).foregroundColor(c.accentInk)
                            .lineLimit(3).fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 6)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                // Goal progress bar
                VStack(spacing: 6) {
                    HStack(alignment: .lastTextBaseline) {
                        Text("GOAL \(goalM > 0 ? "\(goalM / 60)H" : "未設定")")
                            .font(S8Font.mono(8.5)).tracking(1.2).foregroundColor(c.fg3)
                        Spacer()
                        Text(hmText(TimeInterval(focus)))
                            .font(S8Font.mono(12, .bold)).foregroundColor(c.fg1)
                        Text("/ \(pct)%")
                            .font(S8Font.mono(9)).foregroundColor(c.fg3)
                    }
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(c.surface2).frame(height: 5)
                            Capsule().fill(c.accent).frame(width: geo.size.width * progress, height: 5)
                        }
                    }
                    .frame(height: 5)
                }
                .padding(.top, 14)

                // 3-stat panel
                HStack(spacing: 1) {
                    statCell(value: "\(sessionCountThisWeek)", label: "セッション", accent: false)
                    statCell(value: remainingSessionsText, label: "残り", accent: remainingWeeklyMinutes > 0)
                    statCell(value: "\(streakDays)", suffix: "d", label: "連続", accent: false)
                }
                .background(c.line)
                .overlay(RoundedRectangle(cornerRadius: S8Radius.md).stroke(c.line, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: S8Radius.md))
                .padding(.top, 16)
            }
            .padding(20)
        }
    }

    /// ドット環 + 中心にペルソナアイコンのバッジ。progress は 0..1。
    private func personaBadge(progress: Double) -> some View {
        let filled = 18
        let onCount = Int(Double(filled) * progress)
        return ZStack {
            ForEach(0..<filled, id: \.self) { i in
                let angle = Angle.degrees(-90 + Double(i) * 360.0 / Double(filled))
                Circle()
                    .fill(i < onCount ? c.accent : c.surface2)
                    .frame(width: 5, height: 5)
                    .offset(x: 40 * cos(angle.radians), y: 40 * sin(angle.radians))
            }
            Circle().fill(c.surface).frame(width: 60, height: 60)
                .overlay(Circle().strokeBorder(c.lineStrong, lineWidth: 1))
            S8Icon(name: persona.iconName, size: 22, color: c.accentInk)
        }
    }

    /// 3-stat セルの1つ。
    private func statCell(value: String, suffix: String? = nil, label: String, accent: Bool) -> some View {
        VStack(spacing: 2) {
            HStack(alignment: .lastTextBaseline, spacing: 1) {
                Text(value).font(S8Font.mono(16, .bold))
                    .foregroundColor(accent ? c.accentInk : c.fg1)
                if let suffix {
                    Text(suffix).font(S8Font.mono(9)).foregroundColor(c.fg3)
                }
            }
            Text(label).font(S8Font.mono(8)).tracking(1.2).foregroundColor(c.fg3)
        }
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(c.surface)
    }

    // MARK: - Subject goal bars

    private var subjectGoalBars: some View {
        VStack(spacing: 16) {
            ForEach(subjects.sorted { $0.name < $1.name }, id: \.id) { s in
                let seconds = weeklySubjectSeconds[s.id] ?? 0
                let goalM = max(s.weeklyGoalMinutes, 1)
                let progress = min(Double(seconds / 60) / Double(goalM), 1.0)
                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        Circle().fill(Color(hex: s.colorHex)).frame(width: 9, height: 9)
                        Text(s.name).font(S8Font.jp(13.5, .medium)).foregroundColor(c.fg1)
                        Spacer()
                        Text("\(seconds / 60) / \(s.weeklyGoalMinutes)分")
                            .font(S8Font.mono(10.5)).foregroundColor(c.fg3)
                    }
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(c.surface2).frame(height: 5)
                            Capsule().fill(c.accent).frame(width: geo.size.width * progress, height: 5)
                        }
                    }
                    .frame(height: 5)
                }
            }
        }
        .padding(.horizontal, 24)
    }

    // MARK: - 12週ヒートマップ

    private var heatmap12Weeks: some View {
        let secs = focusSecondsByDay
        // 直近 12 週の全日を横方向、weekday を縦方向。26 列 × 3 行程度に落とし込む代わりに、
        // シンプルに 12 週 × 7 曜日 = 84 セル。デザインは 26 列だが、7 曜日構造が意味的。
        let today = cal.startOfDay(for: .now)
        let daysBack = 12 * 7 - 1
        let cells: [(Date, Int)] = (0...daysBack).map { i in
            let d = cal.date(byAdding: .day, value: -daysBack + i, to: today) ?? today
            return (d, secs[d] ?? 0)
        }
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 3), count: 12), spacing: 3) {
            ForEach(0..<cells.count, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(heatColor(cells[i].1))
                    .aspectRatio(1, contentMode: .fit)
            }
        }
    }

    private func heatColor(_ seconds: Int) -> Color {
        let minutes = seconds / 60
        switch minutes {
        case 0: return c.surface2
        case 1..<30: return c.accentWash
        case 30..<90: return c.accent
        default: return c.accentInk
        }
    }

    // MARK: - Last 7 days bars

    private var weeklyChart: some View {
        let today = cal.startOfDay(for: .now)
        let days: [(Date, Int)] = (0..<7).map { i in
            let d = cal.date(byAdding: .day, value: i - 6, to: today) ?? today
            return (d, focusSecondsByDay[d] ?? 0)
        }
        let maxSec = max(days.map(\.1).max() ?? 1, 3600)
        return HStack(alignment: .bottom, spacing: 8) {
            ForEach(0..<days.count, id: \.self) { idx in
                let (d, sec) = days[idx]
                let isToday = cal.isDate(d, inSameDayAs: today)
                let h = max(CGFloat(sec) / CGFloat(maxSec), 0.05)
                VStack(spacing: 5) {
                    Spacer()
                    RoundedRectangle(cornerRadius: 2)
                        .fill(c.info.opacity(isToday ? 1.0 : 0.7))
                        .frame(height: h * 88)
                    Text("\(cal.component(.day, from: d))")
                        .font(S8Font.mono(9.5, isToday ? .bold : .regular))
                        .foregroundColor(isToday ? c.accentInk : c.fg3)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 108)
        .padding(.horizontal, 24).padding(.top, 4)
    }

    // MARK: - Computed data

    private var focusSecondsByDay: [Date: Int] { StudyStats.focusSecondsByDay(sessions, calendar: cal) }

    private var weeklyFocusSeconds: Int {
        guard let week = cal.dateInterval(of: .weekOfYear, for: .now) else { return 0 }
        return StudyStats.totalFocusSeconds(sessions, in: week)
    }

    private var weeklySubjectSeconds: [UUID: Int] {
        guard let week = cal.dateInterval(of: .weekOfYear, for: .now) else { return [:] }
        var map: [UUID: Int] = [:]
        for s in subjects {
            map[s.id] = StudyStats.focusSeconds(forSubject: s.id, in: week, sessions)
        }
        return map
    }

    private var totalWeeklyGoalMinutes: Int {
        subjects.reduce(0) { $0 + $1.weeklyGoalMinutes }
    }

    private var remainingWeeklyMinutes: Int {
        max(0, totalWeeklyGoalMinutes - weeklyFocusSeconds / 60)
    }

    private var sessionCountThisWeek: Int {
        guard let week = cal.dateInterval(of: .weekOfYear, for: .now) else { return 0 }
        return sessions.filter { week.contains($0.end) }.count
    }

    /// 残りセッション換算（デフォルトポモ 25 分単位で ceil）。目標未達なら残り、達成済みは "0"。
    private var remainingSessionsText: String {
        if totalWeeklyGoalMinutes == 0 { return "—" }
        let mins = remainingWeeklyMinutes
        if mins == 0 { return "0" }
        return "\(Int(ceil(Double(mins) / 25.0)))"
    }

    private var streakDays: Int {
        StudyStats.currentStreakDays(sessions, asOf: .now, calendar: cal)
    }

    private var persona: StudyPersona {
        StudyPersona.from(sessions: sessions, now: .now, calendar: cal)
    }

    private func heroOneLiner(remainingMinutes: Int) -> String {
        if totalWeeklyGoalMinutes == 0 {
            return "科目に週目標を設定すると、\nここにひとことが出ます。"
        }
        if remainingMinutes == 0 {
            return "今週の目標を達成。\nお疲れさま。"
        }
        return "あと\(hmText(TimeInterval(remainingMinutes * 60)))。\n今日を積めば、届く。"
    }

    // MARK: - Shared parts

    private func sectionHeader(_ tag: String, jp: String, trailing: String? = nil) -> some View {
        HStack(spacing: 10) {
            Text(tag).font(S8Font.mono(10)).tracking(1.6).foregroundColor(c.fg3)
            Text(jp).font(S8Font.jp(13, .medium)).foregroundColor(c.fg2)
            if let trailing {
                Text(trailing).font(S8Font.mono(9)).foregroundColor(c.fg3)
            }
            S8Rule()
        }
        .padding(.horizontal, 24).padding(.top, 22).padding(.bottom, 10)
    }

    private func emptyState(icon: String, title: String, detail: String) -> some View {
        VStack(spacing: 8) {
            S8Icon(name: icon, size: 34, color: c.fg3)
            Text(title).font(S8Font.jp(15, .bold)).foregroundColor(c.fg1)
            Text(detail).font(S8Font.jp(13)).foregroundColor(c.fg3).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24).padding(.vertical, 48)
    }

    /// 週の月〜日レンジを "M/d – M/d" 形式で。
    static func weekRangeText(now: Date, calendar: Calendar) -> String {
        guard let week = calendar.dateInterval(of: .weekOfYear, for: now) else { return "" }
        let f = DateFormatter()
        f.dateFormat = "M/d"
        let start = f.string(from: week.start)
        let end = f.string(from: calendar.date(byAdding: .day, value: -1, to: week.end) ?? week.end)
        return "\(start) – \(end)"
    }
}

// MARK: - B2 共有カード

/// 300×534 の静止画。ImageRenderer で書き出して ShareLink 経由で SNS へ。
private struct StudyShareCard: View {
    let weekRange: String
    let focusSeconds: Int
    let goalMinutes: Int
    let persona: StudyPersona
    let streakDays: Int
    let oneLiner: String

    @Environment(\.colorScheme) private var scheme
    private var c: S8Palette { S8Palette.of(scheme) }

    var body: some View {
        let pct = goalMinutes > 0 ? Int(Double(focusSeconds / 60) / Double(goalMinutes) * 100) : 0
        let progress = goalMinutes > 0 ? min(Double(focusSeconds / 60) / Double(goalMinutes), 1.0) : 0
        ZStack {
            c.paper
            VStack(alignment: .center, spacing: 0) {
                // Top: week range
                HStack {
                    Text("THIS WEEK").font(S8Font.mono(9.5)).tracking(1.8).foregroundColor(c.fg3)
                    Spacer()
                    Text(weekRange).font(S8Font.mono(9.5)).tracking(1.0).foregroundColor(c.fg3)
                }
                // Persona illustration + big dot-ring overlay
                ZStack {
                    Image(persona == .unknown ? "study-think"
                          : (progress >= 1.0 ? "study-achieve" : persona.illustrationName))
                        .resizable()
                        .scaledToFit()
                        .frame(width: 200, height: 200)
                    bigDotRing(progress: progress)
                        .frame(width: 224, height: 224)
                }
                .padding(.top, 12)
                // Main time
                Text(hmText(TimeInterval(focusSeconds)))
                    .font(S8Font.mono(46, .bold))
                    .foregroundColor(c.fg1)
                    .padding(.top, 12)
                Text("FOCUS · \(pct)% OF GOAL")
                    .font(S8Font.mono(9)).tracking(1.6).foregroundColor(c.fg3)
                    .padding(.top, 6)
                // Persona
                Text("FOCUS PERSONA")
                    .font(S8Font.mono(9)).tracking(1.6).foregroundColor(c.fg3)
                    .padding(.top, 18)
                Text(persona.name)
                    .font(S8Font.jp(21, .bold)).foregroundColor(c.fg1)
                    .padding(.top, 4)
                Text(oneLiner + "\n" + streakLine)
                    .font(S8Font.jp(12.5)).foregroundColor(c.fg2)
                    .multilineTextAlignment(.center)
                    .padding(.top, 8)
                Spacer(minLength: 0)
                // Footer
                HStack {
                    HStack(spacing: 2) {
                        Text("str").font(.system(size: 18, weight: .heavy)).foregroundColor(c.fg1)
                        Text("(8)").font(.system(size: 18, weight: .heavy)).foregroundColor(c.accent)
                    }
                    Spacer()
                    Text("STUDY HUB").font(S8Font.mono(8.5)).tracking(1.6).foregroundColor(c.fg3)
                }
                .padding(.top, 12)
                .overlay(alignment: .top) { S8Rule() }
                .padding(.top, 12)
            }
            .padding(28)
        }
        .frame(width: 300, height: 534)
        .clipShape(RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(c.lineStrong, lineWidth: 1))
    }

    private var streakLine: String {
        if streakDays > 0 { return "\(streakDays)日連続" }
        return "今日から始めよう"
    }

    private func bigDotRing(progress: Double) -> some View {
        let n = 24
        let onCount = Int(Double(n) * progress)
        return ZStack {
            ForEach(0..<n, id: \.self) { i in
                let angle = Angle.degrees(-90 + Double(i) * 360.0 / Double(n))
                Circle()
                    .fill(i < onCount ? c.accent : c.surface2)
                    .frame(width: 8, height: 8)
                    .offset(x: 84 * cos(angle.radians), y: 84 * sin(angle.radians))
            }
        }
    }
}

// MARK: - Add Subject Sheet

struct AddSubjectSheet: View {
    @Binding var isPresented: Bool
    let context: ModelContext
    @Environment(\.colorScheme) private var scheme
    private var c: S8Palette { S8Palette.of(scheme) }

    @State private var name = ""
    @State private var colorHex = "4F8DFD"
    @State private var dailyGoalMinutes = 60
    @State private var weeklyGoalMinutes = 300
    @State private var pomodoroMinutes = 25

    private let colorOptions = ["FF6B6B", "4ECDC4", "45B7D1", "FFA07A", "98D8C8", "F7DC6F", "BB8FCE"]

    var body: some View {
        let c = self.c
        VStack(spacing: 0) {
            HStack {
                Button("キャンセル") { isPresented = false }
                    .font(S8Font.jp(14)).foregroundColor(c.fg2)
                Spacer()
                Text("科目を追加").font(S8Font.jp(16, .bold)).foregroundColor(c.fg1)
                Spacer()
                Button("追加") {
                    let subject = Subject(
                        id: UUID(), name: name, colorHex: colorHex,
                        dailyGoalMinutes: dailyGoalMinutes,
                        weeklyGoalMinutes: weeklyGoalMinutes,
                        pomodoroMinutes: pomodoroMinutes
                    )
                    context.insert(subject)
                    try? context.save()
                    isPresented = false
                }
                .font(S8Font.jp(14, .bold))
                .foregroundColor(name.trimmingCharacters(in: .whitespaces).isEmpty ? c.fg3 : c.accentInk)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.horizontal, 24).padding(.vertical, 12)

            ScrollView {
                VStack(spacing: 0) {
                    sectionCap("BASIC", jp: "基本情報").padding(.top, 8)
                    S8Field(placeholder: "科目名（例: 統計学）", text: $name).padding(.top, 8)
                    HStack(spacing: 10) {
                        Text("色").font(S8Font.jp(13.5)).foregroundColor(c.fg2)
                        Spacer()
                        ForEach(colorOptions, id: \.self) { hex in
                            Circle()
                                .fill(Color(hex: hex))
                                .frame(width: 26, height: 26)
                                .overlay(Circle().strokeBorder(colorHex == hex ? c.fg1 : Color.clear, lineWidth: 2))
                                .onTapGesture { colorHex = hex }
                        }
                    }
                    .padding(.vertical, 14)
                    .overlay(alignment: .top) { S8Rule() }

                    sectionCap("GOALS", jp: "目標").padding(.top, 20)
                    stepperRow(label: "日目標", value: $dailyGoalMinutes, range: 5...480, step: 5, unit: "分")
                    stepperRow(label: "週目標", value: $weeklyGoalMinutes, range: 30...2400, step: 30, unit: "分")

                    sectionCap("POMODORO", jp: "ポモドーロ").padding(.top, 20)
                    stepperRow(label: "セッション時間", value: $pomodoroMinutes, range: 5...60, step: 5, unit: "分")

                    Color.clear.frame(height: 24)
                }
                .padding(.horizontal, 24)
            }
        }
        .background(c.paper.ignoresSafeArea())
    }

    private func sectionCap(_ tag: String, jp: String) -> some View {
        HStack(spacing: 10) {
            Text(tag).font(S8Font.mono(10)).tracking(1.6).foregroundColor(c.fg3)
            Text(jp).font(S8Font.jp(13, .medium)).foregroundColor(c.fg2)
            S8Rule()
        }
        .padding(.bottom, 8)
    }

    private func stepperRow(label: String, value: Binding<Int>, range: ClosedRange<Int>, step: Int, unit: String) -> some View {
        HStack {
            Text(label).font(S8Font.jp(13.5)).foregroundColor(c.fg2)
            Spacer()
            S8Stepper(value: value, range: range, step: step, unit: unit, width: 132)
        }
        .padding(.vertical, 12)
        .overlay(alignment: .top) { S8Rule() }
    }
}

#Preview {
    StudyHubView()
        .modelContainer(PreviewData.container)
}
