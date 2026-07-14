import WidgetKit
import SwiftUI
import Foundation

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
}

private enum WF {
    static func mono(_ size: CGFloat, _ w: Font.Weight = .regular) -> Font {
        .system(size: size, weight: w, design: .monospaced)
    }
    static func jp(_ size: CGFloat, _ w: Font.Weight = .medium) -> Font {
        .system(size: size, weight: w)
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

        // 各カードの開始/終了境界でエントリを事前生成（WidgetShared の共有ロジック）。
        if let snapshot = snapshot {
            for boundary in snapshot.timelineBoundaries(after: now) {
                entries.append(StrEntry(date: boundary, snapshot: snapshot))
            }
        }

        // Reload at next day 00:00
        let reloadTime = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: now)) ?? now.addingTimeInterval(86400)
        let timeline = Timeline(entries: entries, policy: .after(reloadTime))
        completion(timeline)
    }
}

// MARK: - View
struct StrWidgetView: View {
    let entry: StrEntry
    @Environment(\.widgetFamily) var family

    // Helper: current card based on entry.date（WidgetShared の共有ロジック）
    private var currentCard: WidgetSnapshot.Card? {
        entry.snapshot?.currentCard(at: entry.date)
    }

    // Helper: snapshot が有効で新鮮か判定
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

    // MARK: - System Small / Medium 共通ヘッダー
    @ViewBuilder
    private func topHeadline() -> some View {
        if let card = currentCard {
            cardView(card)
        } else if isCurrent {
            Text("今日の予定は完了")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .padding(.horizontal, 12)
        } else {
            Text("アプリで更新")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .padding(.horizontal, 12)
        }
    }

    /// 達成／未確定の統計チップ列。`isCurrent` が false の時は "—" を出す。
    @ViewBuilder
    private func statTiles(unconfirmedBold: Bool = false) -> some View {
        let achieve = isCurrent ? "\(entry.snapshot?.achievementCount ?? 0)" : "—"
        let unconfirm = isCurrent ? "\(entry.snapshot?.unconfirmedCount ?? 0)" : "—"
        Text("達成 \(achieve)").font(.caption2)
        Text("未確定 \(unconfirm)")
            .font(.caption2)
            .fontWeight(unconfirmedBold ? .semibold : .regular)
    }

    // MARK: - System Small （Handoff 08a）
    private var systemSmallView: some View {
        VStack(alignment: .leading, spacing: 0) {
            // ヘッダ: dot + NEXT cap
            HStack(spacing: 5) {
                Circle().fill(W.accent).frame(width: 6, height: 6)
                Text("NEXT").font(WF.mono(8, .regular)).tracking(1.4).foregroundColor(W.fg3)
            }
            if let card = currentCard {
                Text(remainText(for: card))
                    .font(WF.mono(21, .bold))
                    .foregroundColor(W.accentInk)
                    .padding(.top, 8)
                Text(card.title)
                    .font(WF.jp(12.5, .bold))
                    .foregroundColor(W.fg1)
                    .lineLimit(1)
                    .padding(.top, 5)
                Text("\(timeFormatter.string(from: card.start))–\(timeFormatter.string(from: card.end))")
                    .font(WF.mono(9.5))
                    .foregroundColor(W.fg3)
            } else if isCurrent {
                Spacer(minLength: 0)
                Text("今日の予定は完了").font(WF.jp(11)).foregroundColor(W.fg3)
            } else {
                Spacer(minLength: 0)
                Text("アプリで更新").font(WF.jp(11)).foregroundColor(W.fg3)
            }
            Spacer(minLength: 0)
            Divider().background(W.line)
            HStack(spacing: 8) {
                statPair(label: "達成", value: "\(entry.snapshot?.achievementCount ?? 0)", strong: false)
                statPair(label: "未確定", value: "\(entry.snapshot?.unconfirmedCount ?? 0)", strong: true)
            }
            .padding(.top, 8)
        }
        .containerBackground(for: .widget) { W.paper }
    }

    // MARK: - System Medium （Handoff 08a）
    private var systemMediumView: some View {
        HStack(spacing: 14) {
            // 左: NEXT
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 5) {
                    Circle().fill(W.accent).frame(width: 6, height: 6)
                    Text("NEXT").font(WF.mono(8, .regular)).tracking(1.4).foregroundColor(W.fg3)
                }
                if let card = currentCard {
                    Text(card.title)
                        .font(WF.jp(14.5, .bold))
                        .foregroundColor(W.fg1)
                        .lineLimit(1)
                        .padding(.top, 8)
                    HStack(spacing: 4) {
                        Text("\(timeFormatter.string(from: card.start))–\(timeFormatter.string(from: card.end))")
                            .font(WF.mono(10))
                            .foregroundColor(W.fg3)
                        Text("· あと\(remainMinutes(for: card))分")
                            .font(WF.mono(10))
                            .foregroundColor(W.fg3)
                    }
                    .padding(.top, 2)
                    // 出発逆算は snapshot に無ければ省略
                } else if isCurrent {
                    Text("今日の予定は完了").font(WF.jp(12)).foregroundColor(W.fg3)
                        .padding(.top, 8)
                }
                Spacer(minLength: 0)
                HStack(spacing: 10) {
                    statPair(label: "達成", value: "\(entry.snapshot?.achievementCount ?? 0)/\(bandsCount)", strong: false)
                    statPair(label: "未確定", value: "\(entry.snapshot?.unconfirmedCount ?? 0)", strong: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Rectangle().fill(W.line).frame(width: 1)

            // 右: 今日の枠
            VStack(alignment: .leading, spacing: 5) {
                Text("今日の枠").font(WF.mono(8, .regular)).tracking(1.4).foregroundColor(W.fg3)
                ForEach(Array((entry.snapshot?.bands ?? []).prefix(3).enumerated()), id: \.offset) { i, band in
                    HStack(spacing: 6) {
                        // 単純に「1つ目は達成/2つ目は次/3つ目は未来」風の見た目
                        if i == 0 {
                            ZStack {
                                Circle().fill(W.ok)
                                Image(systemName: "checkmark")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundColor(W.paper)
                            }
                            .frame(width: 16, height: 16)
                            Text(band.name).font(WF.jp(10.5)).foregroundColor(W.fg3).strikethrough()
                        } else if i == 1 {
                            Circle().strokeBorder(W.accent, lineWidth: 1.5).frame(width: 16, height: 16)
                            Text(band.name).font(WF.jp(10.5, .bold)).foregroundColor(W.fg1)
                        } else {
                            Circle().strokeBorder(W.lineStrong, lineWidth: 1).frame(width: 16, height: 16)
                            Text(band.name).font(WF.jp(10.5)).foregroundColor(W.fg2)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .containerBackground(for: .widget) { W.paper }
    }

    private var bandsCount: Int { entry.snapshot?.bands.count ?? 0 }

    /// 残り分（分未満なら「0」）。
    private func remainMinutes(for card: WidgetSnapshot.Card) -> Int {
        let mins = Int(card.start.timeIntervalSince(entry.date) / 60)
        return max(0, mins)
    }

    /// Handoff 08a: -45分 のような差分表示。過去なら +N。
    private func remainText(for card: WidgetSnapshot.Card) -> String {
        let mins = Int((card.start.timeIntervalSince(entry.date) / 60).rounded())
        return mins >= 0 ? "−\(mins)分" : "+\(-mins)分"
    }

    /// 達成 X / 未確定 Y の mono キャップ + 値。
    private func statPair(label: String, value: String, strong: Bool) -> some View {
        HStack(spacing: 4) {
            Text(label).font(WF.mono(8.5)).tracking(1.0).foregroundColor(W.fg3)
            Text(value)
                .font(WF.mono(8.5, strong ? .bold : .regular))
                .foregroundColor(strong ? W.accentInk : W.fg1)
        }
    }

    // MARK: - Accessory Rectangular（Handoff 08b: NEXT · DEPART の集約リードアウト）
    private var accessoryRectangularView: some View {
        VStack(alignment: .leading, spacing: 3) {
            if let card = currentCard {
                Text("NEXT · あと\(remainMinutes(for: card))分")
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
    // accessoryInline はシステムが描画するため containerBackground 非対応。
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

    // MARK: - Accessory Circular（Handoff 08b: 達成ゲージ）
    private var accessoryCircularView: some View {
        let done = entry.snapshot?.achievementCount ?? 0
        let bandsN = max(1, bandsCount)
        let fraction = min(Double(done) / Double(bandsN), 1)
        return ZStack {
            Circle().stroke(Color.white.opacity(0.25), lineWidth: 5)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(Color.white, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(-90))
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

    // MARK: - Helper
    private func cardView(_ card: WidgetSnapshot.Card) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text(card.title)
                    .font(.subheadline)
                    .lineLimit(2)
                if card.isTimePinned {
                    Image(systemName: "pin.fill")
                        .font(.caption2)
                        .accessibilityLabel("時刻厳守")
                }
            }
            Text("\(timeFormatter.string(from: card.start))–\(timeFormatter.string(from: card.end))")
                .font(.caption)
                .opacity(0.7)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            card.colorHex.map { Color(hex: $0).opacity(0.15) } ?? Color.gray.opacity(0.1)
        )
        .cornerRadius(6)
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

// MARK: - Bundle
@main
struct str8WidgetBundle: WidgetBundle {
    var body: some Widget {
        str8Widget()
    }
}
