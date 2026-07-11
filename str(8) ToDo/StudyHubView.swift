//
//  StudyHubView.swift
//  str8ToDo
//
//  科目管理・集中統計・目標とストリーク。
//  S0: 今日/今週合計、科目リスト。S1: ヒートマップ・週次バー・科目別内訳。
//

import SwiftUI
import SwiftData

struct StudyHubView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.colorScheme) private var scheme
    private var c: S8Palette { S8Palette.of(scheme) }
    @Query private var sessions: [FocusSession]
    @Query private var subjects: [Subject]

    @State private var showAddSubjectSheet = false
    @State private var selectedTab = 0

    private let cal = Calendar.current

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("", selection: $selectedTab) {
                    Text("サマリ").tag(0)
                    Text("詳細").tag(1)
                }
                .pickerStyle(.segmented)
                .padding()

                ScrollView {
                    VStack(spacing: 20) {
                        if selectedTab == 0 {
                            summaryTab
                        } else {
                            detailTab
                        }
                    }
                    .padding()
                }
            }
            .background(c.paper)
            .navigationTitle("Study Hub")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: { showAddSubjectSheet = true }) {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showAddSubjectSheet) {
                AddSubjectSheet(isPresented: $showAddSubjectSheet, context: context)
            }
        }
    }

    // MARK: - S0: Summary Tab

    private var summaryTab: some View {
        VStack(spacing: 16) {
            if sessions.isEmpty {
                ContentUnavailableView {
                    Label("集中セッションがありません", systemImage: "hourglass.tophalf.filled")
                } description: {
                    Text("タイマーから集中セッションを記録しましょう")
                }
            } else {
                // ストリークバッジ
                streakBadge

                // 今日の合計
                summaryCard(
                    title: "今日",
                    icon: "calendar",
                    seconds: todayFocusSeconds
                )

                // 今週の合計
                summaryCard(
                    title: "今週",
                    icon: "calendar.circle",
                    seconds: weeklyFocusSeconds
                )

                // 科目別目標進捗
                if !subjects.isEmpty {
                    subjectGoalProgress
                }

                // 科目リスト
                if !subjects.isEmpty {
                    subjectList
                }
            }
        }
    }

    private var streakBadge: some View {
        let streak = StudyStats.currentStreakDays(sessions, asOf: .now, calendar: cal)
        let streakText = streak == 0 ? "ストリークなし" : "\(streak)日連続"
        return HStack {
            Image(systemName: streak > 0 ? "flame.fill" : "flame")
                .foregroundStyle(streak > 0 ? c.accent : c.fg3)
            Text(streakText)
                .font(.subheadline)
            Spacer()
        }
        .padding()
        .background(c.surface2)
        .cornerRadius(8)
        .accessibilityLabel("ストリーク")
        .accessibilityValue(streakText)
    }

    private var subjectGoalProgress: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("目標進捗")
                .font(.headline)
            ForEach(subjects.sorted { $0.name < $1.name }, id: \.id) { subject in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        SubjectIndicator(subject: subject)
                            .font(.callout)
                        Spacer()
                    }

                    // 日目標進捗
                    if let dayInterval = cal.dateInterval(of: .day, for: .now) {
                        let todaySubjectSeconds = StudyStats.focusSeconds(
                            forSubject: subject.id,
                            in: dayInterval,
                            sessions
                        )
                        let goalSeconds = subject.dailyGoalMinutes * 60
                        if goalSeconds > 0 {
                            let progress = min(Double(todaySubjectSeconds) / Double(goalSeconds), 1.0)
                            HStack(spacing: 8) {
                                ProgressView(value: progress)
                                Text("\(todaySubjectSeconds / 60)/\(subject.dailyGoalMinutes)分")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            .accessibilityLabel("\(subject.name)の今日の目標進捗")
                            .accessibilityValue("\(todaySubjectSeconds / 60)/\(subject.dailyGoalMinutes)分")
                        }
                    }

                    // 週目標進捗
                    if let weekInterval = cal.dateInterval(of: .weekOfYear, for: .now) {
                        let weekSubjectSeconds = StudyStats.focusSeconds(
                            forSubject: subject.id,
                            in: weekInterval,
                            sessions
                        )
                        let goalSeconds = subject.weeklyGoalMinutes * 60
                        if goalSeconds > 0 {
                            let progress = min(Double(weekSubjectSeconds) / Double(goalSeconds), 1.0)
                            HStack(spacing: 8) {
                                ProgressView(value: progress)
                                Text("\(weekSubjectSeconds / 60)/\(subject.weeklyGoalMinutes)分")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            .accessibilityLabel("\(subject.name)の今週の目標進捗")
                            .accessibilityValue("\(weekSubjectSeconds / 60)/\(subject.weeklyGoalMinutes)分")
                        }
                    }
                }
                .padding(8)
            }
        }
        .padding()
        .background(c.surface2)
        .cornerRadius(8)
    }

    private func summaryCard(title: String, icon: String, seconds: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(title, systemImage: icon)
                    .font(.headline)
                Spacer()
                Text(durationText(Double(seconds)))
                    .font(.title2)
                    .bold()
            }
        }
        .padding()
        .background(c.surface2)
        .cornerRadius(8)
        .accessibilityLabel("\(title)の集中時間")
        .accessibilityValue(durationText(Double(seconds)))
    }

    private var subjectList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("科目")
                .font(.headline)
            ForEach(subjects.sorted { $0.name < $1.name }, id: \.id) { subject in
                HStack {
                    SubjectIndicator(subject: subject)
                    Spacer()
                    let subjectSeconds = focusSecondsBySubject[subject.id] ?? 0
                    Text(durationText(Double(subjectSeconds)))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .padding(8)
                .accessibilityLabel("\(subject.name)")
                .accessibilityValue(durationText(Double(focusSecondsBySubject[subject.id] ?? 0)))
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        context.delete(subject)
                        try? context.save()
                    } label: {
                        Label("削除", systemImage: "trash")
                    }
                }
            }
        }
        .padding()
        .background(c.surface2)
        .cornerRadius(8)
    }

    // MARK: - S1: Detail Tab

    private var detailTab: some View {
        VStack(spacing: 20) {
            if sessions.isEmpty {
                ContentUnavailableView {
                    Label("データなし", systemImage: "chart.line.uptrend.xyaxis")
                } description: {
                    Text("集中セッションを記録すると統計が表示されます")
                }
            } else {
                // ヒートマップ
                VStack(alignment: .leading, spacing: 8) {
                    Text("集中ヒートマップ")
                        .font(.headline)
                    HeatmapView(
                        year: cal.component(.year, from: .now),
                        values: focusSecondsByDayMap,
                        tint: c.info,
                        intensity: heatmapIntensity,
                        labelFor: heatmapLabel
                    )
                    .accessibilityLabel("年間集中ヒートマップ")
                }

                // 週次バー
                VStack(alignment: .leading, spacing: 8) {
                    Text("最近7日間")
                        .font(.headline)
                    weeklyChart
                }

                // 科目別内訳
                if !subjects.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("科目別集中時間")
                            .font(.headline)
                        subjectBreakdown
                    }
                }
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
                    RoundedRectangle(cornerRadius: 4)
                        .fill(c.info.opacity(0.7))
                        .frame(height: max(CGFloat(day.seconds) / CGFloat(maxSeconds) * 100, 8))

                    Text("\(cal.component(.day, from: day.date))")
                        .font(.caption2)
                }
                .accessibilityLabel(dayLabel(for: day.date))
                .accessibilityValue(durationText(Double(day.seconds)))
            }
        }
        .frame(height: 120)
        .padding()
        .background(c.surface2)
        .cornerRadius(8)
    }

    private var subjectBreakdown: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(subjects.sorted { $0.name < $1.name }, id: \.id) { subject in
                let seconds = focusSecondsBySubject[subject.id] ?? 0
                if seconds > 0 {
                    HStack {
                        SubjectIndicator(subject: subject)
                        Spacer()
                        Text(durationText(Double(seconds)))
                            .font(.callout)
                    }
                    .padding(8)
                    .accessibilityLabel("\(subject.name)の集中時間")
                    .accessibilityValue(durationText(Double(seconds)))
                }
            }
        }
        .padding()
        .background(c.surface2)
        .cornerRadius(8)
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

    // MARK: - Subject Indicator

    private func SubjectIndicator(subject: Subject) -> some View {
        HStack {
            Circle()
                .fill(Color(hex: subject.colorHex))
                .frame(width: 12, height: 12)
            Text(subject.name)
        }
    }
}

// MARK: - Add Subject Sheet

struct AddSubjectSheet: View {
    @Binding var isPresented: Bool
    let context: ModelContext

    @State private var name = ""
    @State private var colorHex = "4F8DFD"
    @State private var dailyGoalMinutes = 60
    @State private var weeklyGoalMinutes = 300
    @State private var pomodoroMinutes = 25

    private let colorOptions = ["FF6B6B", "4ECDC4", "45B7D1", "FFA07A", "98D8C8", "F7DC6F", "BB8FCE"]

    var body: some View {
        NavigationStack {
            Form {
                Section("基本情報") {
                    TextField("科目名", text: $name)
                        .accessibilityLabel("科目名入力")

                    HStack {
                        Text("色")
                        Spacer()
                        Circle()
                            .fill(Color(hex: colorHex))
                            .frame(width: 32, height: 32)
                        Menu {
                            ForEach(colorOptions, id: \.self) { hex in
                                Button(action: { colorHex = hex }) {
                                    HStack {
                                        Circle().fill(Color(hex: hex)).frame(width: 12, height: 12)
                                        Text(hex)
                                    }
                                }
                            }
                        } label: {
                            Image(systemName: "chevron.right")
                                .foregroundStyle(.blue)
                        }
                        .accessibilityLabel("色選択")
                    }
                }

                Section("目標") {
                    Stepper("日目標: \(dailyGoalMinutes)分", value: $dailyGoalMinutes, in: 5...480, step: 5)
                        .accessibilityLabel("日目標分数")
                    Stepper("週目標: \(weeklyGoalMinutes)分", value: $weeklyGoalMinutes, in: 30...2400, step: 30)
                        .accessibilityLabel("週目標分数")
                }

                Section("ポモドーロ") {
                    Stepper("セッション時間: \(pomodoroMinutes)分", value: $pomodoroMinutes, in: 5...60, step: 5)
                        .accessibilityLabel("ポモドーロセッション時間")
                }
            }
            .navigationTitle("科目を追加")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") {
                        isPresented = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("追加") {
                        let subject = Subject(
                            id: UUID(),
                            name: name,
                            colorHex: colorHex,
                            dailyGoalMinutes: dailyGoalMinutes,
                            weeklyGoalMinutes: weeklyGoalMinutes,
                            pomodoroMinutes: pomodoroMinutes
                        )
                        context.insert(subject)
                        try? context.save()
                        isPresented = false
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

#Preview {
    StudyHubView()
        .modelContainer(PreviewData.container)
}
