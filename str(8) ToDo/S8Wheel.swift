// S8Wheel.swift — iPod 風クリックホイールナビ（iOS 既定）+ タブバー版。wheel.jsx / talk.css の SwiftUI 実装。
//   ドラッグで回転 · アイコンをタップでスナップ · 中心 = P2P ステータス · 折りたたみで最小化。

import SwiftUI

// MARK: - タブ定義（共通）

struct S8TabDef: Identifiable {
    let id: String
    let icon: String
    let label: String
}

let s8Tabs: [S8TabDef] = [
    .init(id: "cal", icon: "calendar", label: "カレンダー"),
    .init(id: "timer", icon: "hourglass", label: "タイマー"),
    .init(id: "list", icon: "list", label: "リスト"),
    .init(id: "approve", icon: "check-circle", label: "承認"),
    .init(id: "study", icon: "book-open", label: "勉強"),
    .init(id: "settings", icon: "settings", label: "設定"),
]

// MARK: - 触覚フィードバック

private enum S8WheelHaptic {
    /// 選択が次の項目へ移った瞬間の軽いコツッ
    static func tick() { UISelectionFeedbackGenerator().selectionChanged() }
    /// スナップ確定・タップ時の軽い衝撃
    static func tap() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
}

// MARK: - クリックホイール

/// Handoff 00c: タブ別センターコアの表示・タップ動作設定。
/// 長押しは S8ClickWheel 側で常に P2P トグルに固定。nil で既存 P2P コア表示。
///
/// タップは「モードホイール」を開く。ホイールを回して該当モードを選ぶ流儀
/// （str(8)_Talk のフィルタ機能と同じ操作感）。options.isEmpty のときはタップ無効。
struct S8CenterCoreConfig {
    let cap: String                            // "MODE" / "PRESET" / "FILTER" / "VIEW"
    let main: String                           // 現在選択の主表示
    let sub: String?                           // 補助テキスト（pips 非表示時）
    let pips: [Bool]                           // pip インジケータ（現在位置ハイライト）
    let options: [S8WheelFilterItem]           // モードホイールの選択肢（icon+label）
    let selectedIndex: Int                     // 現在の options index
    let onSelect: (Int) -> Void                // モード確定時のコールバック
    /// 非 nil のとき、タップでモードホイールを開かず直接発火する（勉強タブの「科目追加」等）。
    var directAction: (() -> Void)? = nil
    /// 非 nil のとき、中心コアを長押しした際に発火する。Timer タブの Crown ホイール展開に使用。
    /// 全タブ共通の長押しは廃止済（旧 P2P 廃止 2026-07-11）なので、タブ固有機能への割当のみ。
    var longPressAction: (() -> Void)? = nil
}

struct S8ClickWheel: View {
    @Binding var tabIndex: Int
    @Binding var minimized: Bool
    let peers: Int
    let connected: Bool
    /// start() 後 peer 接続待ちの探索状態。center 表示で「反応してる」を可視化するため。
    var searching: Bool = false
    /// 通信強度 0〜3（バー表示用。人数とは独立・項目 R2-③）。
    var quality: Int = 0
    /// 画面下端のセーフエリア量（ホームインジケータ帯）。表示はここまで埋め、当たり判定はこの帯を除外する。
    var bottomSafe: CGFloat = 0
    /// Handoff 00c: タブ別コア設定（nil で既存 P2P コア）。
    var centerCore: S8CenterCoreConfig? = nil
    /// Handoff 00c 改: 中心タップで開く「モードホイール」を要求（options 非空時のみ）。
    var onOpenModeWheel: () -> Void = {}
    let onToggleConn: () -> Void

    private let D: CGFloat = 280
    private let R: CGFloat = 92
    private var N: Int { s8Tabs.count }
    private var STEP: Double { 360.0 / Double(N) }

    @State private var rot: Double = 0
    @State private var dragging = false
    @State private var lastAngle: Double? = nil
    @State private var didRotate = false
    /// ノードごとの SF Symbol バウンス用カウンタ。選択された瞬間だけ増やす＝移動先のみ弾む。
    @State private var bump = [Int](repeating: 0, count: s8Tabs.count)

    /// 下端ドックの半ドームの可視高さ（円の下側を画面下端に埋める）。
    /// 0.67→0.72 に緩め、中心コアの下端（y=182）に 20px の余白を確保して見切れ回避。
    private var domeH: CGFloat { D * 0.72 }

    @Environment(\.colorScheme) private var scheme

    private func norm(_ a: Double) -> Double { let m = a.truncatingRemainder(dividingBy: 360); return m < 0 ? m + 360 : m }

    private func selOf(_ r: Double) -> Int {
        var best = 0, bd = 1e9
        for i in 0..<N {
            let a = norm(Double(i) * STEP - 90 + r)
            var d = abs(a - 270); d = min(d, 360 - d)
            if d < bd { bd = d; best = i }
        }
        return best
    }

    private func snap(to i: Int) {
        S8WheelHaptic.tap()
        let target = -Double(i) * STEP
        let k = ((rot - target) / 360).rounded()
        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
            rot = target + k * 360
        }
        if tabIndex != i { tabIndex = i }
    }

    private func syncRot() {
        guard !dragging else { return }
        let target = -Double(tabIndex) * STEP
        let k = ((rot - target) / 360).rounded()
        rot = target + k * 360
    }

    var body: some View {
        let c = S8Palette.of(scheme)
        if minimized {
            minimizedCapsule(c)
                .transition(.scale(scale: 0.85, anchor: .bottom).combined(with: .opacity))
        } else {
            // 折りたたみ矢印は廃止。折りたたみは「ホイール外側・左右の余白を下スワイプ」で行う（S8Root 側）。
            // 折りたたみ時は下端へ畳まれるように縮小＋フェードのトランジション。
            wheel(c)
                .transition(.scale(scale: 0.4, anchor: .bottom).combined(with: .opacity))
                .onAppear { syncRot() }
                .onChange(of: tabIndex) { _, new in
                    syncRot()
                    if bump.indices.contains(new) { bump[new] += 1 }   // 移動先のみバウンス
                }
        }
    }

    private func wheel(_ c: S8Palette) -> some View {
        let sel = selOf(rot)
        // 下端ドックの半ドーム：円の下側は意図的に画面下端へ埋める（＝下の見切れは仕様）。
        // 表示領域 D×domeH に円(D×D)を上揃えで重ね、下側だけはみ出させて clip する。
        let hitH = max(1, domeH - bottomSafe)
        return Color.clear
            .frame(width: D, height: domeH)
            .overlay(alignment: .top) {
                ZStack(alignment: .top) {
                    // 見た目（リング・ゲージ・インジケータ・ノード）は全て非インタラクティブ。
                    Group {
                        // rim
                        Circle().fill(c.surface).overlay(Circle().stroke(c.lineStrong, lineWidth: 1))
                        Circle().inset(by: 18).stroke(c.line, lineWidth: 1)

                        // ticks（固定ゲージ）
                        ForEach(0..<24, id: \.self) { i in
                            Rectangle().fill(c.line)
                                .frame(width: 1, height: i % 3 == 0 ? 11 : 7)
                                .frame(width: D, height: D, alignment: .top)
                                .padding(.top, 5)
                                .rotationEffect(.degrees(Double(i) * 15))
                        }

                        // 上端インジケータ
                        Rectangle().fill(c.accent)
                            .frame(width: 3, height: 9)
                            .frame(width: D, height: D, alignment: .top)
                            .padding(.top, 3)

                        // orbit nodes（表示専用）
                        ForEach(Array(s8Tabs.enumerated()), id: \.element.id) { i, t in
                            let a = (Double(i) * STEP - 90 + rot) * .pi / 180
                            let x = D / 2 + R * cos(a)
                            let y = D / 2 + R * sin(a)
                            VStack(spacing: 2) {
                                S8Icon(name: t.icon, size: 20, color: i == sel ? c.accent : c.fg2)
                                    .symbolVariant(i == sel ? .fill : .none)   // 選択中はフィル／非選択は縁
                                    .symbolEffect(.bounce, value: bump[i])     // 移動先のみ弾む
                                Text(t.label).font(S8Font.jp(10, i == sel ? .bold : .medium))
                                    .foregroundColor(i == sel ? c.accent : c.fg3)
                            }
                            .frame(width: 52, height: 46)
                            .position(x: x, y: y)
                        }
                    }
                    .allowsHitTesting(false)

                    // 回転＋選択を一手に引き受ける静止ドラッグ面。下端 bottomSafe は clip で判定から除外。
                    Color.clear
                        .frame(width: D, height: D)
                        .contentShape(Circle())
                        .gesture(wheelDrag)
                        .frame(width: D, height: hitH, alignment: .top)
                        .clipped()

                    // center core = P2P：長押しで接続トグル。インジケータは通信品質3状態＋強度バー。
                    centerCore(c)
                        .position(x: D / 2, y: D / 2)
                }
                .frame(width: D, height: D)
            }
            .clipped()
    }

    /// 指追従の角度ドラッグ＋タップ選択を1つのジェスチャで処理する。
    /// 静止面に付けるので、回転でノードが動いても当たり判定が崩れない。
    private var wheelDrag: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { g in
                let dx = Double(g.location.x) - Double(D) / 2
                let dy = Double(g.location.y) - Double(D) / 2
                let r = (dx * dx + dy * dy).squareRoot()
                let cur = atan2(dy, dx) * 180 / .pi
                let moved = (Double(g.translation.width) * Double(g.translation.width)
                           + Double(g.translation.height) * Double(g.translation.height)).squareRoot()
                // 6px 超えで「回転」に確定。確定の瞬間に基準角をリセットして初動の飛びを防ぐ
                if !didRotate && moved > 6 {
                    didRotate = true
                    dragging = true
                    lastAngle = cur
                }
                // 中心付近は角度が暴れるので回転に反映しない
                if didRotate, let prev = lastAngle, r > 24 {
                    var d = cur - prev
                    if d > 180 { d -= 360 } else if d < -180 { d += 360 }
                    rot += d
                    lastAngle = cur
                    let s = selOf(rot)
                    if s != tabIndex { tabIndex = s; S8WheelHaptic.tick() }
                }
            }
            .onEnded { g in
                let rotated = didRotate
                didRotate = false
                dragging = false
                lastAngle = nil
                if rotated {
                    snap(to: selOf(rot))
                } else {
                    // タップ：押した方向に最も近いノードを選択（中心ちょうどは無視）
                    let dx = Double(g.startLocation.x) - Double(D) / 2
                    let dy = Double(g.startLocation.y) - Double(D) / 2
                    if (dx * dx + dy * dy).squareRoot() > 24 {
                        snap(to: nearestNode(toAngle: atan2(dy, dx) * 180 / .pi))
                    }
                }
            }
    }

    /// 与えた方向（度）に画面上もっとも近いノードの index。タップ選択用。
    private func nearestNode(toAngle ang: Double) -> Int {
        var best = 0, bd = 1e9
        for i in 0..<N {
            let na = norm(Double(i) * STEP - 90 + rot)
            var diff = abs(norm(ang) - na)
            diff = min(diff, 360 - diff)
            if diff < bd { bd = diff; best = i }
        }
        return best
    }

    /// 中心コア：タップで cfg.directAction / モードホイール展開 / P2P トグル（承認タブなど centerCore==nil のとき）。
    /// 長押し P2P は廃止。承認タブは centerCore==nil を返して、その中心タップで P2P を切替える。
    private func centerCore(_ c: S8Palette) -> some View {
        ZStack {
            Circle().fill(c.surface2)
            Circle().stroke(c.lineStrong, lineWidth: 1)
            // Handoff 00c: 上端に MODE/PRESET/VIEW のミニインジケータ（centerCore あるとき）
            if centerCore != nil {
                Rectangle().fill(c.accent).frame(width: 2, height: 7)
                    .offset(y: -38.5)
            }
            if let cfg = centerCore {
                modeCoreContent(cfg, c: c)
            } else {
                p2pCoreContent(c: c)
            }
        }
        .frame(width: 84, height: 84)
        .clipShape(Circle())
        .contentShape(Circle())
        .onTapGesture {
            S8WheelHaptic.tap()
            guard let cfg = centerCore else {
                // 承認タブ等：中心タップ = P2P トグル
                let wasConnected = connected
                onToggleConn()
                UINotificationFeedbackGenerator().notificationOccurred(wasConnected ? .warning : .success)
                return
            }
            if let direct = cfg.directAction {
                direct()   // 直接発火（勉強・カレンダー・リストの「作成」等）
            } else if !cfg.options.isEmpty {
                onOpenModeWheel()   // モードホイールを開く
            }
        }
        // Timer タブの Crown 展開など、タブ固有の長押しアクション（cfg.longPressAction）だけ発火。
        // 全タブ共通の長押し（旧 P2P トグル）は 2026-07-11 廃止。
        .onLongPressGesture(minimumDuration: 0.55) {
            guard let cfg = centerCore, let action = cfg.longPressAction else { return }
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            action()
        }
    }

    /// P2P LINK ビジュアル（Approve タブや centerCore == nil のフォールバック）。
    /// 中心タップで接続 ON/OFF が切り替わることを明示（wifi/wifi.slash アイコン＋タップヒント）。
    private func p2pCoreContent(c: S8Palette) -> some View {
        let live = connected && peers > 0
        let iconName: String
        let iconColor: Color
        let mainText: String
        let hintText: String
        if connected && live {
            iconName = "wifi"
            iconColor = c.ok
            mainText = "\(peers)人"
            hintText = "タップで切断"
        } else if connected {
            iconName = "wifi"
            iconColor = c.warn
            mainText = "接続中"
            hintText = "タップで切断"
        } else if searching {
            iconName = "wifi"
            iconColor = c.warn
            mainText = "探索中"
            hintText = "タップで停止"
        } else {
            iconName = "wifi.slash"
            iconColor = c.fg3
            mainText = "OFF"
            hintText = "タップで接続"
        }
        return VStack(spacing: 2) {
            Image(systemName: iconName)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(iconColor)
                .symbolEffect(.pulse, options: .repeating, isActive: searching && !connected)
            Text(mainText).font(S8Font.mono(12, .bold)).foregroundColor(c.fg1)
            Text(hintText).font(S8Font.mono(7.5)).tracking(1.2).foregroundColor(c.fg3)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }

    /// Handoff 00c: MODE / PRESET / FILTER / VIEW コアの表示。
    private func modeCoreContent(_ cfg: S8CenterCoreConfig, c: S8Palette) -> some View {
        VStack(spacing: 2) {
            Text(cfg.cap).font(S8Font.mono(7.5)).tracking(1.6).foregroundColor(c.fg3)
            Text(cfg.main)
                .font(S8Font.jp(cfg.main.count > 2 ? 14 : 21, .bold))
                .foregroundColor(c.accentInk)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            if !cfg.pips.isEmpty {
                HStack(spacing: 4) {
                    ForEach(0..<cfg.pips.count, id: \.self) { i in
                        Circle()
                            .fill(cfg.pips[i] ? c.accent : c.lineStrong)
                            .frame(width: 5, height: 5)
                    }
                }
            } else if let sub = cfg.sub {
                Text(sub).font(S8Font.mono(7)).tracking(1.0).foregroundColor(c.fg3)
                    .lineLimit(1)
            }
        }
    }

    private func minimizedCapsule(_ c: S8Palette) -> some View {
        let cur = s8Tabs[min(max(0, tabIndex), N - 1)]
        return Button {
            S8WheelHaptic.tap()
            withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) { minimized = false }
        } label: {
            HStack(spacing: 8) {
                S8Icon(name: cur.icon, size: 18, color: c.accent)
                    .symbolVariant(.fill)
                    .symbolEffect(.bounce, value: tabIndex)
                Text(cur.label).font(S8Font.jp(14, .bold)).foregroundColor(c.fg1)
                S8Icon(name: "chevron-up", size: 16, color: c.fg3)
            }
            .padding(.horizontal, 18).padding(.vertical, 11)
            .background(c.surface)
            .overlay(Capsule().stroke(c.lineStrong, lineWidth: 1))
            .clipShape(Capsule())
            .shadow(color: Color.black.opacity(0.12), radius: 10, x: 0, y: 4)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - フィルタホイール（ホーム/広告のカテゴリ絞り込み・旧 FilterWheelNavigation の S8 移植）
//
// ホイールナビと同じ操作感（ドラッグ回転 + タップ選択）で、ノードがタブではなく
// カテゴリになる。中心タップで閉じる。S8Root がタブに応じてアイテムを渡す。

struct S8WheelFilterItem: Identifiable, Equatable {
    let id: String       // "" = すべて
    let icon: String
    let label: String
}

struct S8FilterWheel: View {
    let items: [S8WheelFilterItem]
    @Binding var selectedIndex: Int
    let onClose: () -> Void
    var bottomSafe: CGFloat = 0

    private let D: CGFloat = 280
    private let R: CGFloat = 92
    private var N: Int { max(1, items.count) }
    private var STEP: Double { 360.0 / Double(N) }
    private var domeH: CGFloat { D * 0.72 }

    @State private var rot: Double = 0
    @State private var dragging = false
    @State private var lastAngle: Double? = nil
    @State private var didRotate = false

    @Environment(\.colorScheme) private var scheme

    private func norm(_ a: Double) -> Double { let m = a.truncatingRemainder(dividingBy: 360); return m < 0 ? m + 360 : m }

    private func selOf(_ r: Double) -> Int {
        var best = 0, bd = 1e9
        for i in 0..<N {
            let a = norm(Double(i) * STEP - 90 + r)
            var d = abs(a - 270); d = min(d, 360 - d)
            if d < bd { bd = d; best = i }
        }
        return best
    }

    private func snap(to i: Int) {
        S8WheelHaptic.tap()
        let target = -Double(i) * STEP
        let k = ((rot - target) / 360).rounded()
        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) { rot = target + k * 360 }
        if selectedIndex != i { selectedIndex = i }
    }

    var body: some View {
        let c = S8Palette.of(scheme)
        let sel = selOf(rot)
        let hitH = max(1, domeH - bottomSafe)
        return Color.clear
            .frame(width: D, height: domeH)
            .overlay(alignment: .top) {
                ZStack(alignment: .top) {
                    Group {
                        Circle().fill(c.surface).overlay(Circle().stroke(c.accent.opacity(0.55), lineWidth: 1))
                        Circle().inset(by: 18).stroke(c.line, lineWidth: 1)
                        // 上端インジケータ
                        Rectangle().fill(c.accent)
                            .frame(width: 3, height: 9)
                            .frame(width: D, height: D, alignment: .top)
                            .padding(.top, 3)
                        // カテゴリノード
                        ForEach(Array(items.enumerated()), id: \.element.id) { i, item in
                            let a = (Double(i) * STEP - 90 + rot) * .pi / 180
                            let x = D / 2 + R * cos(a)
                            let y = D / 2 + R * sin(a)
                            VStack(spacing: 2) {
                                // ponytail: symbolVariant(.fill) を削除。ユーザーが選んだ SF Symbol 名
                                // (例 "tag.fill") が二重 fill にならない
                                S8Icon(name: item.icon, size: 17, color: i == sel ? c.accent : c.fg2)
                                Text(item.label).font(S8Font.jp(9, i == sel ? .bold : .medium))
                                    .foregroundColor(i == sel ? c.accent : c.fg3)
                                    .lineLimit(1)
                            }
                            .frame(width: 50, height: 42)
                            .position(x: x, y: y)
                        }
                    }
                    .allowsHitTesting(false)

                    // 回転 + タップ選択（静止ドラッグ面）
                    Color.clear
                        .frame(width: D, height: D)
                        .contentShape(Circle())
                        .gesture(filterDrag)
                        .frame(width: D, height: hitH, alignment: .top)
                        .clipped()

                    // 中心 = 現在の選択 + 閉じる。下端見切れ防止のため、hitH 制約と .clipped() を外して
                    // 外側 D×D 枠内に自然配置する（円自体は 84×84、y=D/2 中心なので必ず枠内に収まる）。
                    Button(action: { S8WheelHaptic.tap(); onClose() }) {
                        ZStack {
                            Circle().fill(c.accentWash)
                            Circle().stroke(c.accent, lineWidth: 1)
                            VStack(spacing: 3) {
                                S8Icon(name: "filter", size: 15, color: c.accentInk)
                                Text(items.indices.contains(sel) ? items[sel].label : "すべて")
                                    .font(S8Font.jp(11, .bold)).foregroundColor(c.fg1).lineLimit(1)
                                Text("とじる").font(S8Font.mono(8)).tracking(1.2).foregroundColor(c.fg3)
                            }
                            .padding(.horizontal, 6)
                        }
                        .frame(width: 84, height: 84)
                        .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .position(x: D / 2, y: D / 2)
                }
                .frame(width: D, height: D, alignment: .top)
            }
            .clipped()
            .onAppear {
                // 現在の選択にホイールを合わせる
                rot = -Double(min(max(0, selectedIndex), N - 1)) * STEP
            }
    }

    private var filterDrag: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { g in
                let dx = Double(g.location.x) - Double(D) / 2
                let dy = Double(g.location.y) - Double(D) / 2
                let r = (dx * dx + dy * dy).squareRoot()
                let cur = atan2(dy, dx) * 180 / .pi
                let moved = (Double(g.translation.width) * Double(g.translation.width)
                           + Double(g.translation.height) * Double(g.translation.height)).squareRoot()
                if !didRotate && moved > 6 {
                    didRotate = true
                    dragging = true
                    lastAngle = cur
                }
                if didRotate, let prev = lastAngle, r > 42 {   // 中心ボタン領域は回転に使わない
                    var d = cur - prev
                    if d > 180 { d -= 360 } else if d < -180 { d += 360 }
                    rot += d
                    lastAngle = cur
                    let s = selOf(rot)
                    if s != selectedIndex { selectedIndex = s; S8WheelHaptic.tick() }
                }
            }
            .onEnded { g in
                let rotated = didRotate
                didRotate = false
                dragging = false
                lastAngle = nil
                if rotated {
                    snap(to: selOf(rot))
                } else {
                    let dx = Double(g.startLocation.x) - Double(D) / 2
                    let dy = Double(g.startLocation.y) - Double(D) / 2
                    if (dx * dx + dy * dy).squareRoot() > 42 {
                        // タップ：押した方向に最も近いノードを選択
                        var best = 0, bd = 1e9
                        let ang = atan2(dy, dx) * 180 / .pi
                        for i in 0..<N {
                            let na = norm(Double(i) * STEP - 90 + rot)
                            var diff = abs(norm(ang) - na)
                            diff = min(diff, 360 - diff)
                            if diff < bd { bd = diff; best = i }
                        }
                        snap(to: best)
                    }
                }
            }
    }
}

// MARK: - P2P ミニコントロール（タブ操作時用・項目20）
//
// ホイールの中心コア相当：通信品質バー + ピア数 + 長押しで接続トグル。

struct S8P2PMiniControl: View {
    let peers: Int
    let connected: Bool
    /// 通信強度 0〜3（バー表示用）。
    var quality: Int = 0
    let onToggleConn: () -> Void
    @State private var pressing = false
    @State private var pressProgress: CGFloat = 0
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let c = S8Palette.of(scheme)
        let live = connected && peers > 0
        let qColor: Color = !connected ? c.fg3 : (live ? c.ok : c.warn)
        let qText: String = !connected ? "OFF" : (live ? "\(peers)人" : "探索中")
        return HStack(spacing: 7) {
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(0..<3, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(quality > i ? qColor : c.line)
                        .frame(width: 3.5, height: 5 + CGFloat(i) * 3.5)
                }
            }
            .frame(height: 12, alignment: .bottom)
            Text(qText).font(S8Font.mono(11, .bold)).foregroundColor(c.fg1)
            // 長押し進捗
            Circle()
                .trim(from: 0, to: pressProgress)
                .stroke(connected ? c.danger : c.ok, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .frame(width: 12, height: 12)
                .opacity(pressing ? 1 : 0)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(c.surface)
        .overlay(Capsule().stroke(c.lineStrong, lineWidth: 1))
        .clipShape(Capsule())
        .scaleEffect(pressing ? 0.95 : 1)
        .animation(.spring(response: 0.2), value: pressing)
        .contentShape(Capsule())
        .onLongPressGesture(minimumDuration: 0.6, pressing: { isPressing in
            pressing = isPressing
            if isPressing {
                S8WheelHaptic.tap()
                withAnimation(.linear(duration: 0.6)) { pressProgress = 1 }
            } else {
                withAnimation(.easeOut(duration: 0.2)) { pressProgress = 0 }
            }
        }, perform: {
            let wasConnected = connected
            onToggleConn()
            UINotificationFeedbackGenerator().notificationOccurred(wasConnected ? .warning : .success)
            pressing = false
            withAnimation(.easeOut(duration: 0.2)) { pressProgress = 0 }
        })
    }
}

// MARK: - タブバー（ホイールを使わないとき）

struct S8TabBar: View {
    @Binding var tabIndex: Int
    var unread: Int = 0
    @Environment(\.colorScheme) private var scheme
    /// タブごとの SF Symbol バウンス用カウンタ。選択された瞬間だけ増やす＝移動先のみ弾む。
    @State private var bump = [Int](repeating: 0, count: s8Tabs.count)

    var body: some View {
        let c = S8Palette.of(scheme)
        VStack(spacing: 0) {
            S8Rule()
            HStack(spacing: 0) {
                ForEach(Array(s8Tabs.enumerated()), id: \.element.id) { i, t in
                    Button {
                        guard i != tabIndex else { return }
                        S8WheelHaptic.tick()   // ホイール同様の選択触覚
                        tabIndex = i           // コンテンツ切替は即時（ホイールと同じ）。見た目だけ下で animate。
                    } label: {
                        VStack(spacing: 4) {
                            ZStack(alignment: .topTrailing) {
                                S8Icon(name: t.icon, size: 22, color: i == tabIndex ? c.accent : c.fg3)
                                    .frame(width: 30, height: 24)
                                    .symbolVariant(i == tabIndex ? .fill : .none)   // 選択中はフィル／非選択は縁
                                    .symbolEffect(.bounce, value: bump[i])          // 移動先のみ弾む
                                if t.id == "dm" && unread > 0 {
                                    Text("\(unread)").font(S8Font.mono(8, .bold)).foregroundColor(c.onAccent)
                                        .frame(minWidth: 14, minHeight: 14)
                                        .background(c.accent).clipShape(Capsule())
                                        .offset(x: 6, y: -4)
                                }
                            }
                            Text(t.label).font(S8Font.jp(9, i == tabIndex ? .bold : .medium))
                                .foregroundColor(i == tabIndex ? c.accent : c.fg3)
                        }
                        .frame(maxWidth: .infinity)
                        .scaleEffect(i == tabIndex ? 1.06 : 1)   // 選択タブが少しポップ
                        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: tabIndex)   // 見た目のみ
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 10).padding(.bottom, 8)
            .background(c.surface)
        }
        .onChange(of: tabIndex) { _, new in
            if bump.indices.contains(new) { bump[new] += 1 }   // 移動先のみバウンス
        }
    }
}

// MARK: - S8WheelOverlayPresenter（Talk 流儀のホイール直接差替オーバレイの共有提示器）
//
// ホイール中央領域を S8FilterWheel に差替える汎用パス。ContentView が @State で observe し、
// MorphCalendar のカテゴリフィルタなど任意の子ビューが `shared` から present する。
// シートではなくホイール位置そのものを差し替えるため、背景グレーアウトは Content 側で実装。

enum S8WheelOverlayMode: Equatable {
    case filter                              // 従来の S8FilterWheel（アイコン + ラベル）
    case crown(range: ClosedRange<Int>, unit: String)   // Crown ホイール（1周60ドット等の連続値）
}

@Observable
@MainActor
final class S8WheelOverlayPresenter {
    static let shared = S8WheelOverlayPresenter()

    var isPresented: Bool = false
    var mode: S8WheelOverlayMode = .filter
    /// filter 用：アイコン+ラベル項目。crown モードでは未使用。
    var items: [S8WheelFilterItem] = []
    /// filter 用 index / crown 用の現在値の両方に流用。
    var selectedIndex: Int = 0
    private var _onSelect: (Int) -> Void = { _ in }

    private init() {}

    func present(items: [S8WheelFilterItem], selectedIndex: Int, onSelect: @escaping (Int) -> Void) {
        self.mode = .filter
        self.items = items
        self.selectedIndex = max(0, min(items.count - 1, selectedIndex))
        self._onSelect = onSelect
        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
            self.isPresented = true
        }
    }

    /// Crown モード提示（Timer タブの時間設定用）。range 内の初期値と分単位確定コールバックを渡す。
    func presentCrown(range: ClosedRange<Int>, currentValue: Int, unit: String = "分", onSelect: @escaping (Int) -> Void) {
        self.mode = .crown(range: range, unit: unit)
        self.items = []
        self.selectedIndex = max(range.lowerBound, min(range.upperBound, currentValue))
        self._onSelect = onSelect
        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
            self.isPresented = true
        }
    }

    func commitAndDismiss() {
        let cb = _onSelect
        let idx = selectedIndex
        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
            self.isPresented = false
        }
        cb(idx)
    }

    func dismissWithoutCommit() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
            self.isPresented = false
        }
    }
}

// MARK: - S8CrownWheel（60 ドット環の連続値ホイール。時間設定など）
//
// ハンドオフ準拠：ドラッグで回転、6°/分のスナップ、5分ごとに数字ラベル。
// 巻いた分だけ accent、未セット分は line で描く。中心＝現在値の mono 表示 + 「とじる」。

struct S8CrownWheel: View {
    /// 対象範囲（例: 1...180 分）。範囲を超えるドラッグはクランプ。
    let range: ClosedRange<Int>
    @Binding var value: Int
    var unit: String = "分"
    let onClose: () -> Void
    var bottomSafe: CGFloat = 0

    /// ドット環のサイズ・半径。
    private let D: CGFloat = 280
    private let R: CGFloat = 118
    /// 1 周 60 ドット固定（1周目は分単位の刻み）。
    private let dotCount: Int = 60
    /// 1 ドットあたり 6°（＝360°/60）。
    private var stepDeg: Double { 360.0 / Double(dotCount) }
    /// 2 周目に入る回転角。360°。
    private var lap2StartDeg: Double { 360.0 }
    /// 2 周目の最大回転角（180 分まで到達するのに必要な角度）: 360 + (180-60)/10 * 6 = 432°。
    private var maxRotDeg: Double { 360.0 + Double(max(0, range.upperBound - 60)) / 10.0 * stepDeg }
    private var domeH: CGFloat { D * 0.72 }

    /// 累積回転角（ring rotation）。0..maxRotDeg。値の唯一の源。
    @State private var rot: Double = 0
    @State private var dragging = false
    @State private var lastAngle: Double? = nil

    @Environment(\.colorScheme) private var scheme

    /// 回転角 → 値（1周目=1分/dot、2周目=10分/dot）。
    private func valueFor(_ deg: Double) -> Int {
        let d = max(0, min(maxRotDeg, deg))
        if d <= lap2StartDeg {
            return max(range.lowerBound, min(60, Int(round(d / stepDeg))))
        } else {
            let laps2 = Int(round((d - lap2StartDeg) / stepDeg))   // 1..12
            return min(range.upperBound, 60 + laps2 * 10)
        }
    }

    /// 値 → 回転角（初期化用）。
    private func rotFor(_ v: Int) -> Double {
        let clamped = max(range.lowerBound, min(range.upperBound, v))
        if clamped <= 60 {
            return Double(clamped) * stepDeg
        } else {
            return lap2StartDeg + Double(clamped - 60) / 10.0 * stepDeg
        }
    }

    /// 現在が 2 周目か。
    private var isLap2: Bool { rot > lap2StartDeg + 0.5 }

    var body: some View {
        let c = S8Palette.of(scheme)
        return Color.clear
            .frame(width: D, height: domeH)
            .overlay(alignment: .top) {
                ZStack(alignment: .top) {
                    // rim（2周目はアクセント縁で識別）
                    Circle().fill(c.surface)
                        .overlay(Circle().stroke(isLap2 ? c.accent : c.lineStrong, lineWidth: isLap2 ? 2 : 1))
                    Circle().inset(by: 18).stroke(c.line, lineWidth: 1)

                    // 上部固定インジケータ（ここに揃った値が選択される）
                    Rectangle().fill(c.accent)
                        .frame(width: 3, height: 10)
                        .position(x: D / 2, y: 8)

                    // 回転するドット環：ring 側を .rotationEffect で回す。上部の pointer が「選択」を示す。
                    ZStack {
                        ForEach(0..<dotCount, id: \.self) { i in
                            let a = (Double(i) * stepDeg - 90) * .pi / 180
                            let x = D / 2 + R * cos(a)
                            let y = D / 2 + R * sin(a)
                            // 1周目: dot i が塗られる条件は i <= value（ただし value<=60）
                            // 2周目: 全 60 dot を塗り、加えて (value-60)/10 個の 2周目 dot をアクセント強色で表現
                            let litLap1 = i <= min(60, value)
                            let lit2ndIndex = isLap2 ? Int(round((rot - lap2StartDeg) / stepDeg)) : 0
                            let isLap2Dot = isLap2 && i > 0 && i <= lit2ndIndex
                            let isMajor = (i % 5 == 0)
                            Circle()
                                .fill(isLap2Dot ? c.accent : (litLap1 ? c.accent : c.lineStrong))
                                .frame(width: isMajor ? 6 : 4, height: isMajor ? 6 : 4)
                                .position(x: x, y: y)
                            if isMajor && i > 0 {
                                // 1周目ラベル: 5,10,...,60。ring 回転を counter-rotate してテキストを常に上向きに。
                                Text("\(i)")
                                    .font(S8Font.mono(9, .bold))
                                    .foregroundColor((litLap1 || isLap2Dot) ? c.accent : c.fg3)
                                    .rotationEffect(.degrees(rot))
                                    .position(x: D / 2 + (R - 22) * cos(a), y: D / 2 + (R - 22) * sin(a))
                            }
                        }
                    }
                    .rotationEffect(.degrees(-rot))
                    .animation(.interactiveSpring(response: 0.15), value: rot)
                    .allowsHitTesting(false)

                    // ドラッグ面（回転しない固定レイヤ）
                    Color.clear
                        .frame(width: D, height: D)
                        .contentShape(Circle())
                        .gesture(crownDrag)
                        .clipped()

                    // 中心 = 現在値 + 「とじる」
                    Button(action: {
                        S8WheelHaptic.tap()
                        onClose()
                    }) {
                        ZStack {
                            Circle().fill(c.accentWash)
                            Circle().stroke(c.accent, lineWidth: 1)
                            VStack(spacing: 2) {
                                Text("\(value)").font(S8Font.mono(28, .bold)).foregroundColor(c.fg1)
                                Text(unit.uppercased()).font(S8Font.mono(9)).tracking(1.5).foregroundColor(c.fg3)
                                if isLap2 {
                                    Text("×10").font(S8Font.mono(8, .bold)).tracking(1.2).foregroundColor(c.accent)
                                }
                                Text("とじる").font(S8Font.mono(8)).tracking(1.2).foregroundColor(c.fg3)
                                    .padding(.top, 2)
                            }
                        }
                        .frame(width: 108, height: 108)
                        .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .position(x: D / 2, y: D / 2)
                }
                .frame(width: D, height: D)
            }
            .clipped()
            .onAppear {
                // 現在値に合わせて rot を初期化
                rot = rotFor(value)
            }
    }

    private var crownDrag: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { g in
                let dx = Double(g.location.x) - Double(D) / 2
                let dy = Double(g.location.y) - Double(D) / 2
                let r = (dx * dx + dy * dy).squareRoot()
                let cur = atan2(dy, dx) * 180 / .pi
                let moved = (Double(g.translation.width) * Double(g.translation.width)
                           + Double(g.translation.height) * Double(g.translation.height)).squareRoot()
                if !dragging && moved > 6 {
                    dragging = true
                    lastAngle = cur
                }
                if dragging, let prev = lastAngle, r > 32 {   // 中心ボタンは無視
                    var d = cur - prev
                    if d > 180 { d -= 360 } else if d < -180 { d += 360 }
                    lastAngle = cur
                    // Balmuda 参考：finger と scale を同方向に動かす直感に合わせるため d を反転。
                    // CW ドラッグ → rot 減 → 値↓、CCW ドラッグ → rot 増 → 値↑。
                    let effectiveD = -d
                    let newRot = max(0, min(maxRotDeg, rot + effectiveD))
                    let prevValue = value
                    rot = newRot
                    let nextValue = valueFor(newRot)
                    if nextValue != prevValue {
                        value = nextValue
                        S8WheelHaptic.tick()
                    }
                }
            }
            .onEnded { _ in
                dragging = false
                lastAngle = nil
                // スナップ: 選択値に対応する rot に吸着（視覚的にドットが pointer に整列）
                withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                    rot = rotFor(value)
                }
            }
    }
}
