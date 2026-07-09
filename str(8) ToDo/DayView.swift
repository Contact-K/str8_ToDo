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
    @Query private var weatherCache: [WeatherCache]
    @State private var showAddTaskSheet = false
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

                // Weather bar
                HStack(spacing: 8) {
                    let cal = Calendar.current
                    let displayDay = cal.startOfDay(for: date)
                    if let cache = weatherCache.first(where: { cal.isDate($0.day, inSameDayAs: displayDay) }) {
                        Image(systemName: cache.symbolName)
                            .font(.system(size: 14))
                            .foregroundStyle(.orange)
                        Text("最高\(Int(cache.highCelsius))°/最低\(Int(cache.lowCelsius))°")
                            .font(.caption)
                            .foregroundStyle(.primary)
                        Spacer()
                        WeatherFreshnessLabel(fetchedAt: cache.fetchedAt)
                    } else {
                        Image(systemName: "cloud.sun")
                            .font(.system(size: 14))
                            .foregroundStyle(.gray.opacity(0.3))
                        Text("天気情報なし")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color(.systemGray5))
                .cornerRadius(8)
                .padding(12)

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
                    Button(action: { showAddTaskSheet = true }) {
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
        .sheet(isPresented: $showAddTaskSheet) {
            AddTaskSheet(defaultDate: date)
        }
        .sheet(item: $gapPrefill) { prefill in
            AddTaskSheet(
                defaultDate: prefill.start,
                prefillDuration: prefill.duration
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
