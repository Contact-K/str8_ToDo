import SwiftUI
import SwiftData

struct CalendarSettingsView: View {
    @Environment(\.modelContext) var modelContext
    @Query(sort: \Category.name) var categories: [Category]
    @Query(sort: \BandTemplate.name) private var templates: [BandTemplate]
    @Query private var assignments: [BandAssignment]

    @AppStorage(AppSettingsKey.syncSystemCalendar) var syncSystemCalendar = AppSettingsKey.syncSystemCalendarDefault
    @AppStorage(AppSettingsKey.syncWeather) var syncWeather = AppSettingsKey.syncWeatherDefault
    @AppStorage(AppSettingsKey.enableNotifications) var enableNotifications = AppSettingsKey.enableNotificationsDefault

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

            // MARK: - マイ時間割セクション
            Section(header: Text("マイ時間割")) {
                ForEach(templates) { template in
                    NavigationLink(destination: BandTemplateEditorView(template: template)) {
                        HStack {
                            Text(template.name)
                            Spacer()
                            Text("\(template.bands.count)枠")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .onDelete { offsets in
                    offsets.map { templates[$0] }.forEach(modelContext.delete)
                    try? modelContext.save()
                }

                Button("テンプレートを追加") {
                    modelContext.insert(BandTemplate(name: "新しいテンプレート"))
                    try? modelContext.save()
                }
            }

            // MARK: - 曜日割当セクション
            Section(header: Text("曜日割当")) {
                ForEach(1...7, id: \.self) { weekday in
                    Picker(weekdayLabel(weekday), selection: weekdayTemplateBinding(weekday)) {
                        Text("なし").tag(nil as UUID?)
                        ForEach(templates) { template in
                            Text(template.name).tag(template.id as UUID?)
                        }
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
    }

    // MARK: - ヘルパー

    private func weekdayLabel(_ weekday: Int) -> String {
        ["日", "月", "火", "水", "木", "金", "土"][weekday - 1] + "曜日"
    }

    /// 曜日デフォルト割当の Picker バインディング。なし選択で削除、未存在なら作成。
    private func weekdayTemplateBinding(_ weekday: Int) -> Binding<UUID?> {
        Binding(
            get: { assignments.first { $0.weekday == weekday }?.template?.id },
            set: { newID in
                let existing = assignments.filter { $0.weekday == weekday }
                if let newID, let template = templates.first(where: { $0.id == newID }) {
                    if let row = existing.first {
                        row.template = template
                        existing.dropFirst().forEach(modelContext.delete)  // 重複行は掃除
                    } else {
                        modelContext.insert(BandAssignment(weekday: weekday, template: template))
                    }
                } else {
                    existing.forEach(modelContext.delete)
                }
                try? modelContext.save()
            }
        )
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

// MARK: - 枠テンプレートエディタ（最小版、磨き込みは P9）

struct BandTemplateEditorView: View {
    @Bindable var template: BandTemplate
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        Form {
            Section("テンプレート名") {
                TextField("テンプレート名", text: $template.name)
            }

            Section("枠") {
                ForEach(template.orderedBands) { band in
                    BandRowEditor(band: band)
                }
                .onDelete { offsets in
                    let bands = template.orderedBands
                    offsets.map { bands[$0] }.forEach(modelContext.delete)
                    try? modelContext.save()
                }

                Button("枠を追加") {
                    // 末尾（最大 endMinutes）の後ろに60分枠を置く
                    let start = min(template.bands.map(\.endMinutes).max() ?? 9 * 60, 1380)
                    let band = Band(name: "枠\(template.bands.count + 1)",
                                    startMinutes: start,
                                    endMinutes: min(start + 60, 1440))
                    band.template = template
                    modelContext.insert(band)
                    try? modelContext.save()
                }
            }
        }
        .navigationTitle(template.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// 枠1行の編集（名前＋開始/終了時刻）。
// ponytail: DatePicker は 24:00 を表現できないため終了 24:00 は 0:00 と表示される（保存値は維持）
struct BandRowEditor: View {
    @Bindable var band: Band

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField("枠名", text: $band.name)

            HStack {
                // 終了<開始 と隣接枠との重複はクランプで防ぐ（最低5分幅）
                DatePicker("開始",
                           selection: minuteBinding($band.startMinutes, clamp: {
                               max(neighborBounds.lower, min($0, band.endMinutes - 5))
                           }),
                           displayedComponents: .hourAndMinute)
                DatePicker("終了",
                           selection: minuteBinding($band.endMinutes, clamp: {
                               min(neighborBounds.upper, max($0, band.startMinutes + 5))
                           }),
                           displayedComponents: .hourAndMinute)
            }
            .font(.caption)
        }
        .padding(.vertical, 2)
    }

    /// startMinutes ソートでの前枠 endMinutes / 次枠 startMinutes（隣接枠との重複防止の境界）。
    private var neighborBounds: (lower: Int, upper: Int) {
        let siblings = band.template?.orderedBands ?? [band]
        guard let idx = siblings.firstIndex(where: { $0.id == band.id }) else { return (0, 1440) }
        let lower = idx > 0 ? siblings[idx - 1].endMinutes : 0
        let upper = idx + 1 < siblings.count ? siblings[idx + 1].startMinutes : 1440
        return (lower, upper)
    }

    private func minuteBinding(_ minutes: Binding<Int>, clamp: @escaping (Int) -> Int) -> Binding<Date> {
        Binding(
            get: {
                var components = DateComponents()
                components.hour = (minutes.wrappedValue % 1440) / 60
                components.minute = minutes.wrappedValue % 60
                return Calendar.current.date(from: components) ?? .now
            },
            set: { date in
                let components = Calendar.current.dateComponents([.hour, .minute], from: date)
                minutes.wrappedValue = clamp((components.hour ?? 0) * 60 + (components.minute ?? 0))
            }
        )
    }
}

#Preview {
    NavigationStack {
        CalendarSettingsView()
    }
    .modelContainer(PreviewData.container)
}
