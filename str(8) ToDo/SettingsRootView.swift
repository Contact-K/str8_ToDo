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
    @AppStorage(AppSettingsKey.timerPreset1) private var timerPreset1 = AppSettingsKey.timerPreset1Default
    @AppStorage(AppSettingsKey.timerPreset2) private var timerPreset2 = AppSettingsKey.timerPreset2Default
    @AppStorage(AppSettingsKey.timerPreset3) private var timerPreset3 = AppSettingsKey.timerPreset3Default
    @AppStorage("s8_accent") private var accentRaw = S8Accent.anzu.rawValue
    /// "system" / "light" / "dark"（アプリレベルのテーマ）
    @AppStorage("s8_theme") private var themeRaw: String = "system"

    @State private var eventKit = EventKitService()
    @State private var showBandTemplates = false
    @State private var showDictionary = false
    @State private var showAdvancedSettings = false

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

                    // MARK: - タイマー
                    S8SectionLabel(text: "タイマープリセット")
                    presetRow(index: 1, minutes: $timerPreset1)
                    S8Rule()
                    presetRow(index: 2, minutes: $timerPreset2)
                    S8Rule()
                    presetRow(index: 3, minutes: $timerPreset3)

                    // MARK: - 入力
                    S8SectionLabel(text: "入力の設定")
                    S8SetRow(icon: "text-cursor", label: "サジェスト機能を有効化") {
                        S8Toggle(on: enableDictionarySuggestions) { enableDictionarySuggestions.toggle() }
                    }
                    S8Rule()
                    S8SetRow(icon: "bookmark", label: "辞書管理", trailing: {
                        S8Icon(name: "chevron-right", size: 16, color: c.fg3)
                    }, onTap: { showDictionary = true })

                    // MARK: - マイ時間割
                    S8SectionLabel(text: "マイ時間割")
                    S8SetRow(icon: "list", label: "枠テンプレートを編集", trailing: {
                        S8Icon(name: "chevron-right", size: 16, color: c.fg3)
                    }, onTap: { showBandTemplates = true })

                    // MARK: - 詳細
                    S8SectionLabel(text: "詳細")
                    S8SetRow(icon: "settings", label: "カレンダー詳細設定・バックアップ", trailing: {
                        S8Icon(name: "chevron-right", size: 16, color: c.fg3)
                    }, onTap: { showAdvancedSettings = true })

                    Color.clear.frame(height: 32)
                }
            }
        }
        .background(c.paper.ignoresSafeArea())
        .sheet(isPresented: $showBandTemplates) {
            NavigationStack { CalendarSettingsView() }
        }
        .sheet(isPresented: $showDictionary) {
            NavigationStack { DictionarySettingsView() }
        }
        .sheet(isPresented: $showAdvancedSettings) {
            NavigationStack { CalendarSettingsView() }
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

    private func presetRow(index: Int, minutes: Binding<Int>) -> some View {
        HStack(spacing: 14) {
            S8Icon(name: "hourglass", size: 20, color: c.fg2)
            Text("プリセット\(index)").font(S8Font.jp(15)).foregroundColor(c.fg1)
            Spacer()
            Text("\(minutes.wrappedValue)分")
                .font(S8Font.mono(14, .bold))
                .foregroundColor(c.fg1)
            Stepper("", value: minutes, in: 1...180, step: 1).labelsHidden()
        }
        .padding(.horizontal, 24).padding(.vertical, 15)
    }
}
