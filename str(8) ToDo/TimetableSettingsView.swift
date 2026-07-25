import SwiftUI
import SwiftData

struct TimetableSettingsView: View {
    @Environment(\.modelContext) var modelContext
    @Environment(\.colorScheme) private var scheme
    private var c: S8Palette { S8Palette.of(scheme) }
    @Query(sort: \BandTemplate.name) private var templates: [BandTemplate]
    @Query private var assignments: [BandAssignment]

    // 特定日差し替え UI
    @State private var showDateSpecificPicker = false
    @State private var selectedDateForAssignment = Date()
    @State private var selectedTemplateForDate: UUID?

    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateStyle = .medium
        return formatter
    }()

    var body: some View {
        VStack(spacing: 0) {
            S8TopBar("時間割", sub: "timetable") { EmptyView() }
            ScrollView {
                VStack(spacing: 0) {
                    // MARK: - マイ時間割セクション
                    S8SectionLabel(text: "マイ時間割")
                    ForEach(templates) { template in
                        HStack(spacing: 8) {
                            NavigationLink(destination: BandTemplateEditorView(template: template)) {
                                HStack(spacing: 14) {
                                    S8Icon(name: "calendar", size: 20, color: c.fg2)
                                    Text(template.name)
                                        .font(S8Font.jp(15))
                                        .foregroundColor(c.fg1)
                                    Spacer()
                                    Text("\(template.bands.count)枠")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    S8Icon(name: "chevron-right", size: 16, color: c.fg3)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)

                            Button(action: {
                                modelContext.delete(template)
                                try? modelContext.save()
                            }) {
                                S8Icon(name: "trash", size: 14, color: c.fg3).padding(5)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 24)
                        .padding(.vertical, 15)
                    }

                    if !templates.isEmpty { S8Rule() }
                    S8SetRow(icon: "plus", label: "テンプレートを追加", trailing: {
                        EmptyView()
                    }, onTap: {
                        modelContext.insert(BandTemplate(name: "新しいテンプレート"))
                        try? modelContext.save()
                    })

                    // MARK: - 曜日割当セクション
                    S8SectionLabel(text: "曜日割当")
                    ForEach(1...7, id: \.self) { weekday in
                        S8SetRow(icon: "calendar", label: weekdayLabel(weekday)) {
                            S8Picker(
                                selection: weekdayTemplateBinding(weekday),
                                options: [(nil as UUID?, "なし")] + templates.map { ($0.id as UUID?, $0.name) },
                                style: .sheet,
                                placeholder: "テンプレート"
                            )
                        }
                        if weekday < 7 { S8Rule() }
                    }

                    // MARK: - 特定日差し替えセクション
                    S8SectionLabel(text: "特定日の差し替え")
                    ForEach(assignments.filter { $0.date != nil }.sorted { ($0.date ?? .distantPast) < ($1.date ?? .distantPast) }) { assignment in
                        HStack(spacing: 14) {
                            S8Icon(name: "calendar", size: 20, color: c.fg2)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(assignment.date.map { dateFormatter.string(from: $0) } ?? "不明")
                                    .font(S8Font.jp(15))
                                    .foregroundColor(c.fg1)
                                Text(assignment.template?.name ?? "なし")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Button(action: {
                                modelContext.delete(assignment)
                                try? modelContext.save()
                            }) {
                                S8Icon(name: "trash", size: 14, color: c.fg3).padding(5)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 24)
                        .padding(.vertical, 15)
                    }

                    if assignments.contains(where: { $0.date != nil }) { S8Rule() }
                    S8SetRow(icon: "plus", label: "特定日の差し替えを追加", trailing: {
                        EmptyView()
                    }, onTap: {
                        showDateSpecificPicker = true
                        selectedDateForAssignment = Date()
                        selectedTemplateForDate = nil
                    })

                    Color.clear.frame(height: 32)
                }
            }
        }
        .sheet(isPresented: $showDateSpecificPicker) {
            NavigationStack {
                Form {
                    Section("日付") {
                        HStack {
                            Text("日付を選択")
                            Spacer()
                            S8DatePicker(date: $selectedDateForAssignment, showTime: false)
                        }
                    }
                    Section("テンプレート") {
                        HStack {
                            Text("テンプレートを選択")
                            Spacer()
                            S8Picker(
                                selection: $selectedTemplateForDate,
                                options: [(nil as UUID?, "なし")] + templates.map { ($0.id as UUID?, $0.name) },
                                style: .sheet,
                                placeholder: "選択"
                            )
                        }
                    }
                }
                .navigationTitle("特定日の差し替え")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("キャンセル") {
                            showDateSpecificPicker = false
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("保存") {
                            if let templateID = selectedTemplateForDate,
                               let template = templates.first(where: { $0.id == templateID }) {
                                // 同日の既存割当があれば update、なければ insert（重複行を作らない）
                                let dayStart = Calendar.current.startOfDay(for: selectedDateForAssignment)
                                if let existing = assignments.first(where: { $0.date == dayStart }) {
                                    existing.template = template
                                } else {
                                    modelContext.insert(BandAssignment(date: selectedDateForAssignment, template: template))
                                }
                                try? modelContext.save()
                            }
                            showDateSpecificPicker = false
                        }
                    }
                }
            }
            .presentationDetents([.medium])
        }
    }

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
}

// MARK: - 枠テンプレートエディタ

struct BandTemplateEditorView: View {
    @Bindable var template: BandTemplate
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        Form {
            Section {
                TextField("テンプレート名", text: $template.name)
                    // 空名のまま離脱したらデフォルト名で保存（空テンプレ名を作らせない）
                    .onSubmit { normalizeName() }
            } header: {
                Text("テンプレート名")
            } footer: {
                if template.name.trimmingCharacters(in: .whitespaces).isEmpty {
                    Text("名称は空にできません。空のままだと自動命名されます。")
                        .foregroundColor(.secondary)
                }
            }

            Section("枠") {
                if template.orderedBands.isEmpty {
                    Text("枠がありません。「枠を追加」で作成してください。")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                ForEach(template.orderedBands) { band in
                    BandRowEditor(band: band)
                }
                .onDelete { offsets in
                    let bands = template.orderedBands
                    offsets.map { bands[$0] }.forEach(modelContext.delete)
                    try? modelContext.save()
                }

                Button("枠を追加") {
                    // 末尾（最大 endMinutes）の後ろに60分枠を置く。開始<終了は clamp で保証。
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
        .navigationTitle(template.name.isEmpty ? "（無題）" : template.name)
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { normalizeName() }
    }

    /// 空テンプレ名を防ぐ。空白のみなら自動命名して save。
    private func normalizeName() {
        if template.name.trimmingCharacters(in: .whitespaces).isEmpty {
            template.name = "名称未設定"
        }
        try? modelContext.save()
    }
}

/// 枠1行の編集（名前＋開始/終了時刻）。
// ponytail: DatePicker は 24:00 を表現できないため終了 24:00 は 0:00 と表示される（保存値は維持）
// ponytail: 時刻のみ編集用の S8TimePicker が未実装のため、ここだけ iOS DatePicker を維持。
// バンドテンプレ編集は「マイ時間割」深い下層で露出が低く、後回しの許容範囲。専用コンポーネント作成時に置換。
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
        TimetableSettingsView()
    }
    .modelContainer(PreviewData.container)
}
