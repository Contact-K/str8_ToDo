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
    @State private var showComposer = false
    @State private var gapPrefill: GapPrefill?

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                // Navigation header
                HStack {
                    Button(action: { date = Calendar.current.date(byAdding: .day, value: -1, to: date) ?? date }) {
                        Image(systemName: "chevron.left")
                            .font(.body)
                            .foregroundStyle(.primary)
                    }

                    Spacer()

                    Text(dayHeaderText())
                        .font(.headline)

                    Spacer()

                    Button(action: { date = Calendar.current.date(byAdding: .day, value: 1, to: date) ?? date }) {
                        Image(systemName: "chevron.right")
                            .font(.body)
                            .foregroundStyle(.primary)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color(.systemGray6))

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

            // Floating + button
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    Button(action: { showComposer = true }) {
                        Image(systemName: "plus")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 56, height: 56)
                            .background(Color.blue)
                            .clipShape(Circle())
                            .shadow(radius: 4)
                    }
                    .padding(20)
                }
            }
        }
        .sheet(isPresented: $showComposer) {
            EventComposerView(initialStart: date)
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
