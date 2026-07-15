//
//  EventComposerView.swift
//  str8ToDo
//
//  イベント作成シート（企画書 2026-07-07 新設）E0+E1。旧 AddTaskSheet の項目連続 Form を、
//  what（タイトル）常時表示 + when/where/which/who/how/other の概要タイル + フォーカス編集
//  シートへ置き換える（P15）。
//

import Foundation
import SwiftUI
import SwiftData

/// タイルグリッド ⇄ フォーカス編集シートが共有する編集中の草稿。
/// @Observable にして EventComposerView と ComposerFocusView の両方から @Bindable で参照する。
@Observable
final class ComposerDraft {
    var title: String = ""

    // when
    var isTimeSpecified: Bool
    var startDate: Date
    var duration: TimeInterval
    var isTimePinned: Bool = false
    var repeatPattern: String = "none"
    var notificationOffsets: [Int] = []

    // where
    var place: PlaceTag?

    // which
    var category: Category?
    var profile: Profile?

    // who
    var participantNames: [String] = []

    // how
    var isImportant: Bool = false
    var amountText: String = ""
    var paymentMethod: String = ""

    // other
    var notes: String = ""
    var colorHex: String?

    /// 新規作成（空きカード等からのプリフィル対応）。
    init(defaultDate: Date, prefillDuration: TimeInterval?) {
        self.startDate = defaultDate
        self.duration = prefillDuration ?? 3600
        self.isTimeSpecified = prefillDuration != nil
    }

    /// 既存タスクの値で初期化（編集導線は P18 で TaskDetailView から接続）。
    init(task: TaskItem) {
        title = task.title
        isTimeSpecified = task.startDate != nil
        startDate = task.startDate ?? .now
        duration = task.duration > 0 ? task.duration : 3600
        isTimePinned = task.isTimePinned
        repeatPattern = EventComposerView.repeatOptions.first { $0.2 == task.rrule }?.0 ?? "none"
        notificationOffsets = task.notificationOffsets
        place = task.place
        category = task.category
        profile = task.profile
        participantNames = task.participantNames
        isImportant = task.isImportant
        amountText = task.amount.map { "\($0)" } ?? ""
        paymentMethod = task.paymentMethod ?? ""
        notes = task.notes
        colorHex = task.colorHex
    }

    /// 金額入力の正規化＋パース（AddTaskSheet から踏襲）。全角数字→半角、カンマ・空白除去。
    /// マイナスや 0 以下は集計対象外なのでパース失敗扱い。
    var parsedAmount: Decimal? {
        let normalized = amountText
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
}

/// .sheet(item:) で使うため Identifiable 化（モデル層の WHCategory 自体は変更しない）。
extension WHCategory: Identifiable {
    var id: String { rawValue }
}

@MainActor
struct EventComposerView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    private var c: S8Palette { S8Palette.of(scheme) }
    @Query private var aliases: [PhraseAlias]
    @Query private var categories: [Category]
    @Query private var placeTags: [PlaceTag]

    private let existingTask: TaskItem?
    @State private var draft: ComposerDraft
    @State private var focusedCategory: WHCategory?
    /// P18 M13: prefillPlace（場所名の文字列ヒント）は init 時点では modelContext が使えないため、
    /// PlaceTag への解決を body 表示後の .task に遅延する。
    @State private var pendingPlaceHint: String?
    /// P18 H2: 金額が上限（1兆円）を超えた保存操作を弾いた時に表示するアラート。
    @State private var showAmountTooLargeAlert = false
    /// 自然文パース入力（Phase 16 の QuickAddParserView をカレンダー作成側にも接続）。
    @State private var nlInput: String = ""
    @State private var nlDebounceTask: Task<Void, Never>? = nil
    @State private var recognizedChips: [(WHCategory, String)] = []
    @FocusState private var nlFieldFocused: Bool

    /// 新規作成。空きカードタップ経由のプリフィル対応（initialDuration ありなら when を時刻指定済みで開く）。
    /// P18 M13: QuickAddParserView「詳細を追加」から ParseResult の全ヒントを渡すための一括プリフィル拡張
    /// （既存呼び出し元はデフォルト値でそのまま動く）。
    init(
        initialStart: Date? = nil,
        initialDuration: TimeInterval? = nil,
        prefillTitle: String? = nil,
        prefillPlace: String? = nil,
        prefillCategory: Category? = nil,
        prefillProfile: Profile? = nil,
        prefillParticipants: [String] = [],
        prefillNotes: String = ""
    ) {
        existingTask = nil
        let newDraft = ComposerDraft(defaultDate: initialStart ?? .now, prefillDuration: initialDuration)
        if let prefillTitle { newDraft.title = prefillTitle }
        newDraft.category = prefillCategory
        newDraft.profile = prefillProfile
        newDraft.participantNames = prefillParticipants
        newDraft.notes = prefillNotes
        _draft = State(initialValue: newDraft)
        _pendingPlaceHint = State(initialValue: prefillPlace)
    }

    /// 既存タスクの編集。TaskDetailView のペンアイコンから接続（P18）。
    /// initialFocus 指定時はタイルグリッドを経由せず、そのトピックのフォーカスシートを起動直後に開く
    /// （focusedCategory の初期値を非 nil にするだけで .sheet(item:) が appear 時に発火する）。
    init(task: TaskItem, initialFocus: WHCategory? = nil) {
        existingTask = task
        _draft = State(initialValue: ComposerDraft(task: task))
        _focusedCategory = State(initialValue: initialFocus)
    }

    /// what 以外の6分類。タイルグリッド・フォーカス内ジャンプバー共通の並び順。
    static let tileCategories: [WHCategory] = WHCategory.allCases.filter { $0 != .what }

    /// RRULE プリセット。TaskItem.occurs() が解釈できる形のみ。
    /// 授業/バイト等の定期イベント作成に対応（毎週/毎月/毎年）。
    static let repeatOptions: [(String, String, String?)] = [
        ("none", "なし", nil),
        ("daily", "毎日", "FREQ=DAILY"),
        ("weekly", "毎週（同曜日）", "FREQ=WEEKLY"),
        ("weekday", "平日", "FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR"),
        ("mwf", "毎週月水金", "FREQ=WEEKLY;BYDAY=MO,WE,FR"),
        ("weekend", "毎週末", "FREQ=WEEKLY;BYDAY=SA,SU"),
        ("monthly", "毎月（同日）", "FREQ=MONTHLY"),
        ("yearly", "毎年", "FREQ=YEARLY")
    ]

    private let gridColumns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        VStack(spacing: 0) {
            S8TopBar(existingTask == nil ? "タスク追加" : "タスク編集", sub: existingTask == nil ? "new · what/when/where" : "edit · what/when/where") {
                HStack(spacing: 6) {
                    S8IconButton(icon: "x", action: { dismiss() })
                        .accessibilityLabel("キャンセル")
                    S8IconButton(icon: "check", accent: !isSaveDisabled, action: save)
                        .disabled(isSaveDisabled)
                        .accessibilityLabel(existingTask == nil ? "追加" : "保存")
                }
            }

            // 自然文パース入力（新規作成のみ表示。編集時は不要）
            if existingTask == nil {
                VStack(alignment: .leading, spacing: 4) {
                    TextField("自然文で入力（例: 明日 14:00 大学でレポート）", text: $nlInput, axis: .vertical)
                        .textFieldStyle(.plain)
                        .lineLimit(1...2)
                        .focused($nlFieldFocused)
                        .padding(10)
                        .background(c.surface)
                        .overlay(
                            RoundedRectangle(cornerRadius: S8Radius.md)
                                .stroke(nlFieldFocused ? c.accent : c.lineStrong, lineWidth: nlFieldFocused ? 1.5 : 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: S8Radius.md))
                        .onChange(of: nlInput) { _, newValue in
                            scheduleParse(newValue)
                        }
                    if !recognizedChips.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(Array(recognizedChips.enumerated()), id: \.offset) { _, chip in
                                    Text("\(chip.0.label): \(chip.1)")
                                        .font(S8Font.mono(11)).tracking(1.5)
                                        .foregroundStyle(c.fg2)
                                        .padding(.horizontal, 11)
                                        .padding(.vertical, 6)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: S8Radius.md)
                                                .stroke(c.lineStrong, lineWidth: 1)
                                        )
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 4)
                .padding(.bottom, 8)
            }

            S8Field(placeholder: "タスク名", text: $draft.title)
                .padding(.horizontal, 24).padding(.bottom, 8)

            S8Rule()

            ScrollView {
                LazyVGrid(columns: gridColumns, spacing: 12) {
                    ForEach(Self.tileCategories) { category in
                        tileButton(for: category)
                    }
                }
                .padding(24)
            }
        }
        .background(c.paper.ignoresSafeArea())
        .sheet(item: $focusedCategory) { category in
            ComposerFocusView(category: category, draft: draft) { focusedCategory = $0 }
        }
        .task {
            resolvePlaceHintIfNeeded()
        }
        .alert("金額が大きすぎます", isPresented: $showAmountTooLargeAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("金額は1兆円以下で入力してください")
        }
    }

    /// P18 M13: prefillPlace（文字列）を PlaceTag に解決する。modelContext は init 時点では
    /// 使えないため body 表示後に一度だけ実行する。
    private func resolvePlaceHintIfNeeded() {
        guard let hint = pendingPlaceHint, draft.place == nil else { return }
        let fetch = FetchDescriptor<PlaceTag>(predicate: #Predicate<PlaceTag> { $0.name == hint })
        draft.place = try? modelContext.fetch(fetch).first
        pendingPlaceHint = nil
    }

    /// 自然文入力の 300ms デバウンス。空文字ならクリア。
    private func scheduleParse(_ text: String) {
        nlDebounceTask?.cancel()
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            recognizedChips = []
            return
        }
        nlDebounceTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            applyParse(trimmed)
        }
    }

    /// PhraseParser 結果を draft に反映。既存の手動編集を尊重しつつヒントを埋める。
    private func applyParse(_ text: String) {
        let result = PhraseParser.parse(text, aliases: aliases)
        // タイトル: 残り文字列を反映（自然文入力を使う=手動入力より優先）
        draft.title = result.titleRemainder
        // when
        if let start = result.startDate {
            draft.isTimeSpecified = true
            draft.startDate = start
        }
        if let duration = result.duration {
            draft.duration = duration
            draft.isTimeSpecified = true
        }
        // where: PlaceTag 名でマッチ、無ければ pendingPlaceHint に置く（後で解決）
        if let placeHint = result.placeHint {
            if let match = placeTags.first(where: { $0.name == placeHint }) {
                draft.place = match
            } else {
                pendingPlaceHint = placeHint
            }
        }
        // which
        if let categoryHint = result.categoryHint,
           let match = categories.first(where: { $0.name == categoryHint }) {
            draft.category = match
        }
        // who / other は既存 EventComposer プリフィル経路と同じ
        if let who = result.whoHint, !draft.participantNames.contains(who) {
            draft.participantNames.append(who)
        }
        if let other = result.otherHint {
            if draft.notes.isEmpty { draft.notes = other }
            else if !draft.notes.contains(other) { draft.notes += "\n" + other }
        }
        recognizedChips = result.recognizedChips
    }

    private var isSaveDisabled: Bool {
        draft.title.trimmingCharacters(in: .whitespaces).isEmpty
            || (!draft.amountText.isEmpty && draft.parsedAmount == nil)
    }

    private func tileButton(for category: WHCategory) -> some View {
        Button(action: { focusedCategory = category }) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: category.iconName)
                        .foregroundStyle(isSet(category) ? c.accent : c.fg2)
                    Text(category.label)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(c.fg1)
                    Spacer()
                }
                Text(preview(for: category))
                    .font(.caption)
                    .foregroundStyle(isSet(category) ? c.fg1 : c.fg3)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 72, alignment: .topLeading)
            .background(c.surface)
            .overlay(RoundedRectangle(cornerRadius: S8Radius.lg).stroke(c.line, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: S8Radius.lg))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(category.label): \(preview(for: category))")
        // P18 M10: how タイルはフォーカスを開かずに重要度だけ切替できるインラインの星アイコンを重ねる。
        .overlay(alignment: .bottomTrailing) {
            if category == .how {
                Image(systemName: draft.isImportant ? "star.fill" : "star")
                    .font(.caption)
                    .foregroundStyle(draft.isImportant ? c.accent : c.fg3)
                    .padding(8)
                    .onTapGesture { draft.isImportant.toggle() }
                    .accessibilityLabel(draft.isImportant ? "重要を解除" : "重要に設定")
            }
        }
    }

    private func isSet(_ category: WHCategory) -> Bool {
        preview(for: category) != "未設定"
    }

    private func preview(for category: WHCategory) -> String {
        switch category {
        case .what:
            return draft.title
        case .when:
            guard draft.isTimeSpecified else { return "未設定" }
            let start = Self.previewFormatter.string(from: draft.startDate)
            let end = Self.previewEndFormatter.string(from: draft.startDate.addingTimeInterval(draft.duration))
            return "\(start)–\(end)"
        case .where_:
            return draft.place?.name ?? "未設定"
        case .which:
            let parts = [draft.category?.name, draft.profile?.name].compactMap { $0 }
            return parts.isEmpty ? "未設定" : parts.joined(separator: "・")
        case .who:
            return draft.participantNames.isEmpty ? "未設定" : draft.participantNames.joined(separator: ", ")
        case .how:
            var parts: [String] = []
            if draft.isImportant { parts.append("★重要") }
            if let amount = draft.parsedAmount { parts.append(currencyText(amount)) }
            return parts.isEmpty ? "未設定" : parts.joined(separator: " ")
        case .other:
            return draft.notes.isEmpty ? "未設定" : draft.notes
        }
    }

    private static let previewFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "M/d HH:mm"
        return f
    }()

    private static let previewEndFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    /// 保存：新規時は TaskItem を insert、編集時は既存を in-place 更新。
    /// ワークフロー系フィールド（status/phase/sortIndex/snoozeUntil 等）はここでは触らない。
    private func save() {
        let trimmedTitle = draft.title.trimmingCharacters(in: .whitespaces)
        guard !trimmedTitle.isEmpty else { return }
        guard draft.amountText.isEmpty || draft.parsedAmount != nil else { return }
        // P18 H2: 金額の上限バリデーション（1兆円超は拒否）。
        if let amount = draft.parsedAmount, amount > 1_000_000_000_000 {
            showAmountTooLargeAlert = true
            return
        }

        let rruleStr = Self.repeatOptions.first { $0.0 == draft.repeatPattern }?.2
        let amount = draft.parsedAmount
        let trimmedPayment = draft.paymentMethod.trimmingCharacters(in: .whitespaces)
        let paymentMethod = amount != nil && !trimmedPayment.isEmpty ? trimmedPayment : nil

        // ponytail: WH カテゴリに対応しない phase は新規時のみ .today 固定（TodoListView.quickAdd と同じ既定値）。
        let task = existingTask ?? TaskItem(title: trimmedTitle, phase: .today)

        // P18: reschedule/recompute を「実際に変わった時だけ」呼ぶための保存前スナップショット。
        // 新規タスクは全フィールドがデフォルト値（nil/0/[]）なので、そのまま「変更あり」判定に使える。
        let oldStart = task.startDate
        let oldDuration = task.duration
        let oldOffsets = task.notificationOffsets
        let oldAmount = task.amount

        task.title = trimmedTitle
        task.category = draft.category
        task.startDate = draft.isTimeSpecified ? draft.startDate : nil
        task.duration = draft.isTimeSpecified ? draft.duration : 0
        task.place = draft.place
        task.notes = draft.notes
        task.isImportant = draft.isImportant
        task.colorHex = draft.colorHex
        task.notificationOffsets = draft.notificationOffsets.sorted()
        task.timeZoneIdentifier = draft.isTimeSpecified ? TimeZone.current.identifier : nil
        task.amount = amount
        task.paymentMethod = paymentMethod
        task.isTimePinned = draft.isTimeSpecified && draft.isTimePinned
        task.rrule = rruleStr
        task.profile = draft.profile
        task.participantNames = draft.participantNames

        if existingTask == nil {
            modelContext.insert(task)
        }
        do {
            try modelContext.save()
        } catch {
            // ponytail: save 失敗を可視化。sheet を閉じずユーザーが失敗に気付ける
            print("[EventComposer] save failed: \(error)")
            assertionFailure("EventComposer save failed: \(error)")
            return
        }

        // P18: when（startDate/duration/通知設定）が変わった時だけ再スケジュール。
        // 新規タスクは old が空なので必ず走り、既存の挙動（常時 reschedule）を保つ。
        if task.startDate != oldStart || task.duration != oldDuration || task.notificationOffsets != oldOffsets {
            NotificationService.reschedule(for: task)
        }
        // P18: P8 debate-review 繰り越しの解消（金額編集時 recompute）。amount の
        // nil→値／値→nil／値→別値のいずれの変化でも対象にする（旧実装は amount != nil の時しか呼ばず、
        // 編集で金額を消したケースで月次キャッシュが更新されない問題があった）。
        if task.amount != oldAmount {
            MoneyStats.recompute(for: task, context: modelContext)
        }

        dismiss()
    }
}

// MARK: - フォーカス編集シート（s8 化）

/// トピック1つの内容を全画面表示するフォーカス編集画面。上部ジャンプバーで他タイルへ横移動。
/// SettingsRootView 流儀（S8SectionLabel + S8SetRow + s8 プリミティブ）で iOS 標準 Form/Toggle/Slider/Picker/DatePicker を排除。
private struct ComposerFocusView: View {
    let category: WHCategory
    @Bindable var draft: ComposerDraft
    var onNavigate: (WHCategory) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    private var c: S8Palette { S8Palette.of(scheme) }
    @Query(sort: \Profile.name) private var profiles: [Profile]

    @State private var newParticipant: String = ""
    @State private var customNotificationMinutes: Int = 5
    @State private var showCategoryPicker: Bool = false

    private static let colorPresets: [String] = ["4F8DFD", "34C759", "FF9500", "FF2D55", "AF52DE", "8E8E93"]
    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.timeStyle = .short
        return f
    }()

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Text(category.label).font(S8Font.jp(16, .bold)).foregroundColor(c.fg1)
                Spacer()
            }
            .padding(.horizontal, 24).padding(.top, 14)
            .overlay(alignment: .trailing) {
                Button("閉じる") { dismiss() }
                    .font(S8Font.jp(14)).foregroundColor(c.accentInk)
                    .padding(.trailing, 20).padding(.top, 14)
            }
            jumpBar
                .padding(.top, 8)
            S8Rule()
            contentContainer
        }
        .background(c.paper.ignoresSafeArea())
        .sheet(isPresented: $showCategoryPicker) {
            NavigationStack { CategoryPickerView(selection: $draft.category) }
        }
    }

    /// 他タイルへの直接ジャンプアイコン列。
    private var jumpBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 20) {
                ForEach(EventComposerView.tileCategories) { cat in
                    Button(action: { onNavigate(cat) }) {
                        VStack(spacing: 3) {
                            S8Icon(name: whCategoryToS8Icon(cat), size: 16,
                                   color: cat == category ? c.accentInk : c.fg3)
                            Text(cat.label)
                                .font(S8Font.jp(10, cat == category ? .bold : .regular))
                                .foregroundColor(cat == category ? c.accentInk : c.fg3)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(cat.label)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 4)
        }
    }

    private func whCategoryToS8Icon(_ cat: WHCategory) -> String {
        switch cat {
        case .what:   return "text-cursor"
        case .when:   return "clock"
        case .where_: return "map-pin"
        case .which:  return "tag"
        case .who:    return "users"
        case .how:    return "gauge"
        case .other:  return "file"
        }
    }

    @ViewBuilder
    private var contentContainer: some View {
        switch category {
        case .what:
            EmptyView() // 到達しない
        case .when:
            ScrollView { whenContent; Color.clear.frame(height: 24) }
        case .where_:
            // LocationPickerView は自前ナビ・入力体系。NavigationStack で包んで直接。
            NavigationStack { LocationPickerView(place: $draft.place) }
        case .which:
            ScrollView { whichContent; Color.clear.frame(height: 24) }
        case .who:
            ScrollView { whoContent; Color.clear.frame(height: 24) }
        case .how:
            ScrollView { howContent; Color.clear.frame(height: 24) }
        case .other:
            ScrollView { otherContent; Color.clear.frame(height: 24) }
        }
    }

    // MARK: - when

    @ViewBuilder
    private var whenContent: some View {
        let notifPresets: [(Int, String)] = [(5, "5分前"), (15, "15分前"), (60, "1時間前"), (1440, "前日")]
        VStack(spacing: 0) {
            S8SectionLabel(text: "時刻")
            S8SetRow(icon: "clock", label: "時刻を指定") {
                S8Toggle(on: draft.isTimeSpecified) { draft.isTimeSpecified.toggle() }
            }
            if draft.isTimeSpecified {
                S8Rule()
                S8SetRow(icon: "calendar", label: "開始") {
                    S8DatePicker(date: $draft.startDate, showTime: true, minuteStep: 5)
                }
                S8Rule()
                S8SetRow(icon: "hourglass", label: "所要") {
                    S8Stepper(
                        value: Binding(
                            get: { Int(draft.duration / 60) },
                            set: { draft.duration = TimeInterval($0) * 60 }
                        ),
                        range: 0...(24 * 60),
                        step: 5,
                        unit: "分",
                        width: 132
                    )
                }
                S8Rule()
                HStack(spacing: 14) {
                    Spacer(minLength: 62)
                    Text("終了: \(Self.timeFormatter.string(from: draft.startDate.addingTimeInterval(draft.duration)))")
                        .font(S8Font.mono(11)).tracking(1.0)
                        .foregroundColor(c.fg3)
                    Spacer()
                }
                .padding(.horizontal, 24).padding(.vertical, 6)
                S8Rule()
                S8SetRow(icon: "pin", label: "時刻厳守") {
                    S8Toggle(on: draft.isTimePinned) { draft.isTimePinned.toggle() }
                }

                S8SectionLabel(text: "繰り返し")
                S8SetRow(icon: "repeat", label: "パターン") {
                    S8Picker(
                        selection: $draft.repeatPattern,
                        options: EventComposerView.repeatOptions.map { ($0.0, $0.1) },
                        style: .sheet
                    )
                }

                S8SectionLabel(text: "通知")
                ForEach(notifPresets, id: \.0) { minutes, label in
                    S8SetRow(icon: "bell", label: label) {
                        S8Toggle(on: draft.notificationOffsets.contains(minutes)) {
                            if draft.notificationOffsets.contains(minutes) {
                                draft.notificationOffsets.removeAll { $0 == minutes }
                            } else {
                                draft.notificationOffsets.append(minutes)
                                draft.notificationOffsets.sort()
                            }
                        }
                    }
                    S8Rule()
                }
                S8SetRow(icon: "plus", label: "カスタム") {
                    HStack(spacing: 8) {
                        S8Stepper(value: $customNotificationMinutes, range: 1...10080, step: 1, unit: "分前", width: 118)
                        S8IconButton(icon: "plus", accent: true) {
                            if !draft.notificationOffsets.contains(customNotificationMinutes) {
                                draft.notificationOffsets.append(customNotificationMinutes)
                                draft.notificationOffsets.sort()
                            }
                        }
                        .accessibilityLabel("カスタム通知を追加")
                    }
                }
                if !draft.notificationOffsets.isEmpty {
                    S8SectionLabel(text: "有効な通知")
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(draft.notificationOffsets, id: \.self) { m in
                                S8Chip(offsetLabel(m), icon: "bell") {
                                    draft.notificationOffsets.removeAll { $0 == m }
                                }
                            }
                        }
                        .padding(.horizontal, 24)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    private func offsetLabel(_ minutes: Int) -> String {
        if minutes >= 1440 { return "\(minutes/1440)日前" }
        if minutes >= 60 { return "\(minutes/60)時間前" }
        return "\(minutes)分前"
    }

    // MARK: - which

    @ViewBuilder
    private var whichContent: some View {
        VStack(spacing: 0) {
            S8SectionLabel(text: "カテゴリ")
            S8SetRow(icon: "tag", label: "カテゴリ", trailing: {
                HStack(spacing: 8) {
                    if let cat = draft.category {
                        Circle().fill(Color(hex: cat.colorHex)).frame(width: 12, height: 12)
                        Text(cat.name).font(S8Font.jp(14)).foregroundColor(c.fg1)
                    } else {
                        Text("未選択").font(S8Font.jp(14)).foregroundColor(c.fg3)
                    }
                    S8Icon(name: "chevron-right", size: 14, color: c.fg3)
                }
            }, onTap: { showCategoryPicker = true })
            if draft.category != nil {
                S8Rule()
                S8SetRow(icon: "x", label: "カテゴリを外す", trailing: { EmptyView() }, onTap: { draft.category = nil })
            }

            S8SectionLabel(text: "プロフィール")
            if profiles.isEmpty {
                HStack(spacing: 14) {
                    S8Icon(name: "info", size: 16, color: c.fg3)
                    Text("プロフィールが未登録です").font(S8Font.jp(13)).foregroundColor(c.fg3)
                    Spacer()
                }
                .padding(.horizontal, 24).padding(.vertical, 15)
            } else {
                ForEach(Array(profiles.enumerated()), id: \.element.id) { i, profile in
                    S8SetRow(icon: profile.iconName, label: profile.name, trailing: {
                        if draft.profile?.id == profile.id {
                            S8Icon(name: "check", size: 16, color: c.accent)
                        }
                    }, onTap: {
                        draft.profile = (draft.profile?.id == profile.id) ? nil : profile
                    })
                    if i < profiles.count - 1 { S8Rule() }
                }
            }
        }
    }

    // MARK: - who

    @ViewBuilder
    private var whoContent: some View {
        VStack(spacing: 0) {
            S8SectionLabel(text: "参加者を追加")
            HStack(spacing: 8) {
                S8Field(placeholder: "名前", text: $newParticipant)
                    .onSubmit(addParticipant)
                S8IconButton(icon: "plus", accent: !newParticipant.trimmingCharacters(in: .whitespaces).isEmpty) {
                    addParticipant()
                }
                .disabled(newParticipant.trimmingCharacters(in: .whitespaces).isEmpty)
                .accessibilityLabel("参加者を追加")
            }
            .padding(.horizontal, 24).padding(.vertical, 10)

            if !draft.participantNames.isEmpty {
                S8SectionLabel(text: "参加者")
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(draft.participantNames, id: \.self) { name in
                            HStack(spacing: 6) {
                                Text(name).font(S8Font.jp(13)).foregroundColor(c.fg1)
                                Button(action: { removeParticipant(name) }) {
                                    S8Icon(name: "x", size: 12, color: c.fg3)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("\(name) を削除")
                            }
                            .padding(.horizontal, 11)
                            .padding(.vertical, 7)
                            .overlay(RoundedRectangle(cornerRadius: S8Radius.md).stroke(c.lineStrong, lineWidth: 1))
                            .clipShape(RoundedRectangle(cornerRadius: S8Radius.md))
                        }
                    }
                    .padding(.horizontal, 24)
                }
                .padding(.vertical, 6)
            }
        }
    }

    private func addParticipant() {
        // P18 H2: 改行除去→trim→50文字上限、既存重複はスキップ。
        let noNewlines = newParticipant.replacingOccurrences(of: "\n", with: "").replacingOccurrences(of: "\r", with: "")
        let trimmed = String(noNewlines.trimmingCharacters(in: .whitespaces).prefix(50))
        guard !trimmed.isEmpty, !draft.participantNames.contains(trimmed) else { return }
        draft.participantNames.append(trimmed)
        newParticipant = ""
    }

    private func removeParticipant(_ name: String) {
        draft.participantNames.removeAll { $0 == name }
    }

    // MARK: - how

    @ViewBuilder
    private var howContent: some View {
        VStack(spacing: 0) {
            S8SectionLabel(text: "金額")
            VStack(alignment: .leading, spacing: 10) {
                S8Field(placeholder: "金額（例: 1490）", text: $draft.amountText)
                if !draft.amountText.isEmpty && draft.parsedAmount == nil {
                    Text("金額は正の数値で入力してください")
                        .font(S8Font.jp(11))
                        .foregroundColor(c.danger)
                }
                S8Field(placeholder: "支払方法（例: クレジットカード）", text: $draft.paymentMethod)
            }
            .padding(.horizontal, 24).padding(.vertical, 12)

            S8SectionLabel(text: "重要度")
            S8SetRow(icon: draft.isImportant ? "star" : "star", label: "重要") {
                S8Toggle(on: draft.isImportant) { draft.isImportant.toggle() }
            }
        }
    }

    // MARK: - other

    @ViewBuilder
    private var otherContent: some View {
        VStack(spacing: 0) {
            S8SectionLabel(text: "メモ")
            TextEditor(text: $draft.notes)
                .font(S8Font.jp(14))
                .foregroundColor(c.fg1)
                .scrollContentBackground(.hidden)
                .background(c.surface)
                .overlay(RoundedRectangle(cornerRadius: S8Radius.md).stroke(c.lineStrong, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: S8Radius.md))
                .frame(minHeight: 160)
                .padding(.horizontal, 24).padding(.vertical, 10)

            S8SectionLabel(text: "色")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(Self.colorPresets, id: \.self) { hex in
                        Button(action: { draft.colorHex = hex }) {
                            Circle()
                                .fill(Color(hex: hex))
                                .frame(width: 34, height: 34)
                                .overlay(
                                    Circle().stroke(draft.colorHex == hex ? c.fg1 : Color.clear, lineWidth: 2)
                                )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("色を選択")
                    }
                    Button(action: { draft.colorHex = nil }) {
                        ZStack {
                            Circle().fill(c.surface2)
                            S8Icon(name: "x", size: 14, color: c.fg2)
                        }
                        .frame(width: 34, height: 34)
                        .overlay(
                            Circle().stroke(draft.colorHex == nil ? c.fg1 : Color.clear, lineWidth: 2)
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("色をクリア")
                }
                .padding(.horizontal, 24).padding(.vertical, 8)
            }
        }
    }
}

#Preview {
    EventComposerView()
        .modelContainer(PreviewData.container)
}
