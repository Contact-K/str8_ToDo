//
//  SettingsRootView.swift
//  str(8) ToDo
//
//  ホイール6番目タブの設定画面。str(8)_Talk S8Profile.swift の S8SetRow パターンに倣った
//  Handoff スタイル（トップバー + セクション + 各行）。旧 CalendarSettingsView の複雑な機能
//  （時間割編集・バックアップ・カテゴリ色編集）は NavigationLink 経由で呼び出す。
//

import SwiftUI
import SwiftData

struct SettingsRootView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.colorScheme) private var scheme
    private var c: S8Palette { S8Palette.of(scheme) }

    @AppStorage(AppSettingsKey.syncSystemCalendar) private var syncSystemCalendar = AppSettingsKey.syncSystemCalendarDefault
    @AppStorage(AppSettingsKey.enableNotifications) private var enableNotifications = AppSettingsKey.enableNotificationsDefault
    @AppStorage(AppSettingsKey.enableDictionarySuggestions) private var enableDictionarySuggestions = AppSettingsKey.enableDictionarySuggestionsDefault
    // タイマープリセットは Timer タブへ移設（2026-07-14）。
    @AppStorage("s8_accent") private var accentRaw = S8Accent.anzu.rawValue
    /// "system" / "light" / "dark"（アプリレベルのテーマ）
    @AppStorage("s8_theme") private var themeRaw: String = "system"
    /// タブナビ方式（true=ホイール / false=タブバー）。Talk 移植。
    @AppStorage(AppSettingsKey.navWheel) private var navWheel = AppSettingsKey.navWheelDefault

    @State private var eventKit = EventKitService()
    @State private var showDictionary = false
    @State private var showAdvancedSettings = false
    // プロフィール編集シート。nil=非表示、"new"=新規追加、Profile=既存編集。
    @State private var editingProfile: Profile? = nil
    @State private var showNewProfile: Bool = false

    @Query(sort: \Profile.name) private var profiles: [Profile]

    private var currentAccent: S8Accent { S8Accent(rawValue: accentRaw) ?? .anzu }

    var body: some View {
        let c = self.c
        VStack(spacing: 0) {
            S8TopBar("設定", sub: "settings · profile & sync") { EmptyView() }
            ScrollView {
                VStack(spacing: 0) {
                    // MARK: - 同期
                    S8SectionLabel(text: "同期")
                    S8SetRow(icon: "calendar", label: "システムカレンダー同期") {
                        S8Toggle(on: syncSystemCalendar) {
                            syncSystemCalendar.toggle()
                            if syncSystemCalendar {
                                Task { _ = await eventKit.requestAccess() }
                            }
                        }
                    }
                    S8Rule()
                    S8SetRow(icon: "bell", label: "通知を有効化") {
                        S8Toggle(on: enableNotifications) { enableNotifications.toggle() }
                    }

                    // MARK: - 表示
                    S8SectionLabel(text: "表示")
                    themeRow
                    S8Rule()
                    accentRow
                    S8Rule()
                    S8SetRow(icon: "circle-dot", label: "ホイールナビ") {
                        S8Toggle(on: navWheel) { navWheel.toggle() }
                    }

                    // タイマープリセットは Timer タブ内へ移設（2026-07-14）。
                    // マイ時間割・曜日割当は Calendar タブ内 週ビューヘッダから開く CalendarSettingsView へ集約。

                    // MARK: - 入力
                    S8SectionLabel(text: "入力の設定")
                    S8SetRow(icon: "text-cursor", label: "サジェスト機能を有効化") {
                        S8Toggle(on: enableDictionarySuggestions) { enableDictionarySuggestions.toggle() }
                    }
                    S8Rule()
                    S8SetRow(icon: "bookmark", label: "辞書管理", trailing: {
                        S8Icon(name: "chevron-right", size: 16, color: c.fg3)
                    }, onTap: { showDictionary = true })

                    // MARK: - プロフィール
                    S8SectionLabel(text: "プロフィール")
                    ForEach(Array(profiles.enumerated()), id: \.element.id) { i, p in
                        S8SetRow(icon: p.iconName, label: p.name, trailing: {
                            S8Icon(name: "chevron-right", size: 16, color: c.fg3)
                        }, onTap: { editingProfile = p })
                        if i < profiles.count - 1 { S8Rule() }
                    }
                    if !profiles.isEmpty { S8Rule() }
                    S8SetRow(icon: "plus", label: "プロフィールを追加", trailing: {
                        EmptyView()
                    }, onTap: { showNewProfile = true })

                    // MARK: - バックアップ
                    // ponytail 2026-07-14: 詳細シートを「バックアップ」に集約。マイ時間割は Calendar タブへ移設済。
                    // フル抽出は次サイクル（現状は同じ CalendarSettingsView を開いてバックアップ操作のみ想定）。
                    S8SectionLabel(text: "バックアップ")
                    S8SetRow(icon: "share", label: "エクスポート／インポート", trailing: {
                        S8Icon(name: "chevron-right", size: 16, color: c.fg3)
                    }, onTap: { showAdvancedSettings = true })

                    Color.clear.frame(height: 32)
                }
            }
        }
        // 背景はグローバル S8SamonPaper に任せる
        .sheet(isPresented: $showDictionary) {
            NavigationStack { DictionarySettingsView() }
        }
        .sheet(isPresented: $showAdvancedSettings) {
            NavigationStack { CalendarSettingsView() }
        }
        .sheet(item: $editingProfile) { profile in
            ProfileEditSheet(profile: profile, isNew: false)
        }
        .sheet(isPresented: $showNewProfile) {
            ProfileEditSheet(profile: nil, isNew: true)
        }
    }

    // MARK: - Rows

    /// テーマ 3択（システム / ライト / ダーク）。S8 Talk 版と同じ流儀。
    private var themeRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 14) {
                S8Icon(name: themeRaw == "dark" ? "moon" : "sun", size: 20, color: c.fg2)
                Text("テーマ").font(S8Font.jp(15)).foregroundColor(c.fg1)
                Spacer()
            }
            HStack(spacing: 8) {
                S8Chip("システム", selected: themeRaw == "system") { themeRaw = "system" }
                S8Chip("ライト", icon: "sun", selected: themeRaw == "light") { themeRaw = "light" }
                S8Chip("ダーク", icon: "moon", selected: themeRaw == "dark") { themeRaw = "dark" }
            }
        }
        .padding(.horizontal, 24).padding(.vertical, 15)
    }

    /// アクセントカラー（無料）。ドット群でプレビュー、タップで即反映。
    private var accentRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 14) {
                S8Icon(name: "palette", size: 20, color: c.fg2)
                Text("アクセントカラー").font(S8Font.jp(15)).foregroundColor(c.fg1)
                Spacer()
                Text(currentAccent.name).font(S8Font.jp(13)).foregroundColor(c.fg3)
            }
            HStack(spacing: 10) {
                ForEach(S8Accent.allCases) { a in
                    let on = a.rawValue == accentRaw
                    Button {
                        S8Palette.currentAccent = a
                        accentRaw = a.rawValue
                    } label: {
                        ZStack {
                            Circle().fill(a.color)
                            if on {
                                Circle().stroke(c.fg1, lineWidth: 2).padding(-3)
                                S8Icon(name: "check", size: 13, color: .white)
                            }
                        }
                        .frame(width: 30, height: 30)
                        .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
        }
        .padding(.horizontal, 24).padding(.vertical, 15)
    }

}

// MARK: - プロフィール編集シート
//
// 新規追加 or 既存編集を 1 つのシートで扱う。フィールド=名前、アイコン=SFSymbol グリッド、
// フッターに削除ボタン（既存編集時のみ）。削除時はデフォルト 2 件でも制限なし。

private struct ProfileEditSheet: View {
    let profile: Profile?
    let isNew: Bool
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    private var c: S8Palette { S8Palette.of(scheme) }

    @State private var name: String = ""
    @State private var iconName: String = "person"
    @State private var showDeleteConfirm: Bool = false
    @State private var showCapAlert: Bool = false

    private let iconColumns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 6)

    var body: some View {
        let c = self.c
        VStack(spacing: 0) {
            S8TopBar(isNew ? "プロフィール追加" : "プロフィール編集", sub: isNew ? "new profile" : "edit · \(profile?.name ?? "")") {
                HStack(spacing: 6) {
                    S8IconButton(icon: "x") { dismiss() }
                    S8IconButton(icon: "check", accent: canSave, action: save)
                        .disabled(!canSave)
                }
            }
            S8Rule()
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    S8SectionLabel(text: "名前")
                    S8Field(placeholder: "例: 個人 / 仕事 / 副業", text: $name)
                        .padding(.horizontal, 24)

                    S8SectionLabel(text: "アイコン")
                    LazyVGrid(columns: iconColumns, spacing: 10) {
                        ForEach(ShopManager.shared.availableIcons, id: \.self) { sym in
                            let isSelected = iconName == sym
                            Button(action: { iconName = sym }) {
                                Image(systemName: sym)
                                    .font(.system(size: 20))
                                    .foregroundStyle(isSelected ? c.onAccent : c.fg1)
                                    .frame(width: 40, height: 40)
                                    .background(
                                        RoundedRectangle(cornerRadius: S8Radius.md)
                                            .fill(isSelected ? c.accent : c.surface)
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: S8Radius.md)
                                            .stroke(isSelected ? c.accent : c.lineStrong, lineWidth: 1)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 24)

                    if !isNew {
                        S8SectionLabel(text: "その他")
                        S8Button("プロフィールを削除", icon: "trash", variant: .secondary) {
                            showDeleteConfirm = true
                        }
                        .padding(.horizontal, 24)
                    }
                    Color.clear.frame(height: 32)
                }
            }
        }
        .background(c.paper.ignoresSafeArea())
        .onAppear {
            if let p = profile {
                name = p.name
                iconName = p.iconName
            }
        }
        .alert("このプロフィールを削除しますか？", isPresented: $showDeleteConfirm) {
            Button("削除", role: .destructive) { delete() }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("紐付いているタスクはプロフィール未設定になります")
        }
        .alert("上限に達しています", isPresented: $showCapAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("プロフィール上限は \(ShopManager.shared.profileCap) 個です。ショップで枠を追加できます。")
        }
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        if isNew {
            // 新規追加は cap チェック。既存の編集は cap 無関係。
            let existing = (try? context.fetch(FetchDescriptor<Profile>())) ?? []
            guard existing.count < ShopManager.shared.profileCap else {
                showCapAlert = true
                return
            }
            let new = Profile(name: trimmed, iconName: iconName)
            context.insert(new)
        } else if let p = profile {
            p.name = trimmed
            p.iconName = iconName
        }
        try? context.save()
        dismiss()
    }

    private func delete() {
        guard let p = profile else { return }
        context.delete(p)
        try? context.save()
        dismiss()
    }
}
