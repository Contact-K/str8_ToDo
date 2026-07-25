//
//  DictionarySettingsView.swift
//  str8ToDo
//
//  辞書管理画面（企画書 E3 / P17）。SettingsRootView から遷移。
//  既定表現（isBuiltIn）は ON/OFF のみ、ユーザー登録分は追加/編集/削除可能、
//  クイック追加（P16）のサジェスト経由で貯まった未認識ワードは SuggestionQueue から
//  「登録待ち」として表示し、分類選択で PhraseAlias に確定するとキューから消える。
//

import SwiftUI
import SwiftData

struct DictionarySettingsView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.colorScheme) private var scheme
    private var c: S8Palette { S8Palette.of(scheme) }
    @Environment(\.dismiss) private var dismiss
    @Query private var aliases: [PhraseAlias]

    @AppStorage(AppSettingsKey.enableDictionarySuggestions)
    private var enableDictionarySuggestions = AppSettingsKey.enableDictionarySuggestionsDefault

    @State private var pendingWords: [String] = []
    @State private var showAddSheet = false
    @State private var editingAlias: PhraseAlias?
    @State private var pendingWordDraft: AliasCandidateWord?

    private var builtInAliases: [PhraseAlias] {
        aliases.filter(\.isBuiltIn).sorted { $0.keyword < $1.keyword }
    }
    private var userAliases: [PhraseAlias] {
        aliases.filter { !$0.isBuiltIn }.sorted { $0.keyword < $1.keyword }
    }

    var body: some View {
        let c = self.c
        VStack(spacing: 0) {
            // Handoff 07c ヘッダ: [chevron-left][辞書管理][新規追加]
            HStack {
                Button(action: { dismiss() }) {
                    S8Icon(name: "chevron-left", size: 16, color: c.fg2)
                        .frame(width: 44, height: 44, alignment: .leading)
                }
                .buttonStyle(.plain)
                Spacer()
                Text("辞書管理").font(S8Font.jp(16, .bold)).foregroundColor(c.fg1)
                Spacer()
                S8Button("新規追加", icon: "plus", variant: .primary, fillWidth: false, action: { showAddSheet = true })
                    .padding(.trailing, 8)
            }
            .padding(.horizontal, 12)

            ScrollView {
                VStack(spacing: 0) {
                    // サジェスト有効化トグル
                    suggestionToggleRow

                    // BUILT-IN
                    sectionCap("BUILT-IN", jp: "既定表現 ── ON/OFFのみ")
                        .padding(.top, 20)
                    if builtInAliases.isEmpty {
                        emptyRow("既定表現はありません")
                    }
                    ForEach(builtInAliases) { alias in
                        aliasRow(alias, isBuiltIn: true)
                    }

                    // USER
                    sectionCap("USER", jp: "ユーザー登録分")
                        .padding(.top, 20)
                    if userAliases.isEmpty {
                        emptyRow("登録された辞書がありません")
                    }
                    ForEach(userAliases) { alias in
                        aliasRow(alias, isBuiltIn: false)
                    }

                    // PENDING
                    if !pendingWords.isEmpty {
                        sectionCap("PENDING", jp: "登録待ち")
                            .padding(.top, 20)
                        ForEach(pendingWords, id: \.self) { word in
                            pendingRow(word)
                        }
                        Button(action: {
                            SuggestionQueue.clear()
                            pendingWords = []
                        }) {
                            Text("すべてクリア")
                                .font(S8Font.jp(11.5)).foregroundColor(c.fg3)
                        }
                        .buttonStyle(.plain)
                    }
                    Color.clear.frame(height: 24)
                }
                .padding(.horizontal, 24)
            }
        }
        .background(c.paper.ignoresSafeArea())
        .navigationBarBackButtonHidden()
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

    // MARK: - Rows

    private var suggestionToggleRow: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("サジェスト機能を有効化").font(S8Font.jp(14)).foregroundColor(c.fg1)
                Text("未認識語を登録候補として表示")
                    .font(S8Font.jp(10.5)).foregroundColor(c.fg3)
            }
            Spacer()
            S8Toggle(on: enableDictionarySuggestions) {
                enableDictionarySuggestions.toggle()
            }
        }
        .padding(.vertical, 13)
        .overlay(alignment: .top) { S8Rule() }
    }

    private func sectionCap(_ tag: String, jp: String) -> some View {
        HStack(spacing: 10) {
            Text(tag).font(S8Font.mono(10)).tracking(1.6).foregroundColor(c.fg3)
            Text(jp).font(S8Font.jp(13, .medium)).foregroundColor(c.fg2)
            S8Rule()
        }
        .padding(.bottom, 8)
    }

    /// Handoff 07c: keyword → arrow-right → replacement + カテゴリチップ + toggle/pencil/trash
    private func aliasRow(_ alias: PhraseAlias, isBuiltIn: Bool) -> some View {
        HStack(spacing: 8) {
            Text(alias.keyword).font(S8Font.jp(14, .bold)).foregroundColor(c.fg1)
            S8Icon(name: "arrow-right", size: 12, color: c.fg3)
            Text(alias.replacement).font(S8Font.jp(13)).foregroundColor(c.fg2)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            categoryChip(alias.whCategory)
            if isBuiltIn {
                S8Toggle(on: alias.isEnabled) {
                    alias.isEnabled.toggle()
                    try? context.save()
                }
            } else {
                Button(action: { editingAlias = alias }) {
                    S8Icon(name: "settings", size: 14, color: c.fg3).padding(5)
                }
                .buttonStyle(.plain)
                Button(action: { delete(alias) }) {
                    S8Icon(name: "trash", size: 14, color: c.fg3).padding(5)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 12)
        .overlay(alignment: .top) { S8Rule() }
    }

    /// Handoff 07c: 登録待ちの行（word + "+ 分類選択" ボタン）。
    private func pendingRow(_ word: String) -> some View {
        HStack(spacing: 12) {
            Text(word).font(S8Font.jp(14)).foregroundColor(c.fg1)
            Spacer()
            Button(action: { pendingWordDraft = AliasCandidateWord(word: word) }) {
                Text("+ 分類選択")
                    .font(S8Font.jp(11.5)).foregroundColor(c.fg2)
                    .padding(.horizontal, 11).padding(.vertical, 5)
                    .overlay(Capsule().stroke(c.lineStrong, lineWidth: 1))
            }
            .buttonStyle(.plain)
            Button(action: {
                SuggestionQueue.dequeue(word)
                pendingWords = SuggestionQueue.all()
            }) {
                S8Icon(name: "trash", size: 14, color: c.fg3).padding(5)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 12)
        .overlay(alignment: .top) { S8Rule() }
    }

    /// カテゴリピル（Handoff: いつ/どこ/どのくらい etc、対応 wash 色）。
    private func categoryChip(_ cat: WHCategory) -> some View {
        let (fg, bg): (Color, Color) = {
            switch cat {
            case .when:   return (c.info, c.infoWash)
            case .where_: return (c.ok, c.okWash)
            case .how:    return (c.accentInk, c.accentWash)
            case .who:    return (c.info, c.infoWash)
            case .which:  return (c.accentInk, c.accentWash)
            case .what:   return (c.fg2, c.surface2)
            case .other:  return (c.fg3, c.surface2)
            }
        }()
        return Text(cat.label)
            .font(S8Font.mono(8.5)).tracking(1.0).foregroundColor(fg)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(bg)
            .clipShape(Capsule())
    }

    private func emptyRow(_ text: String) -> some View {
        Text(text)
            .font(S8Font.jp(12.5)).foregroundColor(c.fg3)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .top) { S8Rule() }
    }

    private func delete(_ alias: PhraseAlias) {
        context.delete(alias)
        try? context.save()
    }
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
            S8Toggle(on: alias.isEnabled) {
                alias.isEnabled.toggle()
                try? context.save()
            }
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
    @Environment(\.colorScheme) private var scheme
    private var c: S8Palette { S8Palette.of(scheme) }
    @Query private var existingAliases: [PhraseAlias]

    /// nil なら新規追加（登録待ち確定含む）、非nilなら既存ユーザー登録分の編集。
    let alias: PhraseAlias?
    var prefillWord: String = ""
    /// 登録待ちワードから確定した際、キューから外すためのコールバック。
    var onSaved: (() -> Void)?

    @State private var keyword = ""
    @State private var category: WHCategory = .other
    @State private var replacement = ""
    @State private var showDuplicateAlert = false

    var body: some View {
        let c = self.c
        VStack(spacing: 0) {
            HStack {
                Button("キャンセル") { dismiss() }
                    .font(S8Font.jp(14)).foregroundColor(c.fg2)
                Spacer()
                Text(alias == nil ? "辞書に登録" : "辞書を編集")
                    .font(S8Font.jp(16, .bold)).foregroundColor(c.fg1)
                Spacer()
                Button("保存", action: save)
                    .font(S8Font.jp(14, .bold))
                    .foregroundColor(keyword.trimmingCharacters(in: .whitespaces).isEmpty ? c.fg3 : c.accentInk)
                    .disabled(keyword.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.horizontal, 24).padding(.vertical, 12)

            ScrollView {
                VStack(spacing: 0) {
                    sectionCap("KEYWORD", jp: "キーワード")
                        .padding(.top, 8)
                    S8Field(placeholder: "例: ポモ", text: $keyword)
                        .padding(.top, 8)

                    sectionCap("CATEGORY", jp: "分類")
                        .padding(.top, 20)
                    // 分類を pill 群に
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(WHCategory.allCases) { cat in
                                Button(action: { category = cat }) {
                                    Text(cat.label)
                                        .font(S8Font.jp(12, category == cat ? .bold : .medium))
                                        .foregroundColor(category == cat ? c.onAccent : c.fg2)
                                        .padding(.horizontal, 11).padding(.vertical, 6)
                                        .background(category == cat ? c.accent : Color.clear)
                                        .overlay(Capsule().stroke(category == cat ? c.accent : c.lineStrong, lineWidth: 1))
                                        .clipShape(Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.top, 4)

                    sectionCap("REPLACEMENT", jp: "変換後の値")
                        .padding(.top, 20)
                    S8Field(placeholder: "例: 25分", text: $replacement)
                        .padding(.top, 8)

                    Color.clear.frame(height: 24)
                }
                .padding(.horizontal, 24)
            }
        }
        .background(c.paper.ignoresSafeArea())
        .alert("重複したキーワード", isPresented: $showDuplicateAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("同じキーワードが既に登録されています")
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

    private func sectionCap(_ tag: String, jp: String) -> some View {
        HStack(spacing: 10) {
            Text(tag).font(S8Font.mono(10)).tracking(1.6).foregroundColor(c.fg3)
            Text(jp).font(S8Font.jp(13, .medium)).foregroundColor(c.fg2)
            S8Rule()
        }
        .padding(.bottom, 8)
    }

    private func save() {
        // H2: keyword/replacement は改行除去→trim→100文字上限で正規化。
        let trimmedKeyword = PhraseAlias.sanitizeEntry(keyword)
        guard !trimmedKeyword.isEmpty else { return }
        let trimmedReplacement = PhraseAlias.sanitizeEntry(replacement)
        let finalReplacement = trimmedReplacement.isEmpty ? trimmedKeyword : trimmedReplacement

        // H3: keyword の一意性維持（自分自身以外の既存 aliases と重複していれば拒否）。
        let isDuplicate = existingAliases.contains { $0.keyword == trimmedKeyword && $0.id != alias?.id }
        guard !isDuplicate else {
            showDuplicateAlert = true
            return
        }

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
