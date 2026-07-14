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
    // Handoff 00c: タブ別センターコアが操作する共有モード（子ビューは @AppStorage で購読）。
    @AppStorage("wheel.cal.mode") private var calMode = 0        // 0=月 1=週 2=日 3=年
    @AppStorage("wheel.timer.preset") private var timerPreset = 0 // 0=preset1 1=preset2 2=preset3
    @AppStorage("wheel.study.view") private var studyView = 0     // 0=サマリ 1=詳細
    // タイマープリセット（ユーザーカスタマイズ）
    @AppStorage(AppSettingsKey.timerPreset1) private var preset1 = AppSettingsKey.timerPreset1Default
    @AppStorage(AppSettingsKey.timerPreset2) private var preset2 = AppSettingsKey.timerPreset2Default
    @AppStorage(AppSettingsKey.timerPreset3) private var preset3 = AppSettingsKey.timerPreset3Default
    // Handoff 00c 改: モードホイールの開閉状態と一時選択。
    @State private var modeWheelOpen = false
    @State private var modeWheelSelection = 0

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
                    case 4: StudyHubView()
                    default: SettingsRootView()   // 5: 設定
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

                if modeWheelOpen, let cfg = makeCenterCore(), !cfg.options.isEmpty {
                    // Handoff 00c: モードホイール開閉時は S8FilterWheel を出す。
                    S8FilterWheel(
                        items: cfg.options,
                        selectedIndex: $modeWheelSelection,
                        onClose: {
                            cfg.onSelect(modeWheelSelection)
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                                modeWheelOpen = false
                            }
                        },
                        bottomSafe: bottomSafe
                    )
                    .padding(.bottom, bottomSafe > 0 ? 0 : 0)
                } else {
                    S8ClickWheel(
                        tabIndex: $tabIndex,
                        minimized: $minimized,
                        peers: 0,
                        connected: false,
                        quality: 0,
                        bottomSafe: bottomSafe,
                        centerCore: makeCenterCore(),
                        onOpenModeWheel: {
                            guard let cfg = makeCenterCore(), !cfg.options.isEmpty else { return }
                            modeWheelSelection = cfg.selectedIndex
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                                modeWheelOpen = true
                            }
                        },
                        onToggleConn: {}
                    )
                    .padding(.bottom, minimized ? 8 + bottomSafe : 0)
                }
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

    /// Handoff 00c 改: タブに応じたセンターコア設定。
    /// 長押しは全タブ共通で P2P トグル。タップで options を持つモードホイールを開く。
    /// options 空 → タップ無効（承認/設定タブ）。
    private func makeCenterCore() -> S8CenterCoreConfig? {
        switch tabIndex {
        case 0: // Calendar → MODE（月/週/日/年）
            let modes = ["月", "週", "日", "年"]
            let icons = ["calendar", "list", "circle-dot", "bar-chart"]
            let idx = max(0, min(modes.count - 1, calMode))
            return .init(
                cap: "MODE",
                main: modes[idx],
                sub: nil,
                pips: modes.indices.map { $0 == idx },
                options: zip(modes, icons).enumerated().map { i, pair in
                    S8WheelFilterItem(id: "mode-\(i)", icon: pair.1, label: pair.0)
                },
                selectedIndex: idx,
                onSelect: { calMode = $0 }
            )
        case 1: // Timer → PRESET（ユーザーカスタマイズ可能）
            let presets = [preset1, preset2, preset3].map { "\($0)′" }
            let idx = max(0, min(presets.count - 1, timerPreset))
            return .init(
                cap: "PRESET",
                main: presets[idx],
                sub: nil,
                pips: presets.indices.map { $0 == idx },
                options: presets.enumerated().map { i, s in
                    S8WheelFilterItem(id: "pre-\(i)", icon: "hourglass", label: s)
                },
                selectedIndex: idx,
                onSelect: { timerPreset = $0 }
            )
        case 2: // List → FILTER（options 空でホイール未対応。フィルタは既存の TodoList 内 Menu）
            return .init(cap: "FILTER", main: "すべて", sub: "科目", pips: [],
                         options: [], selectedIndex: 0, onSelect: { _ in })
        case 3: // Approve → P2P（nil で既存 P2P LINK 表示）
            return nil
        case 4: // Study → 科目追加ボタン（直接アクション、モードホイール開閉なし）
            return .init(
                cap: "ADD",
                main: "＋科目",
                sub: "追加",
                pips: [],
                options: [],
                selectedIndex: 0,
                onSelect: { _ in },
                directAction: {
                    NotificationCenter.default.post(name: .s8StudyAddSubject, object: nil)
                }
            )
        case 5: // Settings → 特に切替なし（P2P コア）
            return nil
        default:
            return nil
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
