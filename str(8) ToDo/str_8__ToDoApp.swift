//
//  str_8__ToDoApp.swift
//  str(8) ToDo
//
//  Created by Konno Takuto on 2026/06/19.
//

import SwiftUI
import SwiftData
import Combine
import UserNotifications

@main
struct str_8__ToDoApp: App {

    /// アプリ全体で共有する SwiftData コンテナ。
    /// オフライン主義のため CloudKit 同期は使わず、端末内ローカルストアのみ。
    let modelContainer: ModelContainer

    init() {
        do {
            let schema = Schema([
                TaskItem.self,
                Category.self,
                PlaceTag.self,
                DayStat.self,
                MonthMoneyStat.self,
                Band.self,
                BandTemplate.self,
                BandAssignment.self,
                FocusSession.self,
                Subject.self,
                Profile.self,
                PhraseAlias.self
            ])
            let configuration = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: false,
                cloudKitDatabase: .none
            )
            modelContainer = try ModelContainer(for: schema, configurations: configuration)

            // UserDefaults に既定値を登録（?? フォールバックを個々の読み出し側に書かない）
            AppSettingsKey.registerDefaults()

            // 通知タップ→WeekReviewView 遷移のための delegate（週次締め通知の identifier だけ拾う）
            UNUserNotificationCenter.current().delegate = NotificationService.delegate

            // 週次締めリマインダーを起動時に予約（enableNotifications OFF なら解除）
            let d = UserDefaults.standard
            let enabled = d.bool(forKey: AppSettingsKey.enableNotifications)
            if enabled {
                let w = d.integer(forKey: AppSettingsKey.weekReviewWeekday)
                let h = d.integer(forKey: AppSettingsKey.weekReviewHour)
                NotificationService.scheduleWeeklyReview(weekday: w, hour: h)
            } else {
                NotificationService.cancelWeeklyReview()
            }
        } catch {
            fatalError("ModelContainer の初期化に失敗しました: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView(modelContainer: modelContainer)
        }
        .modelContainer(modelContainer)
    }
}

// MARK: - Root View with ScenePhase Monitoring

private struct RootView: View {
    let modelContainer: ModelContainer
    @Environment(\.scenePhase) var scenePhase

    var body: some View {
        ContentView()
            .task {
                BandTemplate.seedDefaultIfNeeded(modelContainer.mainContext)
                seedPhraseAliasesIfNeeded(modelContainer.mainContext)
                seedProfilesIfNeeded(modelContainer.mainContext)
                // seed 後の初回 refresh
                WidgetSnapshotService.refresh(modelContainer.mainContext)
                // 起動時に通知権限を要求
                _ = await NotificationService.requestAuthorization()
                // 日の出日の入り(SunCalc)/出発逆算(DepartureService)用の現在地キャッシュ更新
                // （天気機能廃止に伴い旧天気取得プロバイダから移設。天気自体はこの2機能とは無関係）
                await LastKnownLocation.refresh()
            }
            .onChange(of: scenePhase) { _, newPhase in
                switch newPhase {
                case .active, .background:
                    WidgetSnapshotService.refresh(modelContainer.mainContext)
                case .inactive:
                    break
                @unknown default:
                    break
                }
            }
            .onReceive(
                NotificationCenter.default.publisher(for: ModelContext.didSave)
                    .debounce(for: .seconds(2), scheduler: RunLoop.main)
            ) { _ in
                WidgetSnapshotService.refresh(modelContainer.mainContext)
            }
    }
}

/// 辞書の既定表現シード（企画書 E3 / P17）。初回起動時のみ、PhraseAlias が1件も無ければ挿入する。
@MainActor
private func seedPhraseAliasesIfNeeded(_ context: ModelContext) {
    var descriptor = FetchDescriptor<PhraseAlias>()
    descriptor.fetchLimit = 1
    guard ((try? context.fetch(descriptor)) ?? []).isEmpty else { return }

    let seeds: [(keyword: String, category: WHCategory, replacement: String)] = [
        ("ポモ", .how, "25 分"),
        ("今日", .when, "今日 09:00"),
        ("明日", .when, "明日 09:00"),
        ("朝", .when, "09:00"),
        ("昼", .when, "12:00"),
        ("夕方", .when, "17:00"),
        ("夜", .when, "20:00"),
        ("大学", .where_, "大学図書館"),
        ("会社", .where_, "オフィス"),
        ("買い物", .where_, "スーパー"),
        ("レポート", .what, "レポート作成"),
        ("散歩", .what, "散歩 30 分"),
        ("打ち合わせ", .what, "打ち合わせ 60 分"),
        ("30 分", .how, "30 分"),
        ("1 時間", .how, "60 分")
    ]
    // H3: keyword の一意性維持（シード内重複は先勝ちで skip）。
    var existingKeywords: Set<String> = []
    for seed in seeds {
        guard existingKeywords.insert(seed.keyword).inserted else { continue }
        context.insert(PhraseAlias(keyword: seed.keyword, whCategory: seed.category, replacement: seed.replacement, isBuiltIn: true))
    }
    try? context.save()
}

/// Profile の既定シード（対称性。企画書 which=会社/個人の最小セット）。初回起動時のみ、Profile が1件も無ければ挿入する。
@MainActor
private func seedProfilesIfNeeded(_ context: ModelContext) {
    var descriptor = FetchDescriptor<Profile>()
    descriptor.fetchLimit = 1
    guard ((try? context.fetch(descriptor)) ?? []).isEmpty else { return }

    context.insert(Profile(name: "個人", iconName: "person"))
    context.insert(Profile(name: "仕事", iconName: "briefcase"))
    try? context.save()
}
