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
        NavigationStack {
            Form {
                Section("自然文で入力") {
                    TextField("例: 明日 14:00 大学でレポート", text: $text)
                        .onChange(of: text) { _, newValue in
                            scheduleParse(newValue)
                        }
                }

                if !parseResult.recognizedChips.isEmpty {
                    Section("自動認識") {
                        chipsView
                    }
                }

                if enableDictionarySuggestions && !parseResult.unrecognizedWords.isEmpty {
                    Section("辞書に登録できそうな語") {
                        ForEach(parseResult.unrecognizedWords, id: \.self) { word in
                            HStack {
                                Text(word)
                                Spacer()
                                Button("+分類選択") { aliasDraftWord = AliasCandidateWord(word: word) }
                                    .font(.caption)
                                    .buttonStyle(.bordered)
                            }
                        }
                    }
                }
            }
            .navigationTitle("クイック追加")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                HStack(spacing: 12) {
                    Button("保存", action: saveDirect)
                        .buttonStyle(.bordered)
                        .disabled(isEmptyInput)
                    Button("詳細を追加", action: openComposer)
                        .buttonStyle(.borderedProminent)
                        .disabled(isEmptyInput)
                }
                .padding()
                .background(.bar)
            }
        }
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
                prefillNotes: parseResult.otherHint ?? ""
            )
        }
        .sheet(item: $aliasDraftWord) { draft in
            NewAliasSheet(word: draft.word)
        }
    }

    private var isEmptyInput: Bool {
        text.trimmingCharacters(in: .whitespaces).isEmpty
    }

    // MARK: - 自動認識チップ

    private var chipsView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(parseResult.recognizedChips.enumerated()), id: \.offset) { _, chip in
                    let (category, value) = chip
                    Label(value, systemImage: category.iconName)
                        .font(.caption)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(chipColor(for: category).opacity(0.15)))
                        .foregroundStyle(chipColor(for: category))
                }
            }
            .padding(.vertical, 4)
        }
        .listRowInsets(EdgeInsets())
    }

    private func chipColor(for category: WHCategory) -> Color {
        switch category {
        case .what:   return .primary
        case .when:   return .blue
        case .where_: return .green
        case .which:  return .orange
        case .who:    return .purple
        case .how:    return .pink
        case .other:  return .gray
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
    private func saveDirect() {
        let remainder = parseResult.titleRemainder.trimmingCharacters(in: .whitespaces)
        let title = remainder.isEmpty ? text.trimmingCharacters(in: .whitespaces) : remainder
        guard !title.isEmpty else { return }

        // which ヒントは Profile を優先照合（例: "会社"）、無ければ Category を照合。
        let profile = matchedProfile()
        let category = profile == nil ? matchedCategory() : nil

        let task = TaskItem(
            title: title,
            category: category,
            startDate: parseResult.startDate,
            duration: parseResult.duration ?? 0,
            place: matchedPlace(),
            phase: .today,
            profile: profile
        )
        context.insert(task)
        try? context.save()
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
        return try? context.fetch(FetchDescriptor<PlaceTag>(predicate: #Predicate { $0.name == hint })).first
    }
}

/// サジェストからの新規 PhraseAlias 登録ダイアログ（分類選択のみの簡易版。管理 UI 本体は P17）。
private struct NewAliasSheet: View {
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
                    Picker("分類", selection: $category) {
                        ForEach(WHCategory.allCases) { cat in
                            Text(cat.label).tag(cat)
                        }
                    }
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
