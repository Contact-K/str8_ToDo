//
//  StudyHubView.swift
//  str8ToDo
//
//  科目管理・集中統計・目標とストリーク。
//  S0: 今日/今週合計、科目リスト。S1: ヒートマップ・週次バー・科目別内訳。
//

import SwiftUI
import SwiftData

extension Notification.Name {
    /// Handoff 00c: 勉強タブ ホイール中心タップ→科目追加シート
    static let s8StudyAddSubject = Notification.Name("s8.study.addSubject")
}

struct StudyHubView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.colorScheme) private var scheme
    private var c: S8Palette { S8Palette.of(scheme) }
    @Query private var sessions: [FocusSession]
    @Query private var subjects: [Subject]

    @State private var showAddSubjectSheet = false
    @State private var selectedTab = 0
    /// Handoff 00c: ホイール VIEW ダイヤル（0=サマリ 1=詳細）と連動。
    @AppStorage("wheel.study.view") private var wheelStudyView = 0

    private let cal = Calendar.current

    var body: some View {
        let c = self.c
        VStack(spacing: 0) {
            // ponytail: ヘッダ + ボタンは撤去。科目追加はホイール中心コアで発火。
            S8TopBar("勉強", sub: "study hub · focus & streak") { EmptyView() }

            HStack(spacing: 8) {
                S8Chip("サマリ", selected: selectedTab == 0, action: { selectedTab = 0 })
                S8Chip("詳細", selected: selectedTab == 1, action: { selectedTab = 1 })
            }
            .padding(.horizontal, 24).padding(.bottom, 12)

            ScrollView {
                VStack(spacing: 0) {
                    if selectedTab == 0 {
                        summaryTab
                    } else {
                        detailTab
                    }
                    Color.clear.frame(height: 24)
                }
            }
        }
        .background(c.paper.ignoresSafeArea())
        .sheet(isPresented: $showAddSubjectSheet) {
            AddSubjectSheet(isPresented: $showAddSubjectSheet, context: context)
        }
        // ホイール中心の科目追加ボタンからの発火を購読
        .onReceive(NotificationCenter.default.publisher(for: .s8StudyAddSubject)) { _ in
            showAddSubjectSheet = true
        }
    }

    // MARK: - S0: Summary Tab

    @ViewBuilder
    private var summaryTab: some View {
        if sessions.isEmpty {
            emptyState(icon: "hourglass.tophalf.filled", title: "集中セッションがありません",
                       detail: "タイマーから集中セッションを記録しましょう")
        } else {
            streakBadge
            summaryRow(title: "今日", tag: "TODAY", seconds: todayFocusSeconds)
            summaryRow(title: "今週", tag: "WEEK", seconds: weeklyFocusSeconds)

            if !subjects.isEmpty {
                sectionHeader("GOALS", jp: "目標進捗")
                subjectGoalProgress
            }
            if !subjects.isEmpty {
                sectionHeader("SUBJECTS", jp: "科目")
                subjectList
            }
        }
    }

    /// Handoff 05a: 火バッジ（丸 44px、accent-wash 背景、accent 縁）+ 日数 + STREAK · 0:00 RESET テレメトリ。
    private var streakBadge: some View {
        let streak = StudyStats.currentStreakDays(sessions, asOf: .now, calendar: cal)
        let streakText = streak == 0 ? "ストリークなし" : "\(streak)日連続"
        let active = streak > 0
        return HStack(spacing: 14) {
            ZStack {
                Circle().fill(active ? c.accentWash : c.surface2)
                Circle().strokeBorder(active ? c.accent : c.line, lineWidth: 1.5)
                S8Icon(name: "flame", size: 19, color: active ? c.accentInk : c.fg3)
            }
            .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(streakText).font(S8Font.jp(15, .bold)).foregroundColor(c.fg1)
                Text("STREAK · 0:00 RESET")
                    .font(S8Font.mono(9.5)).tracking(1.2).foregroundColor(c.fg3)
            }
            Spacer()
        }
        .padding(.horizontal, 24).padding(.vertical, 14)
        .overlay(alignment: .top) { S8Rule() }
        .accessibilityLabel("ストリーク")
        .accessibilityValue(streakText)
    }

    private func summaryRow(title: String, tag: String, seconds: Int) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(tag).font(S8Font.mono(10)).tracking(1.5).foregroundColor(c.fg3)
                Text(title).font(S8Font.jp(14, .medium)).foregroundColor(c.fg2)
            }
            Spacer()
            Text(durationText(Double(seconds))).font(S8Font.mono(17, .bold)).foregroundColor(c.fg1)
        }
        .padding(.horizontal, 24).padding(.vertical, 14)
        .overlay(alignment: .top) { S8Rule() }
        .accessibilityLabel("\(title)の集中時間")
        .accessibilityValue(durationText(Double(seconds)))
    }

    private var subjectGoalProgress: some View {
        VStack(spacing: 0) {
            ForEach(subjects.sorted { $0.name < $1.name }, id: \.id) { subject in
                VStack(alignment: .leading, spacing: 8) {
                    subjectIndicator(subject)

                    if let dayInterval = cal.dateInterval(of: .day, for: .now) {
                        let todaySubjectSeconds = StudyStats.focusSeconds(
                            forSubject: subject.id, in: dayInterval, sessions
                        )
                        let goalSeconds = subject.dailyGoalMinutes * 60
                        if goalSeconds > 0 {
                            let progress = min(Double(todaySubjectSeconds) / Double(goalSeconds), 1.0)
                            goalBar(progress: progress, text: "今日 \(todaySubjectSeconds / 60)/\(subject.dailyGoalMinutes)分")
                                .accessibilityLabel("\(subject.name)の今日の目標進捗")
                                .accessibilityValue("\(todaySubjectSeconds / 60)/\(subject.dailyGoalMinutes)分")
                        }
                    }

                    if let weekInterval = cal.dateInterval(of: .weekOfYear, for: .now) {
                        let weekSubjectSeconds = StudyStats.focusSeconds(
                            forSubject: subject.id, in: weekInterval, sessions
                        )
                        let goalSeconds = subject.weeklyGoalMinutes * 60
                        if goalSeconds > 0 {
                            let progress = min(Double(weekSubjectSeconds) / Double(goalSeconds), 1.0)
                            goalBar(progress: progress, text: "今週 \(weekSubjectSeconds / 60)/\(subject.weeklyGoalMinutes)分")
                                .accessibilityLabel("\(subject.name)の今週の目標進捗")
                                .accessibilityValue("\(weekSubjectSeconds / 60)/\(subject.weeklyGoalMinutes)分")
                        }
                    }
                }
                .padding(.horizontal, 24).padding(.vertical, 12)
                .overlay(alignment: .top) { S8Rule() }
            }
        }
    }

    private func goalBar(progress: Double, text: String) -> some View {
        HStack(spacing: 8) {
            ProgressView(value: progress).tint(c.accent)
            Text(text).font(S8Font.mono(11)).foregroundColor(c.fg3)
        }
    }

    private var subjectList: some View {
        VStack(spacing: 0) {
            ForEach(subjects.sorted { $0.name < $1.name }, id: \.id) { subject in
                HStack(spacing: 10) {
                    subjectIndicator(subject)
                    Spacer()
                    let subjectSeconds = focusSecondsBySubject[subject.id] ?? 0
                    Text(durationText(Double(subjectSeconds)))
                        .font(S8Font.mono(13)).foregroundColor(c.fg3)
                    S8IconButton(icon: "trash", action: {
                        context.delete(subject)
                        try? context.save()
                    })
                    .accessibilityLabel("\(subject.name)を削除")
                }
                .padding(.horizontal, 24).padding(.vertical, 12)
                .overlay(alignment: .top) { S8Rule() }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(subject.name)
                .accessibilityValue(durationText(Double(focusSecondsBySubject[subject.id] ?? 0)))
            }
        }
    }

    // MARK: - S1: Detail Tab

    @ViewBuilder
    private var detailTab: some View {
        if sessions.isEmpty {
            emptyState(icon: "chart.line.uptrend.xyaxis", title: "データなし",
                       detail: "集中セッションを記録すると統計が表示されます")
        } else {
            sectionHeader("HEATMAP", jp: "集中ヒートマップ")
            HeatmapView(
                year: cal.component(.year, from: .now),
                values: focusSecondsByDayMap,
                tint: c.info,
                intensity: heatmapIntensity,
                labelFor: heatmapLabel
            )
            .padding(.horizontal, 24).padding(.vertical, 8)
            .accessibilityLabel("年間集中ヒートマップ")

            sectionHeader("LAST 7 DAYS", jp: "最近7日間")
            weeklyChart

            if !subjects.isEmpty {
                sectionHeader("BY SUBJECT", jp: "科目別集中時間")
                subjectBreakdown
            }
        }
    }

    /// 直近7日の (日付, 集中秒)。ViewBuilder 外で計算して代入文を排除。
    private var last7Days: [(date: Date, seconds: Int)] {
        let today = cal.startOfDay(for: .now)
        return (0..<7).map { idx in
            let date = cal.date(byAdding: .day, value: idx - 6, to: today) ?? today
            return (date, focusSecondsByDay[date] ?? 0)
        }
    }

    private var weeklyChart: some View {
        let maxSeconds = max(1, last7Days.map(\.seconds).max() ?? 3600)
        return HStack(alignment: .bottom, spacing: 8) {
            ForEach(last7Days, id: \.date) { day in
                VStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: S8Radius.sm)
                        .fill(c.info.opacity(0.7))
                        .frame(height: max(CGFloat(day.seconds) / CGFloat(maxSeconds) * 100, 8))

                    Text("\(cal.component(.day, from: day.date))")
                        .font(S8Font.mono(10)).foregroundColor(c.fg3)
                }
                .accessibilityLabel(dayLabel(for: day.date))
                .accessibilityValue(durationText(Double(day.seconds)))
            }
        }
        .frame(height: 120)
        .padding(.horizontal, 24).padding(.vertical, 12)
    }

    private var subjectBreakdown: some View {
        VStack(spacing: 0) {
            ForEach(subjects.sorted { $0.name < $1.name }, id: \.id) { subject in
                let seconds = focusSecondsBySubject[subject.id] ?? 0
                if seconds > 0 {
                    HStack(spacing: 10) {
                        subjectIndicator(subject)
                        Spacer()
                        Text(durationText(Double(seconds))).font(S8Font.mono(13)).foregroundColor(c.fg2)
                    }
                    .padding(.horizontal, 24).padding(.vertical, 12)
                    .overlay(alignment: .top) { S8Rule() }
                    .accessibilityLabel("\(subject.name)の集中時間")
                    .accessibilityValue(durationText(Double(seconds)))
                }
            }
        }
    }

    // MARK: - Computed Properties

    // 集計はすべて共有純関数 StudyStats（Subject.swift、selfcheck 検証済み）に委譲。
    private var focusSecondsByDay: [Date: Int] { StudyStats.focusSecondsByDay(sessions, calendar: cal) }

    private var focusSecondsByDayMap: [Date: Double] {
        Dictionary(uniqueKeysWithValues: focusSecondsByDay.map { ($0.key, Double($0.value)) })
    }

    private var focusSecondsBySubject: [UUID: Int] { StudyStats.focusSecondsBySubject(sessions) }

    private var todayFocusSeconds: Int {
        guard let day = cal.dateInterval(of: .day, for: .now) else { return 0 }
        return StudyStats.totalFocusSeconds(sessions, in: day)
    }

    private var weeklyFocusSeconds: Int {
        guard let week = cal.dateInterval(of: .weekOfYear, for: .now) else { return 0 }
        return StudyStats.totalFocusSeconds(sessions, in: week)
    }

    private func heatmapIntensity(_ value: Double) -> Double {
        // 秒を分に変換。30分で 0.3、120分で 1.0に飽和する線形
        let minutes = value / 60.0
        return min(minutes / 120.0, 1.0)
    }

    private func heatmapLabel(date: Date, value: Double) -> String {
        let dateStr = dayLabel(for: date)
        if value > 0 {
            return "\(dateStr) \(durationText(value))集中"
        } else {
            return "\(dateStr) 記録なし"
        }
    }

    private func dayLabel(for date: Date) -> String {
        "\(cal.component(.month, from: date))月\(cal.component(.day, from: date))日"
    }

    // MARK: - 共有パーツ

    private func subjectIndicator(_ subject: Subject) -> some View {
        HStack(spacing: 8) {
            Circle().fill(Color(hex: subject.colorHex)).frame(width: 10, height: 10)
            Text(subject.name).font(S8Font.jp(14, .medium)).foregroundColor(c.fg1)
        }
    }

    /// mono UPPERCASE caption + JP ラベルの2段セクション見出し。
    private func sectionHeader(_ tag: String, jp: String) -> some View {
        HStack(spacing: 10) {
            Text(tag).font(S8Font.mono(10)).tracking(1.6).foregroundColor(c.fg3)
            Text(jp).font(S8Font.jp(13, .medium)).foregroundColor(c.fg2)
            S8Rule()
        }
        .padding(.horizontal, 24).padding(.top, 20).padding(.bottom, 8)
    }

    private func emptyState(icon: String, title: String, detail: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 34)).foregroundColor(c.fg3)
            Text(title).font(S8Font.jp(15, .bold)).foregroundColor(c.fg1)
            Text(detail).font(S8Font.jp(13)).foregroundColor(c.fg3).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24).padding(.vertical, 48)
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
            // Handoff ヘッダ: [キャンセル][タイトル][追加]
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
                    sectionCap("BASIC", jp: "基本情報")
                        .padding(.top, 8)
                    // 科目名
                    S8Field(placeholder: "科目名（例: 統計学）", text: $name)
                        .padding(.top, 8)
                    // 色選択（Handoff: パレット直置き）
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

                    sectionCap("GOALS", jp: "目標")
                        .padding(.top, 20)
                    stepperRow(label: "日目標", value: $dailyGoalMinutes, range: 5...480, step: 5, unit: "分")
                    stepperRow(label: "週目標", value: $weeklyGoalMinutes, range: 30...2400, step: 30, unit: "分")

                    sectionCap("POMODORO", jp: "ポモドーロ")
                        .padding(.top, 20)
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
            Text("\(value.wrappedValue)\(unit)")
                .font(S8Font.mono(14, .bold))
                .foregroundColor(c.fg1)
            Stepper("", value: value, in: range, step: step).labelsHidden()
        }
        .padding(.vertical, 12)
        .overlay(alignment: .top) { S8Rule() }
    }
}

#Preview {
    StudyHubView()
        .modelContainer(PreviewData.container)
}
