//
//  DayAgendaView.swift
//  str8ToDo
//
//  カード式アジェンダ。行の並べ替えロジックは DayRowBuilder（純粋関数）に集約し、
//  ここは SwiftData からのタスク取得と表示だけを担う。
//  「今」は TimelineView(.everyMinute) の timeline.date を共有して毎分更新する。
//

import SwiftUI
import SwiftData

struct DayAgendaView: View {
    let date: Date
    var morph: Namespace.ID? = nil
    var categoryFilter: Set<UUID>? = nil
    var onSelectTask: ((TaskItem) -> Void)? = nil
    var onTapGap: ((Date, TimeInterval) -> Void)? = nil

    @Environment(\.modelContext) private var context
    @Environment(\.colorScheme) private var scheme
    @Query private var allTasks: [TaskItem]
    @State private var expandedIDs: Set<UUID> = []
    @State private var travelData: [UUID: TimeInterval] = [:]
    @State private var sunCache: (key: String, times: (sunrise: Date, sunset: Date)?)? = nil

    private let cal = Calendar.current

    var body: some View {
        TimelineView(.everyMinute) { timeline in
            let now = timeline.date
            let isToday = cal.isDateInToday(date)
            let rawRows = buildRows(isToday: isToday, now: now)
            let rows: [DayRow] = isToday ? rawRows.compactMap { row in
                if case .gap(let s, let d) = row {
                    guard let c = FreeSlotSuggester.clampGap(start: s, duration: d, now: now) else { return nil }
                    return .gap(start: c.start, duration: c.duration)
                }
                return row
            } : rawRows

            // rows の gap を index 対応で受ける（同時刻 gap の後勝ち上書き防止）
            let gapSuggestions: [[SlotSuggestion]] = isToday ? {
                let candidates = allTasks
                    .filter { $0.startDate == nil && $0.status == .active && ($0.phase == .now || $0.phase == .today) && !(($0.snoozeUntil ?? .distantPast) > now) }
                    .map { FreeSlotSuggester.Candidate(
                        id: $0.id,
                        phaseRank: $0.phase == .now ? 0 : 1,
                        effectiveDuration: FreeSlotSuggester.effectiveDuration(actualDuration: $0.actualDuration, duration: $0.duration),
                        sortIndex: $0.sortIndex) }
                let gaps: [(start: Date, duration: TimeInterval)] = rows.compactMap {
                    if case .gap(let s, let d) = $0 { return (s, d) } else { return nil }
                }
                return FreeSlotSuggester.suggest(gaps: gaps, candidates: candidates)
            }() : []

            // chip 描画時の O(n*k) 走査を O(k) に。allTasks は tasksByID から引く。
            let tasksByID: [UUID: TaskItem] = Dictionary(uniqueKeysWithValues: allTasks.map { ($0.id, $0) })

            // row index → gap index の対応。gap を上から数えて何番目か。
            let gapIndexByRow: [Int: Int] = {
                var map: [Int: Int] = [:]
                var g = 0
                for (i, row) in rows.enumerated() {
                    if case .gap = row {
                        map[i] = g
                        g += 1
                    }
                }
                return map
            }()

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(Array(rows.enumerated()), id: \.element.id) { (index, row) in
                            switch row {
                            case .bandHeading(let band):
                                bandHeadingRow(band)
                                    .id(row.id)

                            case .task(let task):
                                let isPast = isPastTask(task, now: now)
                                let isCollapsed = isPast && !expandedIDs.contains(task.id)

                                taskRow(task, collapsed: isCollapsed)
                                    .id(row.id)
                                    .onTapGesture {
                                        if isCollapsed {
                                            expandedIDs.insert(task.id)
                                        } else {
                                            onSelectTask?(task)
                                        }
                                    }

                            case .gap(let start, let duration):
                                let sug = (gapIndexByRow[index].flatMap { gapSuggestions.indices.contains($0) ? gapSuggestions[$0] : nil }) ?? []
                                gapRow(start: start, duration: duration, suggestions: sug, tasksByID: tasksByID)
                                    .id(row.id)

                            case .nowSeparator:
                                nowSeparatorRow(now: now)
                                    .id(row.id)

                            case .sun(let isSunrise, let time):
                                sunRow(isSunrise: isSunrise, time: time)
                                    .id(row.id)

                            case .travel(let task, let departure, let eta):
                                travelRow(task: task, departure: departure, eta: eta)
                                    .id(row.id)
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 12)
                }
                .onAppear {
                    if isToday {
                        proxy.scrollTo("now", anchor: .center)
                    }
                }
                .onChange(of: date) {
                    if cal.isDateInToday(date) {
                        proxy.scrollTo("now", anchor: .center)
                    }
                }
                .task(id: DayRowBuilder.travelRefreshKey(date: date, now: now, calendar: cal)) {
                    // 出発逆算データを取得（date 変更＋5分粒度で再実行。実要求は30分キャッシュが抑える）
                    await refreshTravelData(now: now)
                }
            }
        }
    }

    // MARK: - 行構築（マージは DayRowBuilder に委譲）

    private func buildRows(isToday: Bool, now: Date) -> [DayRow] {
        let tasks = dayTasks()
        let bands = BandAssignment.resolveTemplate(for: date, context: context, calendar: cal)?.orderedBands ?? []

        // 太陽位置を計算
        let sunTimes = calculateSunTimes()

        // 出発逆算データを集計
        let travelList = tasks.compactMap { task -> (task: TaskItem, departure: Date, eta: TimeInterval)? in
            guard let eta = travelData[task.id] else { return nil }
            guard let startDate = task.startDate else { return nil }
            let departure = startDate.addingTimeInterval(-eta)
            return (task, departure, eta)
        }.sorted { ($0.departure.timeIntervalSince(date)) < ($1.departure.timeIntervalSince(date)) }

        return DayRowBuilder.buildRows(
            day: date,
            allDayTasks: tasks.filter { $0.isAllDay },
            timedTasks: tasks.filter { !$0.isAllDay && $0.startDate != nil },
            bands: bands,
            now: isToday ? now : nil,
            calendar: cal,
            sunTimes: sunTimes,
            travel: travelList
        )
    }

    /// 太陽位置（日の出・日の入り）。日+位置が同じ間はキャッシュを返す（毎分再計算しない）。
    /// 座標未取得なら nil。
    private func calculateSunTimes() -> (sunrise: Date, sunset: Date)? {
        guard let location = LastKnownLocation.load() else { return nil }
        let key = "\(cal.startOfDay(for: date).timeIntervalSinceReferenceDate)-\(location.latitude)-\(location.longitude)"
        if let cached = sunCache, cached.key == key { return cached.times }
        let times = SunCalc.sunTimes(on: date, latitude: location.latitude, longitude: location.longitude, calendar: cal)
        // ponytail: body 内から呼ばれるので更新は次ランループに逃がす（描画中の state 変更警告回避）
        Task { @MainActor in sunCache = (key, times) }
        return times
    }

    /// 出発逆算データを更新（ゲート判定は DepartureService.eta が唯一の判定点）。
    @MainActor
    private func refreshTravelData(now: Date) async {
        travelData = await DepartureService.shared.etas(for: dayTasks(), now: now)
    }

    /// その日と重なるタスク。startDate が同日のもの＋前日以前に開始しその日に食い込む時刻付きタスク。
    /// カテゴリフィルタ時は category nil のタスクを除外。
    private func dayTasks() -> [TaskItem] {
        let dayStart = cal.startOfDay(for: date)
        return allTasks.filter { task in
            guard let start = task.startDate else { return false }
            let overlaps = cal.isDate(start, inSameDayAs: date)
                || (!task.isAllDay && start < dayStart && (task.endDate ?? start) > dayStart)
            guard overlaps else { return false }
            if let filter = categoryFilter {
                guard let catID = task.category?.id, filter.contains(catID) else { return false }
            }
            return true
        }
    }

    /// 当日で、終了予定（なければ開始）が now より過去のタスク。
    private func isPastTask(_ task: TaskItem, now: Date) -> Bool {
        guard cal.isDateInToday(date) else { return false }
        let endDate = task.endDate ?? task.startDate ?? date
        return endDate < now
    }

    /// 当日の時刻付き未来タスクのうち最初のもの（「次の予定まであと◯分」用）。
    private func nextFutureTask(now: Date) -> TaskItem? {
        dayTasks()
            .filter { !$0.isAllDay && $0.startDate != nil }
            .sorted { ($0.startDate ?? .distantPast) < ($1.startDate ?? .distantPast) }
            .first { ($0.startDate ?? date) > now }
    }

    // MARK: - 行表示

    private func bandHeadingRow(_ band: Band) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(band.name)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)

                Text(formatTimeRange(from: band.startMinutes, to: band.endMinutes))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()
            }

            Divider()
        }
        .padding(.horizontal, 8)
    }

    private func taskRow(_ task: TaskItem, collapsed: Bool) -> some View {
        let card = TaskCardView(task: task, collapsed: collapsed)

        if let morph = morph {
            return AnyView(
                card.matchedGeometryEffect(id: "evt-\(task.id.uuidString)", in: morph, isSource: true)
            )
        } else {
            return AnyView(card)
        }
    }

    private func gapRow(start: Date, duration: TimeInterval, suggestions: [SlotSuggestion], tasksByID: [UUID: TaskItem]) -> some View {
        HStack(spacing: 12) {
            // 静的情報（タップ対応、単一アクセシビリティ要素）
            VStack(alignment: .leading, spacing: 8) {
                Text("空き")
                    .font(.caption)
                    .fontWeight(.semibold)

                Text(formatDurationShort(duration))
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Text("+ タスクを置く")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                onTapGap?(start, duration)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityHint("タップでこの時間にタスクを追加")

            Spacer()

            // 提案チップ（静的 VStack の外、個別に VoiceOver 操作可能）
            if !suggestions.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(suggestions) { suggestion in
                        if let task = tasksByID[suggestion.taskID] {
                            Button {
                                task.scheduleAt(start: suggestion.start, duration: suggestion.duration, context: context)
                            } label: {
                                HStack(spacing: 4) {
                                    Text(task.title)
                                        .lineLimit(1)
                                    Text(formatDurationShort(suggestion.duration))
                                        .foregroundStyle(.secondary)
                                }
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(S8Palette.of(scheme).accentWash)
                                .cornerRadius(4)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("\(task.title) をこの空きに入れる")
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [2]))
        )
        .background(Color(.systemBackground))
        .cornerRadius(8)
    }

    /// Handoff 01c: NOW パネル。1.5px accent 縁 + [今] バッジ + 現在時刻 + NEXT/DEPART 分割リードアウト。
    /// 「NEXT」は次予定までの残分、「DEPART」は次の移動逆算タスクの出発時刻。
    private func nowSeparatorRow(now: Date) -> some View {
        let scheme = self.scheme
        let c = S8Palette.of(scheme)
        let next = nextFutureTask(now: now)
        let travel = findNextTravelTask(now: now)
        let nowFormatter: DateFormatter = {
            let f = DateFormatter(); f.dateFormat = "HH:mm"; return f
        }()
        return VStack(spacing: 0) {
            // Header row: [今] + current time + hairline + NOW cap
            HStack(spacing: 10) {
                Text("今")
                    .font(S8Font.jp(11.5, .bold))
                    .foregroundColor(c.onAccent)
                    .frame(width: 28, height: 28)
                    .background(c.accent)
                    .clipShape(Circle())
                Text(nowFormatter.string(from: now))
                    .font(S8Font.mono(12, .bold))
                    .foregroundColor(c.accentInk)
                Rectangle().fill(c.accent).frame(height: 1)
                Text("NOW").font(S8Font.mono(8.5)).tracking(1.6).foregroundColor(c.fg3)
            }
            .padding(.horizontal, 14).padding(.top, 11)
            .padding(.bottom, 11)

            Rectangle().fill(c.accent).frame(height: 1)

            // Split row: NEXT | DEPART
            HStack(spacing: 1) {
                nowSubPanel(
                    cap: "NEXT",
                    big: nextMinutesText(next: next, now: now),
                    unit: nextMinutesUnit(next: next, now: now),
                    hint: nextHintText(next: next),
                    bigColor: c.accentInk,
                    c: c
                )
                Rectangle().fill(c.line).frame(width: 1)
                nowSubPanel(
                    cap: "DEPART",
                    big: travel.map { formatTime($0.departure) } ?? "—",
                    unit: nil,
                    hint: travelHintText(travel: travel),
                    bigColor: travel != nil ? c.fg1 : c.fg3,
                    c: c
                )
            }
            .background(c.line)
        }
        .background(c.surface)
        .overlay(
            RoundedRectangle(cornerRadius: S8Radius.lg)
                .stroke(c.accent, lineWidth: 1.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: S8Radius.lg))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("今 \(nowFormatter.string(from: now)) 次: \(nextHintText(next: next))")
    }

    private func nowSubPanel(cap: String, big: String, unit: String?, hint: String, bigColor: Color, c: S8Palette) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(cap).font(S8Font.mono(8.5)).tracking(1.6).foregroundColor(c.fg3)
            HStack(alignment: .lastTextBaseline, spacing: 2) {
                Text(big).font(S8Font.mono(26, .bold)).foregroundColor(bigColor)
                if let unit {
                    Text(unit).font(S8Font.mono(12)).foregroundColor(c.fg3)
                }
            }
            Text(hint).font(S8Font.jp(11)).foregroundColor(c.fg2)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(c.surface)
    }

    private func nextMinutesText(next: TaskItem?, now: Date) -> String {
        guard let n = next, let start = n.startDate else { return "—" }
        let mins = Int((start.timeIntervalSince(now) / 60).rounded())
        return String(mins > 0 ? "−\(mins)" : "\(mins)")
    }

    private func nextMinutesUnit(next: TaskItem?, now: Date) -> String? {
        guard next?.startDate != nil else { return nil }
        return "分"
    }

    private func nextHintText(next: TaskItem?) -> String {
        guard let n = next, let start = n.startDate else { return "次予定なし" }
        return "\(n.title) \(formatTime(start))"
    }

    private func travelHintText(travel: (task: TaskItem, departure: Date, eta: TimeInterval)?) -> String {
        guard let t = travel else { return "移動予定なし" }
        let mins = Int((t.eta / 60).rounded())
        return "\(t.task.title)へ · 移動\(mins)分"
    }

    private func sunRow(isSunrise: Bool, time: Date) -> some View {
        let c = S8Palette.of(scheme)
        return HStack(spacing: 8) {
            Image(systemName: isSunrise ? "sunrise.fill" : "sunset.fill")
                .font(.caption)
                .foregroundStyle(c.warn)

            Text(isSunrise ? "日の出" : "日の入り")
                .font(.caption2)
                .foregroundStyle(c.fg3)

            Text(formatTime(time))
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundStyle(c.warn.opacity(0.7))

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(isSunrise ? "日の出" : "日の入り") \(formatTime(time))")
    }

    private func travelRow(task: TaskItem, departure: Date, eta: TimeInterval) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "car.fill")
                .font(.caption)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 4) {
                Text("移動")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    Text(formatDurationShort(eta))
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    Text("・\(formatTime(departure))に出発")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
        )
        .background(Color(.systemBackground))
        .cornerRadius(8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("移動 \(formatDurationShort(eta)) \(formatTime(departure))に出発")
    }

    // MARK: - ヘルパー

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.timeStyle = .short
        return f
    }()

    private func formatTime(_ date: Date) -> String {
        Self.timeFormatter.string(from: date)
    }

    private func formatTimeRange(from startMin: Int, to endMin: Int) -> String {
        String(format: "%02d:%02d–%02d:%02d", startMin / 60, startMin % 60, endMin / 60, endMin % 60)
    }

    private func formatDurationShort(_ duration: TimeInterval) -> String {
        let totalMinutes = Int(duration / 60)
        if totalMinutes >= 60 {
            return String(format: "%.1fh", Double(totalMinutes) / 60)
        }
        return "\(totalMinutes)分"
    }

    /// 次の出発逆算タスク（now 以降で departure が最も近いもの）。
    private func findNextTravelTask(now: Date) -> (task: TaskItem, departure: Date, eta: TimeInterval)? {
        let tasks = dayTasks()
        return tasks.compactMap { task -> (task: TaskItem, departure: Date, eta: TimeInterval)? in
            guard let eta = travelData[task.id] else { return nil }
            guard let startDate = task.startDate else { return nil }
            let departure = startDate.addingTimeInterval(-eta)
            return departure >= now ? (task, departure, eta) : nil
        }.sorted { $0.departure < $1.departure }.first
    }

}

#Preview {
    DayAgendaView(date: Calendar.current.startOfDay(for: .now))
        .modelContainer(PreviewData.container)
}
