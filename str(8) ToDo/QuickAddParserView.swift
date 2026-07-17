//
//  QuickAddParserView.swift
//  str8ToDo
//
//  自然文クイック追加（企画書 E2 / P16）。1行入力 → PhraseParser で日時/場所/カテゴリ/所要時間を
//  自動認識してチップ化。「保存」で TaskItem を即作成（EventComposerView は開かない）、
//  「詳細を追加」でプリフィルした EventComposerView を開く。
//

import SwiftUI
import SwiftData

@MainActor
struct QuickAddParserView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    private var c: S8Palette { S8Palette.of(scheme) }

    @Query(filter: #Predicate<PhraseAlias> { $0.isEnabled }) private var aliases: [PhraseAlias]

    /// サジェスト機能の ON/OFF。設定 UI 本体は P17（辞書管理画面）で提供、ここでは値を購読するだけ。
    @AppStorage(AppSettingsKey.enableDictionarySuggestions)
    private var enableDictionarySuggestions = AppSettingsKey.enableDictionarySuggestionsDefault

    @State private var text = ""
    @State private var parseResult = PhraseParser.ParseResult()
    @State private var debounceTask: Task<Void, Never>?
    @State private var showComposer = false
    @State private var aliasDraftWord: AliasCandidateWord?

    var body: some View {
        let c = self.c
        VStack(spacing: 0) {
            // Handoff 03d ヘッダ: [キャンセル][クイック追加][spacer]
            HStack {
                Button("キャンセル") { dismiss() }
                    .font(S8Font.jp(14))
                    .foregroundColor(c.fg2)
                Spacer()
                Text("クイック追加").font(S8Font.jp(16, .bold)).foregroundColor(c.fg1)
                Spacer()
                Color.clear.frame(width: 64, height: 1)
            }
            .padding(.horizontal, 24).padding(.vertical, 12)

            ScrollView {
                VStack(spacing: 0) {
                    // INPUT
                    sectionCap("INPUT", jp: "自然文で入力")
                        .padding(.top, 8)
                    // 太い accent 縁のテキスト入力
                    TextField("例: 明日 14:00 大学でレポート", text: $text, axis: .vertical)
                        .font(S8Font.jp(14))
                        .foregroundColor(c.fg1)
                        .padding(.horizontal, 14).padding(.vertical, 12)
                        .background(c.surface)
                        .overlay(RoundedRectangle(cornerRadius: S8Radius.md).stroke(c.accent, lineWidth: 1.5))
                        .onChange(of: text) { _, newValue in
                            scheduleParse(newValue)
                        }

                    // PARSED
                    if !parseResult.recognizedChips.isEmpty {
                        sectionCap("PARSED", jp: "自動認識")
                            .padding(.top, 20)
                        parsedChips
                            .padding(.top, 4)
                    }

                    // DICTIONARY
                    if enableDictionarySuggestions && !parseResult.unrecognizedWords.isEmpty {
                        sectionCap("DICTIONARY", jp: "辞書に登録できそうな語")
                            .padding(.top, 20)
                        VStack(spacing: 0) {
                            ForEach(parseResult.unrecognizedWords, id: \.self) { word in
                                HStack {
                                    Text(word).font(S8Font.jp(14)).foregroundColor(c.fg1)
                                    Spacer()
                                    Button(action: { aliasDraftWord = AliasCandidateWord(word: word) }) {
                                        Text("+ 分類選択")
                                            .font(S8Font.jp(11.5)).foregroundColor(c.fg2)
                                            .padding(.horizontal, 10).padding(.vertical, 5)
                                            .overlay(RoundedRectangle(cornerRadius: S8Radius.md).stroke(c.lineStrong, lineWidth: 1))
                                    }
                                    .buttonStyle(.plain)
                                }
                                .padding(.vertical, 12)
                                .overlay(alignment: .top) { S8Rule() }
                            }
                        }
                        Text("「\(parseResult.unrecognizedWords.first ?? "語")」→「25分」のように言い換えを登録すると次から自動認識")
                            .font(S8Font.jp(11)).foregroundColor(c.fg3)
                            .padding(.top, 6)
                    }
                    Color.clear.frame(height: 24)
                }
                .padding(.horizontal, 24)
            }

            // 固定ボトム: 保存 / 詳細を追加
            HStack(spacing: 12) {
                S8Button("保存", variant: .secondary, enabled: !isEmptyInput, action: saveDirect)
                S8Button("詳細を追加", variant: .primary, enabled: !isEmptyInput, action: openComposer)
            }
            .padding(.horizontal, 24).padding(.top, 14).padding(.bottom, 20)
            .background(c.surface)
            .overlay(alignment: .top) { S8Rule() }
        }
        .background(c.paper.ignoresSafeArea())
        .sheet(isPresented: $showComposer) {
            // P18 M13: ParseResult の全ヒント（titleRemainder/startDate/duration/placeHint/
            // categoryHint(→Profile優先/Category)/whoHint/otherHint）を一括プリフィル init に渡す。
            // startDate を検出できたのに duration 未検出だと isTimeSpecified が false 扱いになる
            // （ComposerDraft の仕様）ため、時刻を検出できた場合は既定60分を明示的に渡す。
            let profile = matchedProfile()
            let category = profile == nil ? matchedCategory() : nil
            EventComposerView(
                initialStart: parseResult.startDate,
                initialDuration: parseResult.startDate != nil ? (parseResult.duration ?? 3600) : nil,
                prefillTitle: parseResult.titleRemainder.isEmpty ? nil : parseResult.titleRemainder,
                prefillPlace: parseResult.placeHint,
                prefillCategory: category,
                prefillProfile: profile,
                prefillParticipants: parseResult.whoHint.map { [$0] } ?? [],
                prefillNotes: parseResult.otherHint ?? "",
                prefillRRule: parseResult.rrule,
                prefillNotificationOffsets: parseResult.reminderOffsets,
                prefillIsImportant: parseResult.isImportant
            )
        }
        .sheet(item: $aliasDraftWord) { draft in
            NewAliasSheet(word: draft.word)
        }
    }

    private var isEmptyInput: Bool {
        text.trimmingCharacters(in: .whitespaces).isEmpty
    }

    // MARK: - 自動認識チップ（Handoff 03d: 「いつ:」「どこ:」等の wash 色ピル）

    private var parsedChips: some View {
        let items = parseResult.recognizedChips
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, chip in
                    let (cat, value) = chip
                    HStack(spacing: 5) {
                        S8Icon(name: iconName(cat), size: 12, color: chipColorFG(cat))
                        Text("\(chipLabel(cat)): \(value)")
                            .font(S8Font.jp(11.5)).foregroundColor(chipColorFG(cat))
                    }
                    .padding(.horizontal, 11).padding(.vertical, 5)
                    .background(chipColorBG(cat))
                    .clipShape(Capsule())
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func sectionCap(_ tag: String, jp: String) -> some View {
        HStack(spacing: 10) {
            Text(tag).font(S8Font.mono(10)).tracking(1.6).foregroundColor(c.fg3)
            Text(jp).font(S8Font.jp(13, .medium)).foregroundColor(c.fg2)
            S8Rule()
        }
        .padding(.bottom, 8)
    }

    private func chipColorFG(_ cat: WHCategory) -> Color {
        switch cat {
        case .when:   return c.info
        case .where_: return c.ok
        case .how:    return c.accentInk
        case .who:    return c.info
        case .which:  return c.accentInk
        case .what:   return c.fg1
        case .other:  return c.fg3
        }
    }

    private func chipColorBG(_ cat: WHCategory) -> Color {
        switch cat {
        case .when:   return c.infoWash
        case .where_: return c.okWash
        case .how:    return c.accentWash
        case .who:    return c.infoWash
        case .which:  return c.accentWash
        case .what:   return c.surface2
        case .other:  return c.surface2
        }
    }

    private func chipLabel(_ cat: WHCategory) -> String {
        switch cat {
        case .when: return "いつ"
        case .where_: return "どこ"
        case .how: return "どのくらい"
        case .who: return "誰と"
        case .which: return "どれ"
        case .what: return "何を"
        case .other: return "その他"
        }
    }

    private func iconName(_ cat: WHCategory) -> String {
        switch cat {
        case .when: return "clock"
        case .where_: return "map-pin"
        case .how: return "gauge"
        case .who: return "users"
        case .which: return "tag"
        case .what: return "text-cursor"
        case .other: return "file"
        }
    }

    // MARK: - パース（debounce 300ms）

    private func scheduleParse(_ newValue: String) {
        debounceTask?.cancel()
        debounceTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            parseResult = PhraseParser.parse(newValue, aliases: aliases)
            // 辞書管理画面（P17）の「登録待ち」セクションに引き渡す。既存の直接追加動線（+分類選択）と並列。
            if enableDictionarySuggestions {
                parseResult.unrecognizedWords.forEach(SuggestionQueue.enqueue)
            }
        }
    }

    // MARK: - 操作

    /// 「保存」：パース結果から TaskItem を即作成。EventComposerView は開かない。
    /// Phase 16 拡張: JPRuleLayer が抽出した startDate/duration/rrule/reminderOffsets/isImportant
    /// を TaskItem に反映する。startDate が nil のときのみ浮遊タスクとしてリスト入り。
    private func saveDirect() {
        let remainder = parseResult.titleRemainder.trimmingCharacters(in: .whitespaces)
        let title = remainder.isEmpty ? text.trimmingCharacters(in: .whitespaces) : remainder
        guard !title.isEmpty else { return }

        // which ヒントは Profile を優先照合（例: "会社"）、無ければ Category を照合。
        let profile = matchedProfile()
        let category = profile == nil ? matchedCategory() : nil

        let start = parseResult.startDate
        let dur = start != nil ? (parseResult.duration ?? 3600) : 0

        let task = TaskItem(
            title: title,
            category: category,
            startDate: start,
            duration: dur,
            place: matchedPlace(),
            phase: .today,
            rrule: parseResult.rrule,
            notes: parseResult.otherHint ?? "",
            isImportant: parseResult.isImportant,
            notificationOffsets: parseResult.reminderOffsets,
            profile: profile,
            participantNames: parseResult.whoHint.map { [$0] } ?? []
        )
        context.insert(task)
        do {
            try context.save()
        } catch {
            print("[QuickAddParser] save failed: \(error)")
            assertionFailure("QuickAddParser save failed: \(error)")
            return
        }
        NotificationService.reschedule(for: task)
        dismiss()
    }

    /// 「詳細を追加」：パース結果の全ヒントをプリフィルして EventComposerView を開く（P18 M13）。
    private func openComposer() {
        showComposer = true
    }

    private func matchedProfile() -> Profile? {
        guard let hint = parseResult.categoryHint else { return nil }
        return try? context.fetch(FetchDescriptor<Profile>(predicate: #Predicate { $0.name == hint })).first
    }

    private func matchedCategory() -> Category? {
        guard let hint = parseResult.categoryHint else { return nil }
        return try? context.fetch(FetchDescriptor<Category>(predicate: #Predicate { $0.name == hint })).first
    }

    private func matchedPlace() -> PlaceTag? {
        guard let hint = parseResult.placeHint else { return nil }
        if let existing = try? context.fetch(FetchDescriptor<PlaceTag>(predicate: #Predicate { $0.name == hint })).first {
            return existing
        }
        // 自然文ヒントで新規 PlaceTag を作成（座標なし）。後で LocationPicker から座標を付けられる。
        let placeholder = PlaceTag(name: hint)
        context.insert(placeholder)
        return placeholder
    }
}

/// サジェストからの新規 PhraseAlias 登録ダイアログ（分類選択のみの簡易版。管理 UI 本体は P17）。
/// EventComposerView からも同一 UI で登録できるように internal 公開。
struct NewAliasSheet: View {
    let word: String
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var existingAliases: [PhraseAlias]

    @State private var category: WHCategory = .other
    @State private var replacement: String = ""
    @State private var showDuplicateAlert = false

    var body: some View {
        NavigationStack {
            Form {
                Section("語") {
                    Text(word)
                }
                Section("分類") {
                    S8Picker(
                        selection: $category,
                        options: WHCategory.allCases.map { ($0, $0.label) },
                        style: .chips
                    )
                }
                Section("変換後の値") {
                    TextField("例: 大学図書館", text: $replacement)
                }
            }
            .navigationTitle("辞書に登録")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("登録", action: register)
                }
            }
            .alert("重複したキーワード", isPresented: $showDuplicateAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("「\(word)」は既に辞書に登録されています")
            }
        }
    }

    private func register() {
        // H2: keyword/replacement は改行除去→trim→100文字上限で正規化。
        let keyword = PhraseAlias.sanitizeEntry(word)
        guard !keyword.isEmpty else { return }
        let trimmed = PhraseAlias.sanitizeEntry(replacement)

        // H3: keyword の一意性維持（既存 aliases と重複していれば拒否）。
        guard !existingAliases.contains(where: { $0.keyword == keyword }) else {
            showDuplicateAlert = true
            return
        }

        context.insert(PhraseAlias(keyword: keyword, whCategory: category, replacement: trimmed.isEmpty ? keyword : trimmed))
        try? context.save()
        SuggestionQueue.dequeue(word)  // 直接登録済みなので「登録待ち」からも外す
        dismiss()
    }
}

#Preview {
    QuickAddParserView()
        .modelContainer(PreviewData.container)
}
