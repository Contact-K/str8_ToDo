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
]

// MARK: - 触覚フィードバック

private enum S8WheelHaptic {
    /// 選択が次の項目へ移った瞬間の軽いコツッ
    static func tick() { UISelectionFeedbackGenerator().selectionChanged() }
    /// スナップ確定・タップ時の軽い衝撃
    static func tap() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
}

// MARK: - クリックホイール

struct S8ClickWheel: View {
    @Binding var tabIndex: Int
    @Binding var minimized: Bool
    let peers: Int
    let connected: Bool
    /// 通信強度 0〜3（バー表示用。人数とは独立・項目 R2-③）。
    var quality: Int = 0
    /// 画面下端のセーフエリア量（ホームインジケータ帯）。表示はここまで埋め、当たり判定はこの帯を除外する。
    var bottomSafe: CGFloat = 0
    let onToggleConn: () -> Void

    private let D: CGFloat = 280
    private let R: CGFloat = 92
    private var N: Int { s8Tabs.count }
    private var STEP: Double { 360.0 / Double(N) }

    @State private var rot: Double = 0
    @State private var dragging = false
    @State private var lastAngle: Double? = nil
    @State private var didRotate = false
    @State private var pressProgress: CGFloat = 0   // 中心ボタン長押しの進捗リング
    @State private var pressing = false
    /// ノードごとの SF Symbol バウンス用カウンタ。選択された瞬間だけ増やす＝移動先のみ弾む。
    @State private var bump = [Int](repeating: 0, count: s8Tabs.count)

    /// 下端ドックの半ドームの可視高さ（円の下側を画面下端に埋める）。中心 P2P コアは収まる。
    private var domeH: CGFloat { D * 0.67 }

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

    // 中心 P2P コア：長押しで接続トグル。バーは通信強度（linkQuality 0〜3）を表す。
    private func centerCore(_ c: S8Palette) -> some View {
        let live = connected && peers > 0
        let qColor: Color = !connected ? c.fg3 : (live ? c.ok : c.warn)
        let qText: String = !connected ? "OFF" : (live ? "\(peers)人" : "探索中")
        let ringColor: Color = connected ? c.danger : c.ok   // 長押しで OFF にするなら赤、ON にするなら緑
        return ZStack {
            Circle().fill(c.surface2)
            // 長押し進捗リング（0→1 充填で確定）
            Circle()
                .trim(from: 0, to: pressProgress)
                .stroke(ringColor, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .padding(3)
            Circle().stroke(c.lineStrong, lineWidth: 1)
            VStack(spacing: 3) {
                // 通信強度バー（人数連動ではなくリンク状態 0〜3）
                HStack(alignment: .bottom, spacing: 2) {
                    ForEach(0..<3, id: \.self) { i in
                        RoundedRectangle(cornerRadius: 1)
                            .fill(quality > i ? qColor : c.line)
                            .frame(width: 4, height: 6 + CGFloat(i) * 4)
                    }
                }
                .frame(height: 14, alignment: .bottom)
                Text(qText).font(S8Font.mono(12, .bold)).foregroundColor(c.fg1)
                Text("品質").font(S8Font.mono(8)).tracking(1.5).foregroundColor(c.fg3)
            }
        }
        .frame(width: 84, height: 84)
        .clipShape(Circle())
        .scaleEffect(pressing ? 0.94 : 1)
        .animation(.spring(response: 0.2), value: pressing)
        .contentShape(Circle())
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
    private var domeH: CGFloat { D * 0.67 }

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
                                S8Icon(name: item.icon, size: 17, color: i == sel ? c.accent : c.fg2)
                                    .symbolVariant(i == sel ? .fill : .none)
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

                    // 中心 = 現在の選択 + 閉じる
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
                    .frame(width: D, height: hitH, alignment: .top)
                    .clipped()
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
