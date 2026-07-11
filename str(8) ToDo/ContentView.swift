//
//  ContentView.swift
//  str8ToDo
//
//  5本柱のタブバー：カレンダー・タイマー・リスト・承認・Study Hub。
//  P0 ではカレンダーのみ実装。残りはプレースホルダ。
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Query private var allTasks: [TaskItem]
    /// 仕分けデッキを完走した日（dayKey）。スタンプは SortDeckView が完走時に押す。
    @AppStorage("lastSortPromptDay") private var lastSortPromptDay = 0
    @State private var showMorningDeck = false
    @State private var showWeekReview = false

    /// ponytail: stats 側の控えめ表示+導線はこのタブバッジで満たす。
    private var pendingCount: Int {
        allTasks.filter { $0.status == .done }.count
    }

    var body: some View {
        TabView {
            Tab("カレンダー", systemImage: "calendar") {
                CalendarRootView()
            }
            Tab("タイマー", systemImage: "hourglass") {
                TimerView()
            }
            Tab("リスト", systemImage: "checklist") {
                TodoListView()
            }
            Tab("承認", systemImage: "checkmark.seal") {
                ApprovalQueueView(showWeekReview: $showWeekReview)
            }
            .badge(pendingCount)
            Tab("Study Hub", systemImage: "books.vertical") {
                StudyHubView()
            }
        }
        .onChange(of: scenePhase) {
            guard scenePhase == .active else { return }
            // 未完走ならスタンプされないので、次のフォアグラウンドで残りを自動再提示する
            if lastSortPromptDay != dayKey(.now), !SortDeckEngine.deckTasks(from: allTasks).isEmpty {
                showMorningDeck = true
            }
        }
        .sheet(isPresented: $showMorningDeck) {
            SortDeckView(tasks: allTasks)
        }
        .sheet(isPresented: $showWeekReview) {
            WeekReviewView()
        }
    }
}

/// 未実装タブの共通プレースホルダ。
struct ComingSoonView: View {
    let title: String
    let detail: String

    var body: some View {
        NavigationStack {
            ContentUnavailableView {
                Label(title, systemImage: "wrench.and.screwdriver")
            } description: {
                Text(detail)
            }
            .navigationTitle(title)
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(PreviewData.container)
}
