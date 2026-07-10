import SwiftUI
import SwiftData

@MainActor
struct AddTaskSheet: View {
    @Environment(\.modelContext) var modelContext
    @Environment(\.dismiss) var dismiss

    @Query(sort: \Category.name) var categories: [Category]

    let defaultDate: Date
    let prefillDuration: TimeInterval?

    @State private var selectedTitle: String = ""
    @State private var selectedCategory: Category? = nil
    @State private var selectedPlace: PlaceTag? = nil
    @State private var selectedPhase: SortPhase = .today
    @State private var selectedNotes: String = ""
    @State private var selectedColorHex: String? = nil
    @State private var selectedNotifications: [Int] = []
    @State private var isImportant: Bool = false

    @State private var isMoneySpecified: Bool = false
    @State private var selectedAmount: String = ""
    @State private var selectedPaymentMethod: String = ""

    @State private var isTimeSpecified: Bool = false
    @State private var selectedStartDate: Date = .now
    @State private var selectedDuration: TimeInterval = 3600
    @State private var selectedEndDate: Date = .now
    @State private var selectedRepeatPattern: String = "none"
    @State private var selectedTimeZone: String = TimeZone.current.identifier
    @State private var customNotificationMinutes: Int = 0
    @State private var isSyncingTime: Bool = false
    @State private var isTimePinned: Bool = false

    private let colorPresets: [String] = ["4F8DFD", "34C759", "FF9500", "FF2D55", "AF52DE", "8E8E93"]
    private let repeatOptions: [(String, String, String?)] = [
        ("none", "なし", nil),
        ("daily", "毎日", "FREQ=DAILY"),
        ("weekday", "平日", "FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR"),
        ("weekly", "毎週", "FREQ=WEEKLY"),
        ("monthly", "毎月", "FREQ=MONTHLY")
    ]

    init(defaultDate: Date, prefillDuration: TimeInterval? = nil) {
        self.defaultDate = defaultDate
        self.prefillDuration = prefillDuration
        _selectedStartDate = State(initialValue: defaultDate)
        _selectedEndDate = State(initialValue: defaultDate.addingTimeInterval(prefillDuration ?? 3600))
        _isTimeSpecified = State(initialValue: prefillDuration != nil)
        _selectedDuration = State(initialValue: prefillDuration ?? 3600)
    }

    var body: some View {
        NavigationStack {
            Form {
                // タイトル
                Section("タイトル") {
                    TextField("タスク名", text: $selectedTitle)
                }

                // 重要フラグ
                Section {
                    HStack {
                        Image(systemName: isImportant ? "star.fill" : "star")
                            .foregroundColor(isImportant ? .yellow : .gray)
                        Text("重要")
                        Spacer()
                        Toggle("重要", isOn: $isImportant)
                            .labelsHidden()
                    }
                }

                // カテゴリ
                Section("カテゴリ") {
                    if let selected = selectedCategory {
                        Text(selected.name)
                            .foregroundColor(Color(hex: selected.colorHex))
                    } else {
                        Text("未選択")
                            .foregroundColor(.secondary)
                    }

                    if !categories.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(categories.prefix(6)) { cat in
                                    Button(action: { selectedCategory = cat }) {
                                        Text(cat.name)
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 6)
                                            .background(
                                                RoundedRectangle(cornerRadius: 16)
                                                    .stroke(
                                                        selectedCategory?.id == cat.id ? Color(hex: cat.colorHex) : .gray.opacity(0.3),
                                                        lineWidth: selectedCategory?.id == cat.id ? 2 : 1
                                                    )
                                            )
                                            .foregroundColor(.primary)
                                    }
                                    .buttonStyle(.borderless)
                                    .accessibilityLabel("カテゴリ \(cat.name)")
                                }

                                NavigationLink(destination: CategoryPickerView(selection: $selectedCategory)) {
                                    HStack(spacing: 4) {
                                        Image(systemName: "chevron.right")
                                        Text("全て")
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(
                                        RoundedRectangle(cornerRadius: 16)
                                            .stroke(.gray.opacity(0.3), lineWidth: 1)
                                    )
                                    .foregroundColor(.secondary)
                                }
                                .buttonStyle(.borderless)
                            }
                            .padding(.vertical, 8)
                        }
                    }
                }

                // 場所
                Section("場所") {
                    NavigationLink(
                        destination: LocationPickerView(place: $selectedPlace),
                        label: {
                            HStack {
                                if let place = selectedPlace {
                                    Text(place.name)
                                    Spacer()
                                    Button(action: { selectedPlace = nil }) {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundColor(.gray)
                                    }
                                    .buttonStyle(.borderless)
                                    .accessibilityLabel("場所を削除")
                                } else {
                                    Text("場所を選択")
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    )
                }

                // 時間設定
                Section("時間") {
                    Toggle("時刻を指定", isOn: $isTimeSpecified)

                    if isTimeSpecified {
                        DatePicker(
                            "開始",
                            selection: $selectedStartDate,
                            displayedComponents: [.date, .hourAndMinute]
                        )
                        .onChange(of: selectedStartDate) {
                            if isSyncingTime { return }
                            isSyncingTime = true
                            selectedEndDate = selectedStartDate.addingTimeInterval(selectedDuration)
                            isSyncingTime = false
                        }

                        HStack {
                            Text("所要時間")
                            Spacer()
                            Stepper(value: $selectedDuration, in: 0...(24 * 3600), step: 300) {
                                Text(durationText(selectedDuration))
                            }
                        }
                        .onChange(of: selectedDuration) {
                            if isSyncingTime { return }
                            isSyncingTime = true
                            selectedEndDate = selectedStartDate.addingTimeInterval(selectedDuration)
                            isSyncingTime = false
                        }

                        Toggle("時刻厳守", isOn: $isTimePinned)

                        DatePicker(
                            "終了",
                            selection: $selectedEndDate,
                            displayedComponents: [.date, .hourAndMinute]
                        )
                        .onChange(of: selectedEndDate) {
                            if isSyncingTime { return }
                            isSyncingTime = true
                            selectedDuration = max(0, selectedEndDate.timeIntervalSince(selectedStartDate))
                            isSyncingTime = false
                        }

                        Picker("繰り返し", selection: $selectedRepeatPattern) {
                            ForEach(repeatOptions, id: \.0) { id, label, _ in
                                Text(label).tag(id)
                            }
                        }

                        Picker("タイムゾーン", selection: $selectedTimeZone) {
                            ForEach(TimeZone.knownTimeZoneIdentifiers.prefix(30), id: \.self) { tz in
                                Text(tz).tag(tz)
                            }
                        }
                    }
                }

                // お金
                Section("お金") {
                    Toggle("金額を記録", isOn: $isMoneySpecified)

                    if isMoneySpecified {
                        TextField("金額（例: 1490）", text: $selectedAmount)
                            .keyboardType(.decimalPad)
                        if selectedAmount.isEmpty {
                            Text("金額を入力してください")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } else if parsedAmount == nil {
                            Text("金額は正の数値で入力してください")
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                        TextField("支払方法（例: クレジットカード）", text: $selectedPaymentMethod)
                    }
                }

                // メモ
                Section("メモ") {
                    TextEditor(text: $selectedNotes)
                        .frame(minHeight: 100)
                }

                // 通知
                Section("通知") {
                    let presets = [
                        (5, "5分前"),
                        (15, "15分前"),
                        (60, "1時間前"),
                        (1440, "前日")
                    ]

                    ForEach(presets, id: \.0) { minutes, label in
                        HStack {
                            Image(systemName: selectedNotifications.contains(minutes) ? "checkmark.circle.fill" : "circle")
                                .foregroundColor(selectedNotifications.contains(minutes) ? .blue : .gray)
                                .accessibilityLabel("通知 \(label)")
                            Text(label)
                            Spacer()
                            Toggle("", isOn: Binding(
                                get: { selectedNotifications.contains(minutes) },
                                set: { isOn in
                                    if isOn {
                                        selectedNotifications.append(minutes)
                                        selectedNotifications.sort()
                                    } else {
                                        selectedNotifications.removeAll { $0 == minutes }
                                    }
                                }
                            ))
                            .labelsHidden()
                        }
                    }

                    HStack {
                        Text("カスタム: \(customNotificationMinutes)分前")
                        Spacer()
                        Stepper("", value: $customNotificationMinutes, in: 1...10080, step: 1)
                        Button(action: {
                            if !selectedNotifications.contains(customNotificationMinutes) {
                                selectedNotifications.append(customNotificationMinutes)
                                selectedNotifications.sort()
                            }
                            customNotificationMinutes = 0
                        }) {
                            Image(systemName: "plus.circle.fill")
                                .foregroundColor(.blue)
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("カスタム通知を追加")
                    }
                }

                // 色
                Section("色") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(colorPresets, id: \.self) { hex in
                                Button(action: { selectedColorHex = hex }) {
                                    Circle()
                                        .fill(Color(hex: hex))
                                        .frame(width: 40, height: 40)
                                        .overlay(
                                            selectedColorHex == hex
                                                ? Circle().stroke(.black, lineWidth: 2)
                                                : nil
                                        )
                                }
                                .buttonStyle(.borderless)
                                .accessibilityLabel("色 \(colorName(for: hex))")
                            }

                            Button(action: { selectedColorHex = nil }) {
                                ZStack {
                                    Circle()
                                        .fill(.gray.opacity(0.3))
                                    Text("✓")
                                        .font(.caption)
                                        .opacity(selectedColorHex == nil ? 1 : 0.5)
                                }
                                .frame(width: 40, height: 40)
                                .overlay(
                                    selectedColorHex == nil
                                        ? Circle().stroke(.black, lineWidth: 2)
                                        : nil
                                )
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("色を削除")
                        }
                        .padding(.vertical, 8)
                    }
                }

                // フェーズ
                Section("フェーズ") {
                    Picker("フェーズ", selection: $selectedPhase) {
                        ForEach(SortPhase.allCases) { phase in
                            Text(phase.label).tag(phase)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }
            .navigationTitle("タスク追加")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("追加") { addTask() }
                        .disabled(
                            selectedTitle.trimmingCharacters(in: .whitespaces).isEmpty
                            || (isMoneySpecified && parsedAmount == nil)
                        )
                }
            }
        }
    }

    private func colorName(for hex: String) -> String {
        let colorMap = [
            "4F8DFD": "青",
            "34C759": "緑",
            "FF9500": "オレンジ",
            "FF2D55": "赤",
            "AF52DE": "紫",
            "8E8E93": "グレー"
        ]
        return colorMap[hex] ?? hex
    }

    /// 金額入力の正規化＋パース。全角数字→半角、カンマ・空白除去。
    /// マイナス（半角/全角）や 0 以下は集計対象外（amount > 0 のみ計上）なのでパース失敗扱い。
    private var parsedAmount: Decimal? {
        let normalized = selectedAmount
            .applyingTransform(.fullwidthToHalfwidth, reverse: false)?
            .replacingOccurrences(of: ",", with: "")
            .trimmingCharacters(in: .whitespaces) ?? ""
        guard !normalized.isEmpty,
              !normalized.contains("-"), !normalized.contains("−"),
              let amount = Decimal(string: normalized, locale: Locale(identifier: "en_US")),
              amount > 0
        else { return nil }
        return amount
    }

    private func addTask() {
        let rruleStr = repeatOptions.first { $0.0 == selectedRepeatPattern }?.2

        let amount: Decimal? = isMoneySpecified ? parsedAmount : nil
        let paymentMethod: String? = isMoneySpecified && !selectedPaymentMethod.isEmpty ? selectedPaymentMethod.trimmingCharacters(in: .whitespaces) : nil

        let task = TaskItem(
            title: selectedTitle.trimmingCharacters(in: .whitespaces),
            category: selectedCategory,
            startDate: isTimeSpecified ? selectedStartDate : nil,
            duration: isTimeSpecified ? selectedDuration : 0,
            isAllDay: false,
            place: selectedPlace,
            phase: selectedPhase,
            status: .active,
            rrule: rruleStr,
            notes: selectedNotes,
            isImportant: isImportant,
            colorHex: selectedColorHex,
            notificationOffsets: selectedNotifications.sorted(),
            timeZoneIdentifier: isTimeSpecified ? selectedTimeZone : nil,
            amount: amount,
            paymentMethod: paymentMethod,
            isTimePinned: isTimeSpecified && isTimePinned
        )

        modelContext.insert(task)
        try? modelContext.save()

        // 金額あれば、対象月の統計を再計算
        if amount != nil {
            let targetMonth = isTimeSpecified ? selectedStartDate : .now
            MoneyStats.recompute(month: targetMonth, context: modelContext)
        }

        if !selectedNotifications.isEmpty {
            NotificationService.reschedule(for: task)
        }

        dismiss()
    }

}

#Preview {
    AddTaskSheet(defaultDate: .now)
        .modelContainer(PreviewData.container)
}
