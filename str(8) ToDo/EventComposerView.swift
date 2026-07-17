//
//  EventComposerView.swift
//  str8ToDo
//
//  イベント作成シート。UI改善（str8 UI改善.dc.html A1/A2）:
//    - 大きな 1 行入力を主役化、下に認識チップ（確定 = 緑チェック / 辞書候補 = 破線）
//    - 「確認」インライン展開行（いつ/どこ/どれ/誰と/どのくらい/メモ）
//    - タイトルは必須バッジ付き行、タップで編集
//    - タイル + フォーカスシートを廃止（ComposerFocusView は削除、ここに統合）
//    - タイトルさえあれば常時「追加する」可能
//

import Foundation
import SwiftUI
import SwiftData
import PhotosUI

/// インライン展開行と NL 入力の両方から参照する編集中の草稿。
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
    /// Phase 17: 添付画像。App Group `attachments/` からの相対ファイル名。
    var attachmentPaths: [String] = []

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
        attachmentPaths = task.attachmentPaths
    }

    /// 金額入力の正規化＋パース。全角数字→半角、カンマ・空白除去。マイナスや 0 以下は集計対象外。
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

/// .sheet(item:) で使うため Identifiable 化。
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
    @Query(sort: \Profile.name) private var profiles: [Profile]

    private let existingTask: TaskItem?
    @State private var draft: ComposerDraft
    /// 現在展開中の行（1 個のみ、nil = すべて閉じる）。
    @State private var expandedRow: WHCategory?
    /// タイトル行を展開中かどうか（title は WHCategory.what に相当、別 state で扱う）。
    @State private var editingTitle: Bool = false
    /// P18 M13: prefillPlace（場所名の文字列ヒント）は init 時点では modelContext が使えないため遅延解決。
    @State private var pendingPlaceHint: String?
    @State private var showAmountTooLargeAlert = false

    // Natural language input
    @State private var nlInput: String = ""
    @State private var nlDebounceTask: Task<Void, Never>? = nil
    @State private var recognizedChips: [(WHCategory, String)] = []
    @State private var nlUnrecognizedWords: [String] = []
    @State private var aliasDraftWord: AliasCandidateWord? = nil
    @FocusState private var nlFieldFocused: Bool

    // Editor states (旧 ComposerFocusView から移設)
    @State private var newParticipant: String = ""
    @State private var customNotificationMinutes: Int = 5
    @State private var showCategoryPicker: Bool = false
    @State private var pickerItems: [PhotosPickerItem] = []

    /// サジェスト機能の ON/OFF。QuickAddParserView と共有。
    @AppStorage(AppSettingsKey.enableDictionarySuggestions)
    private var enableDictionarySuggestions = AppSettingsKey.enableDictionarySuggestionsDefault

    private static let colorPresets: [String] = ["4F8DFD", "34C759", "FF9500", "FF2D55", "AF52DE", "8E8E93"]

    /// 新規作成。空きカードタップ経由のプリフィル対応（initialDuration ありなら when を時刻指定済みで開く）。
    init(
        initialStart: Date? = nil,
        initialDuration: TimeInterval? = nil,
        prefillTitle: String? = nil,
        prefillPlace: String? = nil,
        prefillCategory: Category? = nil,
        prefillProfile: Profile? = nil,
        prefillParticipants: [String] = [],
        prefillNotes: String = "",
        prefillRRule: String? = nil,
        prefillNotificationOffsets: [Int] = [],
        prefillIsImportant: Bool = false
    ) {
        existingTask = nil
        let newDraft = ComposerDraft(defaultDate: initialStart ?? .now, prefillDuration: initialDuration)
        if let prefillTitle { newDraft.title = prefillTitle }
        newDraft.category = prefillCategory
        newDraft.profile = prefillProfile
        newDraft.participantNames = prefillParticipants
        newDraft.notes = prefillNotes
        newDraft.repeatPattern = EventComposerView.repeatOptions.first { $0.2 == prefillRRule }?.0 ?? "none"
        newDraft.notificationOffsets = prefillNotificationOffsets
        newDraft.isImportant = prefillIsImportant
        _draft = State(initialValue: newDraft)
        _pendingPlaceHint = State(initialValue: prefillPlace)
    }

    /// 既存タスクの編集。initialFocus 指定時はその行を展開状態で開く。
    init(task: TaskItem, initialFocus: WHCategory? = nil) {
        existingTask = task
        _draft = State(initialValue: ComposerDraft(task: task))
        _expandedRow = State(initialValue: initialFocus)
    }

    /// RRULE プリセット。TaskItem.occurs() が解釈できる形のみ。
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

    /// what 以外の 6 分類。インライン行の並び順（when/where/which/who/how/other）。
    static let rowCategories: [WHCategory] = [.when, .where_, .which, .who, .how, .other]

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                VStack(spacing: 0) {
                    if existingTask == nil {
                        nlInputSection
                            .padding(.horizontal, 24).padding(.top, 4)
                    }

                    confirmationDivider
                        .padding(.top, existingTask == nil ? 18 : 8)

                    titleRow
                    ForEach(Self.rowCategories, id: \.self) { cat in
                        inlineRow(cat)
                    }
                    Color.clear.frame(height: 14)
                }
            }

            bottomBar
        }
        .background(c.paper.ignoresSafeArea())
        .sheet(item: $aliasDraftWord) { d in
            NewAliasSheet(word: d.word)
        }
        .sheet(isPresented: $showCategoryPicker) {
            NavigationStack { CategoryPickerView(selection: $draft.category) }
        }
        .task { resolvePlaceHintIfNeeded() }
        .alert("金額が大きすぎます", isPresented: $showAmountTooLargeAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("金額は1兆円以下で入力してください")
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 3) {
                Text(existingTask == nil ? "追加" : "編集")
                    .font(S8Font.jp(22, .bold))
                    .foregroundColor(c.fg1)
                Text(existingTask == nil ? "type one line" : "edit in place")
                    .font(S8Font.mono(10)).tracking(1.6)
                    .foregroundColor(c.fg3)
            }
            Spacer()
            S8IconButton(icon: "x", action: { dismiss() })
                .accessibilityLabel("閉じる")
        }
        .padding(.horizontal, 24).padding(.top, 14).padding(.bottom, 10)
    }

    // MARK: - Natural language input (A1 の主役)

    private var nlInputSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("一行でいい。あとから直せる。")
                .font(S8Font.jp(12)).foregroundColor(c.fg3)

            TextField("明日 14:00 大学図書館でレポート", text: $nlInput, axis: .vertical)
                .font(S8Font.jp(17, .medium))
                .foregroundColor(c.fg1)
                .lineLimit(1...4)
                .focused($nlFieldFocused)
                .padding(.horizontal, 15).padding(.vertical, 16)
                .background(c.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: S8Radius.md)
                        .stroke(c.lineStrong, lineWidth: 1)
                )
                .overlay(alignment: .bottom) {
                    // A1: 底辺だけ accent の 2.5px。focus 中は色を強調。
                    Rectangle().fill(c.accent).frame(height: 2.5)
                }
                .clipShape(RoundedRectangle(cornerRadius: S8Radius.md))
                .onChange(of: nlInput) { _, newValue in scheduleParse(newValue) }

            if !recognizedChips.isEmpty || (enableDictionarySuggestions && !nlUnrecognizedWords.isEmpty) {
                recognitionChipsRow
            }
        }
    }

    /// 確定チップ（緑チェック + accent-wash 塗り）＋ サジェストチップ（破線）。
    private var recognitionChipsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(Array(recognizedChips.enumerated()), id: \.offset) { _, chip in
                    HStack(spacing: 5) {
                        S8Icon(name: "check", size: 12, color: c.accentInk)
                        Text("\(chipLabel(chip.0)) · \(chip.1)")
                            .font(S8Font.jp(11.5))
                            .foregroundColor(c.accentInk)
                    }
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(c.accentWash)
                    .overlay(Capsule().stroke(c.accent, lineWidth: 1))
                    .clipShape(Capsule())
                }
                if enableDictionarySuggestions {
                    ForEach(nlUnrecognizedWords, id: \.self) { word in
                        Button(action: { aliasDraftWord = AliasCandidateWord(word: word) }) {
                            Text("「\(word)」を登録?")
                                .font(S8Font.jp(11.5))
                                .foregroundColor(c.fg3)
                                .padding(.horizontal, 10).padding(.vertical, 5)
                                .overlay(Capsule().stroke(c.lineStrong, style: StrokeStyle(lineWidth: 1, dash: [3])))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func howSummaryText() -> String {
        var parts: [String] = []
        if draft.isImportant { parts.append("★重要") }
        if draft.duration > 0 { parts.append("\(Int(draft.duration/60))分") }
        if let amount = draft.parsedAmount { parts.append(currencyText(amount)) }
        return parts.joined(separator: " · ")
    }

    private func chipLabel(_ cat: WHCategory) -> String {
        switch cat {
        case .what: return "何を"
        case .when: return "いつ"
        case .where_: return "どこ"
        case .which: return "どれ"
        case .who: return "誰と"
        case .how: return "どのくらい"
        case .other: return "その他"
        }
    }

    // MARK: - 「確認」divider

    private var confirmationDivider: some View {
        HStack(spacing: 10) {
            Text("確認").font(S8Font.mono(10)).tracking(1.6).foregroundColor(c.fg3)
            Text("すべて任意 · タップで直す").font(S8Font.jp(12)).foregroundColor(c.fg3)
            S8Rule()
        }
        .padding(.horizontal, 24).padding(.vertical, 8)
    }

    // MARK: - Title row (必須バッジ、accent-wash 塗り)

    private var titleRow: some View {
        VStack(spacing: 0) {
            Button(action: {
                withAnimation(.easeInOut(duration: 0.15)) {
                    editingTitle.toggle()
                    if editingTitle { expandedRow = nil }
                }
            }) {
                HStack(spacing: 13) {
                    HStack(spacing: 8) {
                        S8Icon(name: "type", size: 15, color: c.accent)
                        Text("タイトル").font(S8Font.jp(12.5, .medium)).foregroundColor(c.fg2)
                    }
                    .frame(width: 88, alignment: .leading)
                    Text(draft.title.isEmpty ? "未入力" : draft.title)
                        .font(S8Font.jp(14, draft.title.isEmpty ? .regular : .bold))
                        .foregroundColor(draft.title.isEmpty ? c.fg3 : c.fg1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("必須")
                        .font(S8Font.mono(8.5)).tracking(1.2)
                        .foregroundColor(c.accentInk)
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .overlay(RoundedRectangle(cornerRadius: 3).stroke(c.accent, lineWidth: 1))
                }
                .padding(.horizontal, 24).padding(.vertical, 15)
                .background(c.accentWash)
                .overlay(alignment: .top) { S8Rule() }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if editingTitle {
                titleEditor
                    .padding(.horizontal, 24).padding(.vertical, 12)
                    .background(c.accentWash.opacity(0.6))
                    .overlay(alignment: .top) { Rectangle().fill(c.accent).frame(height: 1) }
            }
        }
    }

    // MARK: - Inline expandable row

    private func inlineRow(_ cat: WHCategory) -> some View {
        VStack(spacing: 0) {
            Button(action: {
                withAnimation(.easeInOut(duration: 0.15)) {
                    editingTitle = false
                    expandedRow = (expandedRow == cat) ? nil : cat
                }
            }) {
                HStack(spacing: 13) {
                    HStack(spacing: 8) {
                        S8Icon(name: iconName(for: cat), size: 15,
                               color: expandedRow == cat ? c.accentInk : c.fg2)
                        Text(chipLabel(cat)).font(S8Font.jp(12.5, .medium))
                            .foregroundColor(expandedRow == cat ? c.accentInk : c.fg2)
                    }
                    .frame(width: 88, alignment: .leading)
                    summary(for: cat)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    S8Icon(name: expandedRow == cat ? "chevron-down" : "chevron-right",
                           size: 15, color: c.fg3)
                }
                .padding(.horizontal, 24).padding(.vertical, 15)
                .background(expandedRow == cat ? c.accentWash : c.paper)
                .overlay(alignment: .top) { S8Rule() }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expandedRow == cat {
                editor(for: cat)
                    .background(c.accentWash.opacity(0.35))
                    .overlay(alignment: .top) { Rectangle().fill(c.accent).frame(height: 1) }
                    .overlay(alignment: .bottom) { Rectangle().fill(c.accent).frame(height: 1) }
            }
        }
    }

    private func iconName(for cat: WHCategory) -> String {
        switch cat {
        case .what:   return "type"
        case .when:   return "clock"
        case .where_: return "map-pin"
        case .which:  return "tag"
        case .who:    return "users"
        case .how:    return "gauge"
        case .other:  return "file-text"
        }
    }

    // MARK: - Row summary（closed 表示）

    @ViewBuilder
    private func summary(for cat: WHCategory) -> some View {
        switch cat {
        case .what:
            Text(draft.title.isEmpty ? "未入力" : draft.title)
                .font(S8Font.jp(14, draft.title.isEmpty ? .regular : .bold))
                .foregroundColor(draft.title.isEmpty ? c.fg3 : c.fg1)
                .lineLimit(1)
        case .when:
            if draft.isTimeSpecified {
                let start = Self.previewFormatter.string(from: draft.startDate)
                let end = Self.previewEndFormatter.string(from: draft.startDate.addingTimeInterval(draft.duration))
                Text("\(start) – \(end)")
                    .font(S8Font.jp(14)).foregroundColor(c.fg1)
                    .lineLimit(1)
            } else {
                Text("任意").font(S8Font.jp(14)).foregroundColor(c.fg3)
            }
        case .where_:
            if let placeName = draft.place?.name ?? pendingPlaceHint {
                Text(placeName).font(S8Font.jp(14)).foregroundColor(c.fg1).lineLimit(1)
            } else {
                Text("任意").font(S8Font.jp(14)).foregroundColor(c.fg3)
            }
        case .which:
            let parts = [draft.category?.name, draft.profile?.name].compactMap { $0 }
            if parts.isEmpty {
                Text("任意").font(S8Font.jp(14)).foregroundColor(c.fg3)
            } else {
                HStack(spacing: 6) {
                    if let cat = draft.category {
                        Circle().fill(Color(hex: cat.colorHex)).frame(width: 8, height: 8)
                    }
                    Text(parts.joined(separator: "・")).font(S8Font.jp(14)).foregroundColor(c.fg1).lineLimit(1)
                }
            }
        case .who:
            if draft.participantNames.isEmpty {
                Text("任意").font(S8Font.jp(14)).foregroundColor(c.fg3)
            } else {
                Text(draft.participantNames.joined(separator: ", ")).font(S8Font.jp(14)).foregroundColor(c.fg1).lineLimit(1)
            }
        case .how:
            let howText = howSummaryText()
            if howText.isEmpty {
                Text("任意").font(S8Font.jp(14)).foregroundColor(c.fg3)
            } else {
                Text(howText).font(S8Font.jp(14)).foregroundColor(c.fg1).lineLimit(1)
            }
        case .other:
            if draft.notes.isEmpty && draft.attachmentPaths.isEmpty && draft.colorHex == nil {
                Text("任意").font(S8Font.jp(14)).foregroundColor(c.fg3)
            } else {
                let bits = [
                    draft.notes.isEmpty ? nil : "メモ",
                    draft.attachmentPaths.isEmpty ? nil : "画像 \(draft.attachmentPaths.count)",
                    draft.colorHex == nil ? nil : "色"
                ].compactMap { $0 }
                Text(bits.joined(separator: " · "))
                    .font(S8Font.jp(14)).foregroundColor(c.fg1).lineLimit(1)
            }
        }
    }

    // MARK: - Row editor（open 表示）

    @ViewBuilder
    private func editor(for cat: WHCategory) -> some View {
        switch cat {
        case .what: EmptyView()
        case .when: whenEditor
        case .where_: whereEditor
        case .which: whichEditor
        case .who: whoEditor
        case .how: howEditor
        case .other: otherEditor
        }
    }

    // MARK: - Title editor

    private var titleEditor: some View {
        HStack(spacing: 10) {
            S8Field(placeholder: "タスク名", text: $draft.title)
            S8IconButton(icon: "check", accent: true, action: {
                withAnimation(.easeInOut(duration: 0.15)) { editingTitle = false }
            })
            .accessibilityLabel("タイトル決定")
        }
    }

    // MARK: - When editor

    @ViewBuilder
    private var whenEditor: some View {
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
        .padding(.vertical, 4)
    }

    private func offsetLabel(_ minutes: Int) -> String {
        if minutes >= 1440 { return "\(minutes/1440)日前" }
        if minutes >= 60 { return "\(minutes/60)時間前" }
        return "\(minutes)分前"
    }

    // MARK: - Where editor

    private var whereEditor: some View {
        LocationPickerView(place: $draft.place)
            .frame(minHeight: 320)
    }

    // MARK: - Which editor

    @ViewBuilder
    private var whichEditor: some View {
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
        .padding(.vertical, 4)
    }

    // MARK: - Who editor

    @ViewBuilder
    private var whoEditor: some View {
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
        .padding(.vertical, 4)
    }

    private func addParticipant() {
        let noNewlines = newParticipant.replacingOccurrences(of: "\n", with: "").replacingOccurrences(of: "\r", with: "")
        let trimmed = String(noNewlines.trimmingCharacters(in: .whitespaces).prefix(50))
        guard !trimmed.isEmpty, !draft.participantNames.contains(trimmed) else { return }
        draft.participantNames.append(trimmed)
        newParticipant = ""
    }

    private func removeParticipant(_ name: String) {
        draft.participantNames.removeAll { $0 == name }
    }

    // MARK: - How editor

    @ViewBuilder
    private var howEditor: some View {
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
            S8SetRow(icon: "star", label: "重要") {
                S8Toggle(on: draft.isImportant) { draft.isImportant.toggle() }
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Other editor（メモ + 画像 + 色）

    @ViewBuilder
    private var otherEditor: some View {
        VStack(spacing: 0) {
            S8SectionLabel(text: "メモ")
            TextEditor(text: $draft.notes)
                .font(S8Font.jp(14))
                .foregroundColor(c.fg1)
                .scrollContentBackground(.hidden)
                .background(c.surface)
                .overlay(RoundedRectangle(cornerRadius: S8Radius.md).stroke(c.lineStrong, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: S8Radius.md))
                .frame(minHeight: 120)
                .padding(.horizontal, 24).padding(.vertical, 10)

            S8SectionLabel(text: "添付")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(draft.attachmentPaths, id: \.self) { path in
                        ZStack(alignment: .topTrailing) {
                            if let img = AttachmentStore.image(named: path) {
                                Image(uiImage: img)
                                    .resizable().scaledToFill()
                                    .frame(width: 84, height: 84)
                                    .clipShape(RoundedRectangle(cornerRadius: S8Radius.md))
                                    .overlay(RoundedRectangle(cornerRadius: S8Radius.md).stroke(c.lineStrong, lineWidth: 1))
                            } else {
                                RoundedRectangle(cornerRadius: S8Radius.md)
                                    .fill(c.surface2).frame(width: 84, height: 84)
                                    .overlay(S8Icon(name: "image", size: 22, color: c.fg3))
                            }
                            Button(action: { removeAttachment(path) }) {
                                ZStack {
                                    Circle().fill(c.paper).frame(width: 22, height: 22)
                                    S8Icon(name: "x", size: 12, color: c.fg2)
                                }
                            }
                            .buttonStyle(.plain)
                            .offset(x: 6, y: -6)
                            .accessibilityLabel("画像を外す")
                        }
                    }
                    PhotosPicker(selection: $pickerItems, matching: .images) {
                        RoundedRectangle(cornerRadius: S8Radius.md)
                            .stroke(c.lineStrong, style: StrokeStyle(lineWidth: 1, dash: [4]))
                            .frame(width: 84, height: 84)
                            .overlay(S8Icon(name: "plus", size: 22, color: c.fg2))
                    }
                    .accessibilityLabel("画像を追加")
                }
                .padding(.horizontal, 24).padding(.vertical, 10)
            }
            .onChange(of: pickerItems) { _, newItems in
                Task { await ingestPickerItems(newItems) }
            }

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
        .padding(.vertical, 4)
    }

    // MARK: - Bottom bar

    private var bottomBar: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(existingTask == nil ? "タイトルだけで追加できます" : "変更を保存します")
                    .font(S8Font.jp(13.5, .bold))
                    .foregroundColor(c.fg1)
                Text(existingTask == nil ? "REST IS OPTIONAL" : "SAVE CHANGES")
                    .font(S8Font.mono(9)).tracking(1.6)
                    .foregroundColor(c.fg3)
            }
            Spacer()
            S8Button(existingTask == nil ? "追加する" : "保存",
                     icon: "check",
                     variant: .primary,
                     fillWidth: false,
                     action: save)
            .disabled(isSaveDisabled)
            .opacity(isSaveDisabled ? 0.4 : 1.0)
        }
        .padding(.horizontal, 24).padding(.top, 12).padding(.bottom, 20)
        .background(c.surface)
        .overlay(alignment: .top) { S8Rule() }
    }

    // MARK: - Attachment helpers

    private func ingestPickerItems(_ items: [PhotosPickerItem]) async {
        for item in items {
            guard let data = try? await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data),
                  let name = AttachmentStore.writeJPEG(image) else { continue }
            draft.attachmentPaths.append(name)
        }
        pickerItems.removeAll()
    }

    private func removeAttachment(_ path: String) {
        draft.attachmentPaths.removeAll { $0 == path }
        AttachmentStore.remove(paths: [path])
    }

    // MARK: - Natural language parse

    private func resolvePlaceHintIfNeeded() {
        guard let hint = pendingPlaceHint, draft.place == nil else { return }
        let fetch = FetchDescriptor<PlaceTag>(predicate: #Predicate<PlaceTag> { $0.name == hint })
        draft.place = try? modelContext.fetch(fetch).first
        pendingPlaceHint = nil
    }

    private func scheduleParse(_ text: String) {
        nlDebounceTask?.cancel()
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            recognizedChips = []
            nlUnrecognizedWords = []
            return
        }
        nlDebounceTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            applyParse(trimmed)
        }
    }

    private func applyParse(_ text: String) {
        let result = PhraseParser.parse(text, aliases: aliases)
        if !result.titleRemainder.isEmpty {
            draft.title = result.titleRemainder
        } else if draft.title.isEmpty {
            draft.title = text
        }
        if let start = result.startDate {
            draft.isTimeSpecified = true
            draft.startDate = start
        }
        if let duration = result.duration {
            draft.duration = duration
            draft.isTimeSpecified = true
        }
        if let placeHint = result.placeHint {
            if let match = placeTags.first(where: { $0.name == placeHint }) {
                draft.place = match
            } else {
                pendingPlaceHint = placeHint
            }
        }
        if let categoryHint = result.categoryHint,
           let match = categories.first(where: { $0.name == categoryHint }) {
            draft.category = match
        }
        if let who = result.whoHint, !draft.participantNames.contains(who) {
            draft.participantNames.append(who)
        }
        if let other = result.otherHint {
            if draft.notes.isEmpty { draft.notes = other }
            else if !draft.notes.contains(other) { draft.notes += "\n" + other }
        }
        recognizedChips = result.recognizedChips
        nlUnrecognizedWords = result.unrecognizedWords
        if enableDictionarySuggestions {
            result.unrecognizedWords.forEach(SuggestionQueue.enqueue)
        }
    }

    // MARK: - Save

    private var isSaveDisabled: Bool {
        draft.title.trimmingCharacters(in: .whitespaces).isEmpty
            || (!draft.amountText.isEmpty && draft.parsedAmount == nil)
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

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.timeStyle = .short
        return f
    }()

    private func save() {
        let trimmedTitle = draft.title.trimmingCharacters(in: .whitespaces)
        guard !trimmedTitle.isEmpty else { return }
        guard draft.amountText.isEmpty || draft.parsedAmount != nil else { return }
        if let amount = draft.parsedAmount, amount > 1_000_000_000_000 {
            showAmountTooLargeAlert = true
            return
        }

        let rruleStr = Self.repeatOptions.first { $0.0 == draft.repeatPattern }?.2
        let amount = draft.parsedAmount
        let trimmedPayment = draft.paymentMethod.trimmingCharacters(in: .whitespaces)
        let paymentMethod = amount != nil && !trimmedPayment.isEmpty ? trimmedPayment : nil

        let task = existingTask ?? TaskItem(title: trimmedTitle, phase: .today)

        let oldStart = task.startDate
        let oldDuration = task.duration
        let oldOffsets = task.notificationOffsets
        let oldAmount = task.amount

        if draft.place == nil, let hint = pendingPlaceHint {
            let placeholder = PlaceTag(name: hint)
            modelContext.insert(placeholder)
            draft.place = placeholder
        }

        task.title = trimmedTitle
        task.category = draft.category
        task.startDate = draft.isTimeSpecified ? draft.startDate : nil
        task.duration = draft.isTimeSpecified ? draft.duration : 0
        task.place = draft.place
        task.notes = draft.notes
        task.isImportant = draft.isImportant
        task.colorHex = draft.colorHex
        task.attachmentPaths = draft.attachmentPaths
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
            print("[EventComposer] save failed: \(error)")
            assertionFailure("EventComposer save failed: \(error)")
            return
        }

        if task.startDate != oldStart || task.duration != oldDuration || task.notificationOffsets != oldOffsets {
            NotificationService.reschedule(for: task)
        }
        if task.amount != oldAmount {
            MoneyStats.recompute(for: task, context: modelContext)
        }

        dismiss()
    }
}

#Preview {
    EventComposerView()
        .modelContainer(PreviewData.container)
}
