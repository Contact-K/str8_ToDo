//
//  str_8__ToDoApp.swift
//  str(8) ToDo
//
//  Created by Konno Takuto on 2026/06/19.
//

import SwiftUI
import SwiftData

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
            ContentView()
                .task { BandTemplate.seedDefaultIfNeeded(modelContainer.mainContext) }
        }
        .modelContainer(modelContainer)
    }
}
