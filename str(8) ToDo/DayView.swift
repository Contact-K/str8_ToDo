import SwiftUI
import SwiftData

struct GapPrefill: Identifiable {
    let id = UUID()
    let start: Date
    let duration: TimeInterval
}

struct DayView: View {
    @Binding var date: Date
    var morph: Namespace.ID? = nil
    var categoryFilter: Set<UUID>? = nil
    var onSelectTask: ((TaskItem) -> Void)? = nil

    @Environment(\.modelContext) private var context
    @Environment(\.colorScheme) private var scheme
    @State private var gapPrefill: GapPrefill?

    var body: some View {
        let c = S8Palette.of(scheme)
        VStack(spacing: 0) {
            // Navigation header
            HStack {
                Button(action: { date = Calendar.current.date(byAdding: .day, value: -1, to: date) ?? date }) {
                    Image(systemName: "chevron.left")
                        .font(.body)
                        .foregroundStyle(c.accent)
                }

                Spacer()

                Text(dayHeaderText())
                    .font(.headline)
                    .foregroundStyle(c.fg1)

                Spacer()

                Button(action: { date = Calendar.current.date(byAdding: .day, value: 1, to: date) ?? date }) {
                    Image(systemName: "chevron.right")
                        .font(.body)
                        .foregroundStyle(c.accent)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(c.surface2)

            // Agenda view
            DayAgendaView(
                date: date,
                morph: morph,
                categoryFilter: categoryFilter,
                onSelectTask: onSelectTask,
                onTapGap: { start, duration in
                    gapPrefill = GapPrefill(start: start, duration: duration)
                }
            )
        }
        .sheet(item: $gapPrefill) { prefill in
            EventComposerView(
                initialStart: prefill.start,
                initialDuration: prefill.duration
            )
        }
    }

    private static let headerFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "M月d日 (E)"
        formatter.locale = Locale(identifier: "ja_JP")
        return formatter
    }()

    private func dayHeaderText() -> String {
        Self.headerFormatter.string(from: date)
    }
}

#Preview {
    NavigationStack {
        DayView(date: .constant(.now))
    }
    .modelContainer(PreviewData.container)
}
