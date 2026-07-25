import WidgetKit
import SwiftUI
import Foundation
import ActivityKit

// MARK: - Handoff palette（Widget 目的別・S8 と同値）
private enum W {
    static let paper = Color(red: 0xF4/255, green: 0xF2/255, blue: 0xEA/255)
    static let surface2 = Color(red: 0xED/255, green: 0xEA/255, blue: 0xE0/255)
    static let fg1 = Color(red: 0x1F/255, green: 0x1E/255, blue: 0x1A/255)
    static let fg2 = Color(red: 0x46/255, green: 0x44/255, blue: 0x3E/255)
    static let fg3 = Color(red: 0x8A/255, green: 0x87/255, blue: 0x7C/255)
    static let line = Color(red: 0xE2/255, green: 0xDE/255, blue: 0xD2/255)
    static let lineStrong = Color(red: 0xC9/255, green: 0xC4/255, blue: 0xB5/255)
    static let accent = Color(red: 0xDC/255, green: 0x8B/255, blue: 0x28/255)
    static let accentInk = Color(red: 0xB0/255, green: 0x6D/255, blue: 0x17/255)
    static let ok = Color(red: 0x3D/255, green: 0x5A/255, blue: 0x47/255)
    /// Live Activity 用の温かい橙（darkContext で発光する）。
    static let live = Color(red: 0xED/255, green: 0xA9/255, blue: 0x48/255)
    /// Live Activity dim（未経過ドット）。
    static let liveOff = Color.white.opacity(0.18)
    /// Dark BG (StandBy / Live Activity)
    static let darkBg = Color(red: 0x15/255, green: 0x14/255, blue: 0x0F/255)
    static let darkFg = Color(red: 0xF1/255, green: 0xEF/255, blue: 0xE6/255)
    static let darkLine = Color(red: 0x32/255, green: 0x2F/255, blue: 0x26/255)
}

private enum WF {
    static func mono(_ size: CGFloat, _ w: Font.Weight = .regular) -> Font {
        .system(size: size, weight: w, design: .monospaced)
    }
    static func jp(_ size: CGFloat, _ w: Font.Weight = .medium) -> Font {
        .system(size: size, weight: w)
    }
}

// MARK: - Dot ring（C WIDGETS 共通ビジュアル。砂時計グリフを廃止してこれで統一）

private struct DotRing: View {
    let radius: CGFloat
    let count: Int
    /// 0..1。埋まるドット数比。
    let progress: Double
    let onColor: Color
    let offColor: Color
    let dotSize: CGFloat
    /// 12時方向を基準とする角度オフセット。-90 = 12時から時計回り。
    var startDegrees: Double = -90

    var body: some View {
        let k = Int((Double(count) * max(0, min(1, progress))).rounded())
        ZStack {
            ForEach(0..<count, id: \.self) { i in
                let a = Angle.degrees(startDegrees + Double(i) * 360.0 / Double(count))
                Circle()
                    .fill(i < k ? onColor : offColor)
                    .frame(width: dotSize, height: dotSize)
                    .offset(x: radius * cos(a.radians), y: radius * sin(a.radians))
            }
        }
    }
}

// MARK: - Samon backdrop（薄い砂紋。paper widget の底辺に敷く）

private struct SamonBackdrop: Shape {
    /// 高さ比 0..1 で 2〜3 本の緩やかな曲線を返す。
    let curveRatios: [Double]
    func path(in rect: CGRect) -> Path {
        var p = Path()
        for r in curveRatios {
            let y = rect.height * r
            p.move(to: CGPoint(x: 0, y: y))
            p.addQuadCurve(to: CGPoint(x: rect.width, y: y),
                           control: CGPoint(x: rect.width / 2, y: y - rect.height * 0.03))
        }
        return p
    }
}

// MARK: - TimelineEntry
struct StrEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
}

// MARK: - Provider
struct StrTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> StrEntry {
        StrEntry(date: .now, snapshot: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (StrEntry) -> Void) {
        let snapshot = WidgetSnapshotStore.read()
        completion(StrEntry(date: .now, snapshot: snapshot))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<StrEntry>) -> Void) {
        let snapshot = WidgetSnapshotStore.read()
        let now = Date.now

        var entries: [StrEntry] = [StrEntry(date: now, snapshot: snapshot)]

        if let snapshot = snapshot {
            for boundary in snapshot.timelineBoundaries(after: now) {
                entries.append(StrEntry(date: boundary, snapshot: snapshot))
            }
            let cal = Calendar.current
            let today = cal.startOfDay(for: now)
            let bandBoundaries: [Date] = snapshot.bands.flatMap { band -> [Date] in
                let s = cal.date(byAdding: .minute, value: band.startMinutes, to: today) ?? today
                let e = cal.date(byAdding: .minute, value: band.endMinutes, to: today) ?? today
                return [s, e]
            }.filter { $0 > now }
            for boundary in Array(Set(bandBoundaries)).sorted() {
                entries.append(StrEntry(date: boundary, snapshot: snapshot))
            }
        }

        let reloadTime = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: now)) ?? now.addingTimeInterval(86400)
        let timeline = Timeline(entries: entries, policy: .after(reloadTime))
        completion(timeline)
    }
}

// MARK: - View
struct StrWidgetView: View {
    let entry: StrEntry
    @Environment(\.widgetFamily) var family

    private var currentCard: WidgetSnapshot.Card? {
        entry.snapshot?.currentCard(at: entry.date)
    }

    private var isCurrent: Bool {
        entry.snapshot != nil && entry.snapshot?.isStale == false
    }

    private let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    var body: some View {
        switch family {
        case .systemSmall:
            systemSmallView
        case .systemMedium:
            systemMediumView
        case .accessoryRectangular:
            accessoryRectangularView
        case .accessoryInline:
            accessoryInlineView
        case .accessoryCircular:
            accessoryCircularView
        default:
            systemSmallView
        }
    }

    // MARK: - System Small（C1: 砂紋 + ドット環 + NEXT）

    private var systemSmallView: some View {
        ZStack(alignment: .topLeading) {
            SamonBackdrop(curveRatios: [0.75, 0.85, 0.95])
                .stroke(W.line, lineWidth: 1)
                .opacity(0.6)
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 5) {
                    Circle().fill(W.accent).frame(width: 6, height: 6)
                    Text(currentCard.map(remainLabel) ?? "NEXT")
                        .font(WF.mono(8, .regular)).tracking(1.4).foregroundColor(W.fg3)
                }
                if let card = currentCard {
                    HStack(spacing: 12) {
                        smallRing(for: card)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(card.title)
                                .font(WF.jp(13, .bold)).foregroundColor(W.fg1)
                                .lineLimit(1)
                            Text("\(timeFormatter.string(from: card.start))–\(timeFormatter.string(from: card.end))")
                                .font(WF.mono(9)).foregroundColor(W.fg3).lineLimit(1)
                        }
                    }
                    .padding(.top, 8)
                } else if isCurrent {
                    Spacer(minLength: 0)
                    Text("今日の予定は完了").font(WF.jp(11)).foregroundColor(W.fg3)
                } else {
                    Spacer(minLength: 0)
                    Text("アプリで更新").font(WF.jp(11)).foregroundColor(W.fg3)
                }
                Spacer(minLength: 0)
                HStack(spacing: 8) {
                    statPair(label: "達成", value: "\(entry.snapshot?.achievementCount ?? 0)", strong: false)
                    statPair(label: "未確定", value: "\(entry.snapshot?.unconfirmedCount ?? 0)", strong: true)
                }
                .padding(.top, 8)
                .overlay(alignment: .top) { Rectangle().fill(W.line).frame(height: 1).offset(y: -4) }
            }
        }
        .containerBackground(for: .widget) { W.paper }
    }

    /// Small 用 52pt ドット環（残り分数を中央表示）。
    private func smallRing(for card: WidgetSnapshot.Card) -> some View {
        let mins = remainMinutes(for: card)
        let progress = ringProgress(for: card)
        return ZStack {
            DotRing(radius: 20, count: 12, progress: progress,
                    onColor: W.accent, offColor: W.lineStrong, dotSize: 2.4)
            VStack(spacing: 0) {
                Text("\(mins)").font(WF.mono(11, .bold)).foregroundColor(W.accentInk)
                Text("分").font(WF.mono(6.5)).foregroundColor(W.fg3)
            }
        }
        .frame(width: 52, height: 52)
    }

    // MARK: - System Medium（C1: 大きめドット環 + 今日の枠）

    private var systemMediumView: some View {
        ZStack {
            SamonBackdrop(curveRatios: [0.80, 0.90])
                .stroke(W.line, lineWidth: 1)
                .opacity(0.55)
            HStack(spacing: 16) {
                // 左: 74pt ドット環
                if let card = currentCard {
                    mediumRing(for: card)
                        .frame(width: 74, height: 74)
                } else {
                    ZStack {
                        DotRing(radius: 29, count: 12, progress: 0,
                                onColor: W.accent, offColor: W.lineStrong, dotSize: 3)
                        Text("—").font(WF.mono(14, .bold)).foregroundColor(W.fg3)
                    }
                    .frame(width: 74, height: 74)
                }

                // 中: タイトル + 時刻 + 出発逆算 + 統計
                VStack(alignment: .leading, spacing: 3) {
                    if let card = currentCard {
                        Text(card.title)
                            .font(WF.jp(14, .bold)).foregroundColor(W.fg1)
                            .lineLimit(1)
                        Text("\(timeFormatter.string(from: card.start))–\(timeFormatter.string(from: card.end))")
                            .font(WF.mono(9.5)).foregroundColor(W.fg3)
                    } else if isCurrent {
                        Text("今日の予定は完了").font(WF.jp(12)).foregroundColor(W.fg3)
                    }
                    Spacer(minLength: 0)
                    HStack(spacing: 6) {
                        Text("達成 \(entry.snapshot?.achievementCount ?? 0)/\(bandsCount)")
                            .font(WF.mono(8.5)).tracking(0.8).foregroundColor(W.fg2).lineLimit(1)
                        Text("·").foregroundColor(W.fg3).font(WF.mono(8.5))
                        Text("未確定 \(entry.snapshot?.unconfirmedCount ?? 0)")
                            .font(WF.mono(8.5, .bold)).tracking(0.8)
                            .foregroundColor(W.accentInk).lineLimit(1)
                    }
                    .fixedSize(horizontal: true, vertical: false)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Rectangle().fill(W.line).frame(width: 1)

                // 右: 今日の枠
                VStack(alignment: .leading, spacing: 5) {
                    Text("今日の枠").font(WF.mono(8, .regular)).tracking(1.4).foregroundColor(W.fg3)
                    ForEach(Array((entry.snapshot?.bands ?? []).prefix(3).enumerated()), id: \.offset) { _, band in
                        HStack(spacing: 6) {
                            let phase = bandPhase(for: band, at: entry.date)
                            switch phase {
                            case .past:
                                ZStack {
                                    Circle().fill(W.ok)
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundColor(W.paper)
                                }
                                .frame(width: 14, height: 14)
                                Text(band.name).font(WF.jp(10)).foregroundColor(W.fg3).strikethrough().lineLimit(1)
                            case .current:
                                Circle().strokeBorder(W.accent, lineWidth: 1.5).frame(width: 14, height: 14)
                                Text(band.name).font(WF.jp(10, .bold)).foregroundColor(W.fg1).lineLimit(1)
                            case .future:
                                Circle().strokeBorder(W.lineStrong, lineWidth: 1).frame(width: 14, height: 14)
                                Text(band.name).font(WF.jp(10)).foregroundColor(W.fg2).lineLimit(1)
                            }
                        }
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .containerBackground(for: .widget) { W.paper }
    }

    /// Medium 用 74pt ドット環。
    private func mediumRing(for card: WidgetSnapshot.Card) -> some View {
        let mins = remainMinutes(for: card)
        let progress = ringProgress(for: card)
        return ZStack {
            DotRing(radius: 29, count: 12, progress: progress,
                    onColor: W.accent, offColor: W.lineStrong, dotSize: 3)
            VStack(spacing: 0) {
                Text("\(mins)").font(WF.mono(14, .bold)).foregroundColor(W.accentInk)
                Text("分").font(WF.mono(7.5)).foregroundColor(W.fg3)
                Text(remainLabel(for: card)).font(WF.mono(6)).tracking(1).foregroundColor(W.fg3).padding(.top, 1)
            }
        }
    }

    private var bandsCount: Int { entry.snapshot?.bands.count ?? 0 }

    private enum BandPhase { case past, current, future }
    private func bandPhase(for band: WidgetSnapshot.BandInfo, at date: Date) -> BandPhase {
        let cal = Calendar.current
        let minute = cal.component(.hour, from: date) * 60 + cal.component(.minute, from: date)
        if minute >= band.endMinutes { return .past }
        if minute >= band.startMinutes { return .current }
        return .future
    }

    /// 進行中か（開始 <= entry < 終了）。
    private func isInProgress(_ card: WidgetSnapshot.Card) -> Bool {
        entry.date >= card.start && entry.date < card.end
    }

    /// 進行中なら「終了までの残り分」、それ以外なら「開始までの残り分」。0 未満は 0 にクランプ。
    private func remainMinutes(for card: WidgetSnapshot.Card) -> Int {
        let target = isInProgress(card) ? card.end : card.start
        return max(0, Int(target.timeIntervalSince(entry.date) / 60))
    }

    /// ラベル: 進行中は NOW / 予定前は NEXT。
    private func remainLabel(for card: WidgetSnapshot.Card) -> String {
        isInProgress(card) ? "NOW" : "NEXT"
    }

    /// ドット環 progress。
    /// - 進行中カード: 経過率 = (now - start) / (end - start)。時間が進むほど埋まる。
    /// - 予定前カード: 1 - (残り分 / 120)。2時間+先の予定は空、開始直前で満杯。
    private func ringProgress(for card: WidgetSnapshot.Card) -> Double {
        if isInProgress(card) {
            let total = card.end.timeIntervalSince(card.start)
            guard total > 0 else { return 1 }
            let elapsed = entry.date.timeIntervalSince(card.start)
            return max(0, min(1, elapsed / total))
        } else {
            let remaining = card.start.timeIntervalSince(entry.date) / 60
            return max(0, min(1, 1.0 - remaining / 120.0))
        }
    }

    private func statPair(label: String, value: String, strong: Bool) -> some View {
        HStack(spacing: 4) {
            Text(label).font(WF.mono(8.5)).tracking(1.0).foregroundColor(W.fg3).lineLimit(1)
            Text(value)
                .font(WF.mono(8.5, strong ? .bold : .regular))
                .foregroundColor(strong ? W.accentInk : W.fg1)
                .lineLimit(1)
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    // MARK: - Accessory Rectangular

    private var accessoryRectangularView: some View {
        VStack(alignment: .leading, spacing: 3) {
            if let card = currentCard {
                Text("\(remainLabel(for: card)) · あと\(remainMinutes(for: card))分")
                    .font(.system(size: 8, weight: .regular, design: .monospaced))
                    .textCase(.uppercase)
                    .opacity(0.6)
                Text(card.title)
                    .lineLimit(1)
                    .font(.system(size: 13, weight: .bold))
                Text("\(timeFormatter.string(from: card.start))–\(timeFormatter.string(from: card.end))")
                    .font(.system(size: 9.5, weight: .regular, design: .monospaced))
                    .opacity(0.65)
            } else {
                Text("予定なし").font(.system(size: 12))
            }
        }
        .containerBackground(for: .widget) { Color.clear }
    }

    // MARK: - Accessory Inline
    private var accessoryInlineView: some View {
        Group {
            if let card = currentCard {
                Text("次: \(card.title) \(timeFormatter.string(from: card.start))")
                    .lineLimit(1)
            } else {
                Text("予定なし")
            }
        }
    }

    // MARK: - Accessory Circular（達成ゲージをドット環に）

    private var accessoryCircularView: some View {
        let done = entry.snapshot?.achievementCount ?? 0
        let bandsN = max(1, bandsCount)
        let fraction = min(Double(done) / Double(bandsN), 1)
        return ZStack {
            DotRing(radius: 24, count: 14, progress: fraction,
                    onColor: Color.white, offColor: Color.white.opacity(0.22), dotSize: 2.7)
            VStack(spacing: -1) {
                HStack(alignment: .lastTextBaseline, spacing: 0) {
                    Text("\(done)").font(.system(size: 15, weight: .bold, design: .monospaced))
                    Text("/\(bandsN)").font(.system(size: 9, design: .monospaced)).opacity(0.7)
                }
                Text("DONE").font(.system(size: 6.5, design: .monospaced)).tracking(1.2).opacity(0.7)
            }
        }
        .containerBackground(for: .widget) { Color.clear }
    }
}

// MARK: - Widget
struct str8Widget: Widget {
    let kind: String = "str8Widget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: StrTimelineProvider()) { entry in
            StrWidgetView(entry: entry)
        }
        .configurationDisplayName("str(8) ToDo")
        .description("次の予定と達成状況")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryInline, .accessoryCircular])
    }
}

// MARK: - Live Activity（C3: 砂時計グリフ廃止 → ドット環 / ドット列で表現）

@available(iOS 16.1, *)
struct TimerLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TimerAttributes.self) { context in
            lockBanner(context: context)
                .activityBackgroundTint(W.darkBg)
                .activitySystemActionForegroundColor(W.darkFg)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    liveRing(context: context, size: 44)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    // trailing 領域はやや狭い。18pt 横一列 + minimumScaleFactor で必要なら自動縮小。
                    // 縦 3 段組は TimelineView.periodic が iOS に throttle されて数秒で止まるため不採用。
                    // Text(timerInterval:) は OS 特別処理で throttle されず秒毎に更新される。
                    remainDisplay(context: context, size: 18)
                        .foregroundColor(W.live)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.attributes.taskTitle)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.white)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Text("FOCUS" + (context.attributes.subjectName.map { " · \($0)" } ?? ""))
                            .font(.system(size: 9, design: .monospaced))
                            .tracking(1.2)
                            .foregroundColor(.white.opacity(0.6))
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    progressBar(context: context)
                }
            } compactLeading: {
                // デザイン C3 通り: 時間 LEFT / 進捗 RIGHT。
                remainDisplay(context: context, size: 13)
                    .foregroundColor(W.live)
                    .frame(width: 44)
            } compactTrailing: {
                let start = context.state.endDate.addingTimeInterval(-Double(context.state.totalMinutes * 60))
                Group {
                    if context.state.isPaused {
                        ProgressView(value: doneFrac(context: context))
                    } else {
                        ProgressView(
                            timerInterval: start...context.state.endDate,
                            countsDown: false,
                            label: { EmptyView() },
                            currentValueLabel: { EmptyView() }
                        )
                    }
                }
                .progressViewStyle(.circular)
                .tint(W.live)
                .frame(width: 16, height: 16)
            } minimal: {
                // minimal 表示: 経過を単一ドット環で
                liveRing(context: context, size: 18, dotSize: 1.6)
            }
            .keylineTint(W.live)
        }
    }

    /// C3 ロック画面バナー: ドット環 + タスク名 + 大きな残時間。
    @ViewBuilder
    private func lockBanner(context: ActivityViewContext<TimerAttributes>) -> some View {
        HStack(spacing: 14) {
            liveRing(context: context, size: 60)
            VStack(alignment: .leading, spacing: 3) {
                Text("STR(8) · FOCUS")
                    .font(.system(size: 8.5, design: .monospaced))
                    .tracking(1.6)
                    .foregroundColor(.white.opacity(0.6))
                Text(context.attributes.taskTitle)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                Text(context.state.isPaused
                     ? "一時停止中"
                     : "起こすと一時停止" + (context.attributes.subjectName.map { " · \($0)" } ?? ""))
                    .font(.system(size: 10.5))
                    .foregroundColor(.white.opacity(0.65))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 2) {
                remainDisplay(context: context, size: 30)
                    .foregroundColor(W.live)
                Text("/ \(String(format: "%02d:00", context.state.totalMinutes))")
                    .font(.system(size: 8, design: .monospaced))
                    .tracking(1.4)
                    .foregroundColor(.white.opacity(0.6))
            }
        }
        .padding(.horizontal, 18).padding(.vertical, 16)
    }

    /// 残時間表示（endDate ベースで OS が自動更新 or 一時停止時は固定表示）。
    /// endDate 経過後は「00:00」を固定表示（Text(timerInterval:) は negative を表示し続けるため）。
    @ViewBuilder
    private func remainDisplay(context: ActivityViewContext<TimerAttributes>, size: CGFloat) -> some View {
        if context.state.isPaused {
            let m = context.state.pausedRemainingSec / 60
            let s = context.state.pausedRemainingSec % 60
            Text(String(format: "%02d:%02d", m, s))
                .font(.system(size: size, weight: .bold, design: .monospaced))
        } else if context.state.endDate <= Date.now {
            Text("00:00")
                .font(.system(size: size, weight: .bold, design: .monospaced))
        } else {
            Text(timerInterval: Date.now...context.state.endDate, countsDown: true, showsHours: false)
                .font(.system(size: size, weight: .bold, design: .monospaced))
                .monospacedDigit()
        }
    }

    /// C3 のドット環（砂時計を廃した中心の主役ビジュアル）。
    /// 中心には何も置かず、環そのもので「経過」を見せる（沈んだドット = 消化した時間）。
    @ViewBuilder
    private func liveRing(context: ActivityViewContext<TimerAttributes>, size: CGFloat, dotSize: CGFloat? = nil) -> some View {
        let r = size * 0.42
        let n = 16
        // ponytail: 装飾用の静的リング。更新頻度は OS の Live Activity 再描画に依存する。
        DotRing(
            radius: r,
            count: n,
            progress: doneFrac(context: context),
            onColor: W.live.opacity(context.state.isPaused ? 0.5 : 1.0),
            offColor: W.liveOff,
            dotSize: dotSize ?? max(size * 0.06, 2.4)
        )
        .frame(width: size, height: size)
    }

    private func doneFrac(context: ActivityViewContext<TimerAttributes>) -> Double {
        let totalSec = Double(max(1, context.state.totalMinutes * 60))
        let remain: Double = context.state.isPaused
            ? Double(context.state.pausedRemainingSec)
            : max(0, context.state.endDate.timeIntervalSinceNow)
        return max(0, min(1, 1.0 - remain / totalSec))
    }

    /// Expanded 下段の自動更新プログレス。
    @ViewBuilder
    private func progressBar(context: ActivityViewContext<TimerAttributes>) -> some View {
        let start = context.state.endDate.addingTimeInterval(-Double(context.state.totalMinutes * 60))
        VStack(alignment: .leading, spacing: 8) {
            Group {
                if context.state.isPaused {
                    ProgressView(value: doneFrac(context: context))
                } else {
                    ProgressView(
                        timerInterval: start...context.state.endDate,
                        countsDown: false,
                        label: { EmptyView() },
                        currentValueLabel: { EmptyView() }
                    )
                }
            }
            .progressViewStyle(.linear)
            .tint(W.live)
            .scaleEffect(y: 0.8)
            HStack {
                Text(context.state.isPaused ? "PAUSED" : "RUNNING")
                    .font(.system(size: 9, design: .monospaced))
                    .tracking(1.0)
                    .foregroundColor(.white.opacity(0.55))
                Spacer()
                Text("FOCUS貫通")
                    .font(.system(size: 9, design: .monospaced))
                    .tracking(1.0)
                    .foregroundColor(.white.opacity(0.55))
            }
        }
        .padding(.bottom, 2)
    }
}

// MARK: - Bundle
@main
struct str8WidgetBundle: WidgetBundle {
    var body: some Widget {
        str8Widget()
        if #available(iOS 16.1, *) {
            TimerLiveActivity()
        }
    }
}
