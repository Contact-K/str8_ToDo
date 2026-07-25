import SwiftUI
import SwiftData
import EventKit
import UIKit

struct CalendarSelectionView: View {
    let eventKit: EventKitService

    @Environment(\.modelContext) private var context
    @Environment(\.colorScheme) private var scheme
    private var c: S8Palette { S8Palette.of(scheme) }

    @State private var excluded = Set(
        UserDefaults.standard.stringArray(forKey: AppSettingsKey.excludedCalendarIDs) ?? []
    )

    var body: some View {
        VStack(spacing: 0) {
            S8TopBar("同期するカレンダー", sub: "calendar · sync") { EmptyView() }
            ScrollView {
                VStack(spacing: 0) {
                    if eventKit.authState == .authorized {
                        calendarList
                    } else {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("同期するカレンダーを選ぶには、設定でカレンダーへのアクセスを許可してください。")
                                .font(S8Font.jp(13))
                                .foregroundColor(c.fg2)
                                .fixedSize(horizontal: false, vertical: true)
                            S8Button("設定でアクセスを許可", icon: "settings", variant: .secondary) {
                                UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!)
                            }
                        }
                        .padding(.horizontal, 24)
                        .padding(.top, 24)
                    }
                    Color.clear.frame(height: 32)
                }
            }
        }
    }

    private var calendarList: some View {
        let groups = Dictionary(grouping: eventKit.eventCalendars) { $0.source.title }
        return ForEach(groups.keys.sorted(), id: \.self) { source in
            S8SectionLabel(text: source)
            let calendars = groups[source, default: []].sorted {
                $0.title.localizedStandardCompare($1.title) == .orderedAscending
            }
            ForEach(Array(calendars.enumerated()), id: \.element.calendarIdentifier) { index, calendar in
                HStack(spacing: 14) {
                    Circle()
                        .fill(Color(cgColor: calendar.cgColor ?? UIColor.systemGray.cgColor))
                        .frame(width: 10, height: 10)
                    Text(calendar.title)
                        .font(S8Font.jp(15))
                        .foregroundColor(c.fg1)
                    Spacer(minLength: 8)
                    S8Toggle(on: !excluded.contains(calendar.calendarIdentifier)) {
                        toggle(calendar)
                    }
                    .accessibilityLabel(calendar.title)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 15)
                if index < calendars.count - 1 { S8Rule() }
            }
        }
    }

    private func toggle(_ calendar: EKCalendar) {
        if excluded.contains(calendar.calendarIdentifier) {
            excluded.remove(calendar.calendarIdentifier)
        } else {
            excluded.insert(calendar.calendarIdentifier)
        }
        UserDefaults.standard.set(Array(excluded), forKey: AppSettingsKey.excludedCalendarIDs)
        eventKit.sync(into: context)
    }
}
