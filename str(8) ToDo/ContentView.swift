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
    // 手動時間（0=未設定）。長押し Crown で書き込まれる。プリセットを破壊せず独立して保持。
    @AppStorage("timer.manualMinutes") private var timerManualMinutes = 0
    // Handoff 00c 改: モードホイールの開閉状態と一時選択。
    @State private var modeWheelOpen = false
    @State private var modeWheelSelection = 0

    // アクセントカラー同期用：@AppStorage を購読して body 再実行を発火、`S8Palette.currentAccent` に書戻す。
    // これでコールドスタート同期 + ライブ変更時の全タブ再描画を同時に解決（両問題の元手 1 行）。
    @AppStorage("s8_accent") private var accentRaw = S8Accent.anzu.rawValue

    // P2P セッション：承認タブ・設定タブ（中心 P2P コア）・ホイール中心の共有状態源。
    // 以前は ApprovalQueueView の @State に閉じており、他タブから状態が見えなかった。
    @State private var peerSession = PeerSession()

    // ホイール差替オーバレイの共有提示器。MorphCalendar のフィルタなど子から present される。
    @State private var wheelPresenter = S8WheelOverlayPresenter.shared

    // タブ遷移方式（true=ホイール / false=タブバー）。設定タブから切替。Talk 移植。
    @AppStorage(AppSettingsKey.navWheel) private var navWheel = AppSettingsKey.navWheelDefault

    var body: some View {
        // 起動直後・アクセント変更直後の両方でグローバル状態を最新に。副作用を let に閉じ込めて
        // ViewBuilder で void を返さないようにする（body の先頭に if 文を直書きすると型検査失敗）。
        let _: Void = {
            if let a = S8Accent(rawValue: accentRaw), S8Palette.currentAccent != a {
                S8Palette.currentAccent = a
            }
        }()
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
                    case 3: ApprovalQueueView(showWeekReview: $showWeekReview, peerSession: peerSession)
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

                // navWheel=false ならタブバー、true ならホイール（Talk 移植の切替）。
                if !navWheel {
                    S8TabBar(tabIndex: $tabIndex)
                        .padding(.bottom, bottomSafe)
                } else if wheelPresenter.isPresented {
                    // 背景グレーアウト（ScrollView / ヘッダを暗く）
                    Color.black.opacity(0.35)
                        .ignoresSafeArea()
                        .transition(.opacity)
                        .onTapGesture { wheelPresenter.dismissWithoutCommit() }
                    switch wheelPresenter.mode {
                    case .filter:
                        S8FilterWheel(
                            items: wheelPresenter.items,
                            selectedIndex: Binding(
                                get: { wheelPresenter.selectedIndex },
                                set: { wheelPresenter.selectedIndex = $0 }
                            ),
                            onClose: { wheelPresenter.commitAndDismiss() },
                            bottomSafe: bottomSafe
                        )
                    case .crown(let range, let unit):
                        S8CrownWheel(
                            range: range,
                            value: Binding(
                                get: { wheelPresenter.selectedIndex },
                                set: { wheelPresenter.selectedIndex = $0 }
                            ),
                            unit: unit,
                            onClose: { wheelPresenter.commitAndDismiss() },
                            bottomSafe: bottomSafe
                        )
                    }
                } else if modeWheelOpen, let cfg = makeCenterCore(), !cfg.options.isEmpty {
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
                    // P2P 実値を接続（承認/設定タブ中心の p2pCoreContent 用）。
                    let live = peerSession.isConnected && peerSession.connectedPeerName != nil
                    S8ClickWheel(
                        tabIndex: $tabIndex,
                        minimized: $minimized,
                        peers: live ? 1 : 0,
                        connected: peerSession.isConnected,
                        searching: peerSession.isSearching && !peerSession.isConnected,
                        quality: peerSession.isConnected ? 3 : 0,
                        bottomSafe: bottomSafe,
                        centerCore: makeCenterCore(),
                        onOpenModeWheel: {
                            guard let cfg = makeCenterCore(), !cfg.options.isEmpty else { return }
                            modeWheelSelection = cfg.selectedIndex
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                                modeWheelOpen = true
                            }
                        },
                        onToggleConn: {
                            if peerSession.isConnected || peerSession.isSearching {
                                peerSession.stop()
                            } else {
                                peerSession.start()
                            }
                        }
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

    /// タブに応じたセンターコア設定。中心タップの挙動：
    /// - directAction あり → 直接発火（Calendar/List/Study の作成）
    /// - options 非空 → モードホイールを開く（Timer プリセット）
    /// - nil → P2P LINK ビジュアル ＋ 中心タップで接続トグル（承認/設定）
    private func makeCenterCore() -> S8CenterCoreConfig? {
        switch tabIndex {
        case 0: // Calendar → 中心タップで作成、MODE はチップ帯で切替
            return .init(
                cap: "ADD",
                main: "＋作成",
                sub: "イベント",
                pips: [],
                options: [],
                selectedIndex: 0,
                onSelect: { _ in },
                directAction: {
                    NotificationCenter.default.post(name: .s8CalAddEvent, object: nil)
                }
            )
        case 1: // Timer → PRESET（ユーザーカスタマイズ可能）
            let presets = [preset1, preset2, preset3]
            let labels = presets.map { "\($0)′" }
            let idx = max(0, min(presets.count - 1, timerPreset))
            // Handoff 2026-07-14: 中心タップ = プリセット循環（options + directAction 併用）、
            // 中心長押し = Crown ホイールを展開して分数を自由設定。
            return .init(
                cap: "PRESET",
                main: labels[idx],
                sub: nil,
                pips: presets.indices.map { $0 == idx },
                options: presets.enumerated().map { i, m in
                    S8WheelFilterItem(id: "pre-\(i)", icon: "hourglass", label: labels[i])
                },
                selectedIndex: idx,
                onSelect: { timerPreset = $0 },
                directAction: {
                    // タップで次のプリセットに循環。
                    let next = (idx + 1) % presets.count
                    timerPreset = next
                },
                longPressAction: {
                    // 長押しで Crown ホイールを展開。プリセットは書き換えず、独立の手動時間として保持する。
                    let current = timerManualMinutes > 0 ? timerManualMinutes : presets[idx]
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    S8WheelOverlayPresenter.shared.presentCrown(range: 1...180, currentValue: current) { picked in
                        timerManualMinutes = picked
                    }
                }
            )
        case 2: // List → 中心タップでタスク作成
            return .init(
                cap: "ADD",
                main: "＋作成",
                sub: "タスク",
                pips: [],
                options: [],
                selectedIndex: 0,
                onSelect: { _ in },
                directAction: {
                    NotificationCenter.default.post(name: .s8ListAddTask, object: nil)
                }
            )
        case 3: // Approve → P2P（nil で既存 P2P LINK 表示・中心タップで接続トグル）
            return nil
        case 4: // Study → 科目追加ボタン（直接アクション）
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
