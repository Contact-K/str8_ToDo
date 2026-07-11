//
//  DictionarySettingsView.swift
//  str8ToDo
//
//  辞書管理画面（企画書 E3 / P17）。CalendarSettingsView から遷移。
//  既定表現（isBuiltIn）は ON/OFF のみ、ユーザー登録分は追加/編集/削除可能、
//  クイック追加（P16）のサジェスト経由で貯まった未認識ワードは SuggestionQueue から
//  「登録待ち」として表示し、分類選択で PhraseAlias に確定するとキューから消える。
//

import SwiftUI
import SwiftData

struct DictionarySettingsView: View {
    @Environment(\.modelContext) private var context
    @Query private var aliases: [PhraseAlias]

    @AppStorage(AppSettingsKey.enableDictionarySuggestions)
    private var enableDictionarySuggestions = AppSettingsKey.enableDictionarySuggestionsDefault

    @State private var pendingWords: [String] = []
    @State private var showAddSheet = false
    @State private var editingAlias: PhraseAlias?
    @State private var pendingWordDraft: PendingWordDraft?

    private var builtInAliases: [PhraseAlias] {
        aliases.filter(\.isBuiltIn).sorted { $0.keyword < $1.keyword }
    }
    private var userAliases: [PhraseAlias] {
        aliases.filter { !$0.isBuiltIn }.sorted { $0.keyword < $1.keyword }
    }

    var body: some View {
        List {
            Section {
                Toggle("サジェスト機能を有効化", isOn: $enableDictionarySuggestions)
            } footer: {
                Text("クイック追加で認識できなかった語を辞書登録候補として表示します。")
            }

            Section("既定表現") {
                if builtInAliases.isEmpty {
                    Text("既定表現はありません").foregroundColor(.secondary)
                }
                ForEach(builtInAliases) { alias in
                    AliasRow(alias: alias, isBuiltIn: true, onEdit: {}, onDelete: {})
                }
            }

            Section("ユーザー登録分") {
                if userAliases.isEmpty {
                    Text("登録された辞書がありません").foregroundColor(.secondary)
                }
                ForEach(userAliases) { alias in
                    AliasRow(
                        alias: alias,
                        isBuiltIn: false,
                        onEdit: { editingAlias = alias },
                        onDelete: { delete(alias) }
                    )
                }
            }

            if !pendingWords.isEmpty {
                Section("登録待ち") {
                    ForEach(pendingWords, id: \.self) { word in
                        HStack {
                            Text(word)
                            Spacer()
                            Button("+分類選択") { pendingWordDraft = PendingWordDraft(word: word) }
                                .font(.caption)
                                .buttonStyle(.bordered)
                        }
                    }
                }
            }
        }
        .navigationTitle("辞書管理")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("新規追加") { showAddSheet = true }
            }
        }
        .onAppear { pendingWords = SuggestionQueue.all() }
        .sheet(isPresented: $showAddSheet) {
            AliasEditSheet(alias: nil)
        }
        .sheet(item: $editingAlias) { alias in
            AliasEditSheet(alias: alias)
        }
        .sheet(item: $pendingWordDraft, onDismiss: { pendingWords = SuggestionQueue.all() }) { draft in
            AliasEditSheet(alias: nil, prefillWord: draft.word, onSaved: { SuggestionQueue.dequeue(draft.word) })
        }
    }

    private func delete(_ alias: PhraseAlias) {
        context.delete(alias)
        try? context.save()
    }
}

/// 「登録待ち」ワードの分類選択ダイアログ表示用（String は Identifiable でないためラップ）。
private struct PendingWordDraft: Identifiable {
    let word: String
    var id: String { word }
}

/// 既定表現/ユーザー登録分の1行。isBuiltIn=true は Toggle のみ（swipeActions なし＝削除・編集不可）。
private struct AliasRow: View {
    @Bindable var alias: PhraseAlias
    let isBuiltIn: Bool
    let onEdit: () -> Void
    let onDelete: () -> Void
    @Environment(\.modelContext) private var context

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(alias.keyword)
                Text("\(alias.whCategory.label) → \(alias.replacement)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Toggle("", isOn: $alias.isEnabled)
                .labelsHidden()
                .onChange(of: alias.isEnabled) { _, _ in try? context.save() }
        }
        .swipeActions(edge: .trailing) {
            if !isBuiltIn {
                Button("削除", role: .destructive, action: onDelete)
            }
        }
        .swipeActions(edge: .leading) {
            if !isBuiltIn {
                Button("編集", action: onEdit).tint(.blue)
            }
        }
    }
}

/// 新規追加/編集/登録待ち確定を兼ねる共通ダイアログ（keyword / whCategory / replacement 入力）。
private struct AliasEditSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    /// nil なら新規追加（登録待ち確定含む）、非nilなら既存ユーザー登録分の編集。
    let alias: PhraseAlias?
    var prefillWord: String = ""
    /// 登録待ちワードから確定した際、キューから外すためのコールバック。
    var onSaved: (() -> Void)?

    @State private var keyword = ""
    @State private var category: WHCategory = .other
    @State private var replacement = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("キーワード") {
                    TextField("例: ポモ", text: $keyword)
                }
                Section("分類") {
                    Picker("分類", selection: $category) {
                        ForEach(WHCategory.allCases) { cat in
                            Text(cat.label).tag(cat)
                        }
                    }
                }
                Section("変換後の値") {
                    TextField("例: 25分", text: $replacement)
                }
            }
            .navigationTitle(alias == nil ? "辞書に登録" : "辞書を編集")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存", action: save)
                        .disabled(keyword.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .onAppear {
            if let alias {
                keyword = alias.keyword
                category = alias.whCategory
                replacement = alias.replacement
            } else if !prefillWord.isEmpty {
                keyword = prefillWord
            }
        }
    }

    private func save() {
        let trimmedKeyword = keyword.trimmingCharacters(in: .whitespaces)
        guard !trimmedKeyword.isEmpty else { return }
        let trimmedReplacement = replacement.trimmingCharacters(in: .whitespaces)
        let finalReplacement = trimmedReplacement.isEmpty ? trimmedKeyword : trimmedReplacement

        if let alias {
            alias.keyword = trimmedKeyword
            alias.whCategory = category
            alias.replacement = finalReplacement
        } else {
            context.insert(PhraseAlias(keyword: trimmedKeyword, whCategory: category, replacement: finalReplacement))
        }
        try? context.save()
        onSaved?()
        dismiss()
    }
}

#Preview {
    NavigationStack {
        DictionarySettingsView()
    }
    .modelContainer(PreviewData.container)
}
