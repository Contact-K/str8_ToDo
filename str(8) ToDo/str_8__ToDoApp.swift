//
//  str_8__ToDoApp.swift
//  str(8) ToDo
//
//  Created by Konno Takuto on 2026/06/19.
//

import SwiftUI
import SwiftData
import Combine

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
                WeatherCache.self
            ])
            let configuration = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: false,
                cloudKitDatabase: .none
            )
            modelContainer = try ModelContainer(for: schema, configurations: configuration)
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
                // seed 後の初回 refresh
                await WidgetSnapshotService.refresh(modelContainer.mainContext)
            }
            .onChange(of: scenePhase) { _, newPhase in
                switch newPhase {
                case .active, .background:
                    Task {
                        await WidgetSnapshotService.refresh(modelContainer.mainContext)
                    }
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
