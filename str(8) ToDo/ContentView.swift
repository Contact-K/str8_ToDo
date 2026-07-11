//
//  ContentView.swift
//  str8ToDo
//
//  5本柱のタブバー：カレンダー・タイマー・リスト・承認・Study Hub。
//  P0 ではカレンダーのみ実装。残りはプレースホルダ。
//

import SwiftUI
import SwiftData

enum AppTab: Hashable {
    case calendar, timer, list, approval, studyHub
}

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Query private var allTasks: [TaskItem]
    /// 仕分けデッキを完走した日（dayKey）。スタンプは SortDeckView が完走時に押す。
    @AppStorage("lastSortPromptDay") private var lastSortPromptDay = 0
    @State private var showMorningDeck = false
    @State private var showWeekReview = false
    @State private var selectedTab: AppTab = .calendar

    /// ponytail: stats 側の控えめ表示+導線はこのタブバッジで満たす。
    private var pendingCount: Int {
        allTasks.filter { $0.status == .done }.count
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("カレンダー", systemImage: "calendar", value: .calendar) {
                CalendarRootView()
            }
            Tab("タイマー", systemImage: "hourglass", value: .timer) {
                TimerView()
            }
            Tab("リスト", systemImage: "checklist", value: .list) {
                TodoListView()
            }
            Tab("承認", systemImage: "checkmark.seal", value: .approval) {
                ApprovalQueueView(showWeekReview: $showWeekReview)
            }
            .badge(pendingCount)
            Tab("Study Hub", systemImage: "books.vertical", value: .studyHub) {
                StudyHubView()
            }
        }
        .onAppear {
            // コールドスタート競合対策：delegate が起動時にタップを検出済みなら拾う（H6）
            if NotificationService.pendingWeeklyReviewTap {
                showWeekReview = true
                NotificationService.pendingWeeklyReviewTap = false
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
        // 週次締め通知タップ→WeekReviewView 自動遷移（NotificationDelegate 経由）
        .onReceive(NotificationCenter.default.publisher(for: NotificationService.weeklyReviewTappedNotification)) { _ in
            showWeekReview = true
        }
        // 集中ルーム終了「承認へ進む」→ 承認タブへ直行（P14 debate-review #11）
        .onReceive(NotificationCenter.default.publisher(for: FocusRoomView.proceedToApprovalNotification)) { _ in
            selectedTab = .approval
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
