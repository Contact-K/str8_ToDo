import WidgetKit
import SwiftUI
import Foundation

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

    // MARK: - System Small
    private var systemSmallView: some View {
        VStack(alignment: .leading, spacing: 8) {
            topHeadline()
            Spacer()
            HStack(spacing: 12) { statTiles() }
                .foregroundColor(.secondary)
                .padding(.horizontal, 12)
        }
        .padding(.vertical, 12)
        .containerBackground(for: .widget) { Color.clear }
    }

    // MARK: - System Medium
    private var systemMediumView: some View {
        VStack(alignment: .leading, spacing: 8) {
            topHeadline()

            if isCurrent, let bands = entry.snapshot?.bands, !bands.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(bands.prefix(5), id: \.name) { band in
                            Text(band.name)
                                .font(.caption2)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.blue.opacity(0.2))
                                .cornerRadius(4)
                        }
                    }
                    .padding(.horizontal, 12)
                }
            }

            HStack(spacing: 16) {
                statTiles(unconfirmedBold: true)
                Spacer()
            }
            .foregroundColor(.secondary)
            .padding(.horizontal, 12)
        }
        .padding(.vertical, 12)
        .containerBackground(for: .widget) { Color.clear }
    }

    // MARK: - Accessory Rectangular
    private var accessoryRectangularView: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let card = currentCard {
                Text(card.title)
                    .lineLimit(1)
                    .font(.system(.caption, design: .default))
                Text("\(timeFormatter.string(from: card.start))–\(timeFormatter.string(from: card.end))")
                    .font(.system(.caption2, design: .default))
                    .opacity(0.7)
            } else {
                Text("—")
                    .font(.system(.caption, design: .default))
            }
        }
        .containerBackground(for: .widget) {
            Color.clear
        }
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

    // MARK: - Accessory Circular
    private var accessoryCircularView: some View {
        ZStack {
            Circle()
                .fill(Color.clear)

            if isCurrent {
                Text("\(entry.snapshot?.achievementCount ?? 0)")
                    .font(.system(.title2, design: .default))
                    .fontWeight(.semibold)
            } else {
                Text("—")
                    .font(.system(.title2, design: .default))
                    .fontWeight(.semibold)
            }
        }
        .containerBackground(for: .widget) {
            Color.clear
        }
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
