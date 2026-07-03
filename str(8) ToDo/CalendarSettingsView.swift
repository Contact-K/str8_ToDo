import SwiftUI
import SwiftData

struct CalendarSettingsView: View {
    @Environment(\.modelContext) var modelContext
    @Query(sort: \Category.name) var categories: [Category]

    @AppStorage(AppSettingsKey.syncSystemCalendar) var syncSystemCalendar = AppSettingsKey.syncSystemCalendarDefault
    @AppStorage(AppSettingsKey.syncWeather) var syncWeather = AppSettingsKey.syncWeatherDefault
    @AppStorage(AppSettingsKey.enableNotifications) var enableNotifications = AppSettingsKey.enableNotificationsDefault
    @AppStorage(AppSettingsKey.weekStartMinutes) var weekStartMinutes = AppSettingsKey.weekStartMinutesDefault
    @AppStorage(AppSettingsKey.weekEndMinutes) var weekEndMinutes = AppSettingsKey.weekEndMinutesDefault
    @AppStorage(AppSettingsKey.weekBandIntervalHours) var weekBandIntervalHours = AppSettingsKey.weekBandIntervalHoursDefault

    @State private var startDate = Date()
    @State private var endDate = Date()
    @State private var eventKit = EventKitService()
    @State private var weather = WeatherProvider()

    var body: some View {
        Form {
            // MARK: - 同期セクション
            Section(header: Text("同期")) {
                // システムカレンダー同期
                HStack {
                    Toggle("システムカレンダー同期", isOn: $syncSystemCalendar)
                        .onChange(of: syncSystemCalendar) { oldValue, newValue in
                            if newValue {
                                Task {
                                    if await eventKit.requestAccess() {
                                        eventKit.sync(into: modelContext)
                                        eventKit.observeChanges(into: modelContext)
                                    }
                                }
                            }
                        }
                }

                // システムカレンダー同期状態
                HStack {
                    Text("状態")
                    Spacer()
                    HStack(spacing: 6) {
                        Circle()
                            .fill(authStateColor())
                            .frame(width: 8, height: 8)
                        Text(authStateLabel())
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                // 今すぐ同期ボタン
                Button(action: {
                    Task {
                        if await eventKit.requestAccess() {
                            eventKit.sync(into: modelContext)
                            eventKit.observeChanges(into: modelContext)
                        }
                    }
                }) {
                    HStack {
                        Image(systemName: "arrow.clockwise")
                        Text("今すぐ同期")
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                }
                .buttonStyle(.bordered)

                // 天気同期
                HStack {
                    Toggle("天気を同期", isOn: $syncWeather)
                        .onChange(of: syncWeather) { oldValue, newValue in
                            if newValue {
                                Task {
                                    await weather.refresh()
                                }
                            }
                        }
                }

                // 天気同期状態
                HStack {
                    Text("状態")
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        HStack(spacing: 4) {
                            Text(weather.status.rawValue)
                                .font(.caption)
                                .foregroundColor(.secondary)
                            if let statusDetail = weather.statusDetail {
                                Text(statusDetail)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            if let temp = weather.temperatureText {
                                Text(temp)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        if let lastUpdated = weather.lastUpdated {
                            Text("更新: \(formattedTime(lastUpdated))")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                // 天気を取得ボタン
                Button(action: {
                    Task {
                        await weather.refresh()
                    }
                }) {
                    HStack {
                        Image(systemName: "cloud.fill")
                        Text("天気を取得")
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                }
                .buttonStyle(.bordered)

                // WeatherKit注記
                Text("※WeatherKitのCapability追加が必要")
                    .font(.caption2)
                    .foregroundColor(.secondary)

                // 通知
                Toggle("通知", isOn: $enableNotifications)
                    .onChange(of: enableNotifications) { oldValue, newValue in
                        if newValue {
                            Task {
                                await NotificationService.requestAuthorization()
                            }
                        }
                    }
            }

            // MARK: - 週ビュー表示時間セクション
            Section(header: Text("週ビュー表示時間")) {
                HStack {
                    Text("開始時刻")
                    Spacer()
                    DatePicker("", selection: $startDate, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                        .onChange(of: startDate) { oldValue, newValue in
                            weekStartMinutes = minutesFromDate(newValue)
                        }
                    Text(hhmm(weekStartMinutes))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                HStack {
                    Text("終了時刻")
                    Spacer()
                    DatePicker("", selection: $endDate, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                        .onChange(of: endDate) { oldValue, newValue in
                            weekEndMinutes = minutesFromDate(newValue)
                        }
                    Text(hhmm(weekEndMinutes))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                HStack {
                    Text("区切り間隔")
                    Spacer()
                    Stepper(value: $weekBandIntervalHours, in: 1...12) {
                        Text("\(weekBandIntervalHours)時間おき")
                    }
                }
            }

            // MARK: - カテゴリ色セクション
            Section(header: Text("カテゴリ色")) {
                ForEach(categories) { category in
                    HStack(spacing: 12) {
                        Text(category.name)
                            .lineLimit(1)

                        Spacer()

                        // 現在色スウォッチ
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color(hex: category.colorHex))
                            .frame(width: 24, height: 24)

                        // プリセットhexスウォッチ群
                        HStack(spacing: 8) {
                            ForEach(["#4F8DFD", "#34C759", "#FF9500", "#FF2D55", "#AF52DE", "#8E8E93"], id: \.self) { hex in
                                Button(action: {
                                    category.colorHex = hex
                                    try? modelContext.save()
                                }) {
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(Color(hex: hex))
                                        .frame(width: 20, height: 20)
                                        .overlay(
                                            category.colorHex == hex
                                                ? RoundedRectangle(cornerRadius: 6)
                                                    .stroke(Color.primary, lineWidth: 2)
                                                : nil
                                        )
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("カレンダー設定")
        .onAppear {
            startDate = dateFromMinutes(weekStartMinutes)
            endDate = dateFromMinutes(weekEndMinutes)
        }
    }

    // MARK: - ヘルパー
    private func minutesFromDate(_ date: Date) -> Int {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.hour, .minute], from: date)
        return (components.hour ?? 0) * 60 + (components.minute ?? 0)
    }

    private func dateFromMinutes(_ minutes: Int) -> Date {
        let hour = minutes / 60
        let minute = minutes % 60
        var components = DateComponents()
        components.hour = hour
        components.minute = minute
        return Calendar.current.date(from: components) ?? Date()
    }

    private func authStateColor() -> Color {
        switch eventKit.authState {
        case .authorized:
            return .green
        case .denied:
            return .red
        case .unknown:
            return .gray
        }
    }

    private func authStateLabel() -> String {
        switch eventKit.authState {
        case .authorized:
            return "許可済み"
        case .denied:
            return "拒否"
        case .unknown:
            return "未確認"
        }
    }

    private func formattedTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

#Preview {
    NavigationStack {
        CalendarSettingsView()
    }
    .modelContainer(PreviewData.container)
}
