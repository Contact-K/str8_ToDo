//
//  ContentView.swift
//  str8ToDo
//
//  5本柱のタブ（カレンダー・タイマー・リスト・承認・勉強）を S8ClickWheel で切り替える。
//  P2P（peers/connected）は MPC 集中ルーム経由の情報になる想定だが、FocusRoomView 側の
//  接続をまだホイールへ引き上げていないので当面 0 / false 固定（ponytail: 後で繋ぐ）。
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var scheme
    @Query private var allTasks: [TaskItem]
    /// 仕分けデッキを完走した日（dayKey）。スタンプは SortDeckView が完走時に押す。
    @AppStorage("lastSortPromptDay") private var lastSortPromptDay = 0
    @State private var showMorningDeck = false
    @State private var showWeekReview = false
    @State private var tabIndex = 0
    @State private var minimized = false

    var body: some View {
        let c = S8Palette.of(scheme)
        GeometryReader { geo in
            let bottomSafe = geo.safeAreaInsets.bottom
            ZStack(alignment: .bottom) {
                c.paper.ignoresSafeArea()

                Group {
                    switch tabIndex {
                    case 0: CalendarRootView()
                    case 1: TimerView()
                    case 2: TodoListView()
                    case 3: ApprovalQueueView(showWeekReview: $showWeekReview)
                    default: StudyHubView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                // ホイール帯：左右の余白・ホイール外側を下スワイプで折りたたむ（参照 S8Root 踏襲）。
                if !minimized {
                    Color.clear
                        .frame(maxWidth: .infinity)
                        .frame(height: 190)
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 24)
                                .onEnded { g in
                                    if g.translation.height > 36, g.translation.height > abs(g.translation.width) {
                                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                        withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) { minimized = true }
                                    }
                                }
                        )
                }

                S8ClickWheel(
                    tabIndex: $tabIndex,
                    minimized: $minimized,
                    peers: 0,
                    connected: false,
                    quality: 0,
                    bottomSafe: bottomSafe,
                    onToggleConn: {}
                )
                .padding(.bottom, minimized ? 8 + bottomSafe : 0)
            }
            .ignoresSafeArea(.container, edges: .bottom)
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
            tabIndex = 3
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
