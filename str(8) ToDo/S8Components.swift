// S8Components.swift — str(8) 共通プリミティブ（SwiftUI）。primitives.jsx + talk.css 相当。
// アイコンは SF Symbols（Lucide 名 → systemName）。記号名が違っても描画が空になるだけでビルドは通る。

import SwiftUI

/// Lucide 名 → SF Symbol 名。
func s8Symbol(_ name: String) -> String {
    switch name {
    case "waves": return "water.waves"
    case "newspaper": return "newspaper"
    case "message-square", "message-circle": return "bubble.left"
    case "users", "user-plus": return "person.2"
    case "user": return "person"
    case "home": return "house"
    case "settings", "gear": return "gearshape"
    case "plus": return "plus"
    case "arrow-left", "chevron-left": return "chevron.left"
    case "arrow-right": return "arrow.right"
    case "chevron-right": return "chevron.right"
    case "chevron-down": return "chevron.down"
    case "chevron-up": return "chevron.up"
    case "send": return "paperplane.fill"
    case "more-horizontal": return "ellipsis"
    case "clock": return "clock"
    case "calendar": return "calendar"
    case "hourglass": return "hourglass"
    case "list": return "list.bullet"
    case "check-circle": return "checkmark.circle"
    case "book-open": return "book"
    case "flame": return "flame"
    case "check": return "checkmark"
    case "x": return "xmark"
    case "star": return "star.fill"
    case "wifi", "radio": return "wifi"
    case "wifi-off": return "wifi.slash"
    case "search": return "magnifyingglass"
    case "bell": return "bell"
    case "bookmark", "tag": return "bookmark"
    case "inbox": return "tray"
    case "cloud-rain": return "cloud.rain"
    case "help-circle": return "questionmark.circle"
    case "droplet": return "drop"
    case "zap": return "bolt"
    case "heart": return "heart"
    case "alert-triangle": return "exclamationmark.triangle"
    case "gift": return "gift"
    case "venetian-mask": return "theatermasks"
    case "sparkles": return "sparkles"
    case "palette": return "paintpalette"
    case "pin": return "pin"
    case "map-pin": return "mappin.circle"
    case "lock": return "lock"
    case "eye-off": return "eye.slash"
    case "shield": return "shield"
    case "repeat": return "repeat"
    case "megaphone": return "megaphone"
    case "move-horizontal": return "arrow.left.and.right"
    case "scaling": return "arrow.up.left.and.arrow.down.right"
    case "hand": return "hand.tap"
    case "circle-dot": return "smallcircle.filled.circle"
    case "plus-circle": return "plus.circle"
    case "mouse-pointer": return "cursorarrow"
    case "point": return "p.circle"                       // チャットポイント
    case "fork-knife": return "fork.knife"
    case "cart": return "cart"
    case "wrench": return "wrench.adjustable"
    case "building": return "building.2"
    case "calendar-days": return "calendar"
    case "camera": return "camera"
    case "video": return "video"
    case "image": return "photo"
    case "trash": return "trash"
    case "filter": return "line.3.horizontal.decrease"
    case "info": return "info.circle"
    case "sun": return "sun.max"
    case "moon": return "moon"
    case "shopping-bag", "shop": return "bag"
    case "copy": return "doc.on.doc"
    case "share": return "square.and.arrow.up"
    case "file": return "doc"
    case "text-cursor": return "character.cursor.ibeam"
    case "shuffle": return "shuffle"
    case "bug": return "ladybug"
    case "bar-chart": return "chart.bar.xaxis"
    default: return "circle"
    }
}

struct S8Icon: View {
    let name: String
    var size: CGFloat = 20
    var color: Color? = nil
    var body: some View {
        Image(systemName: s8Symbol(name))
            .font(.system(size: size, weight: .regular))
            .foregroundColor(color)
    }
}

/// mono キャプション（大文字・字間広め）。
struct S8Cap: View {
    let text: String
    var color: Color? = nil
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        Text(text.uppercased())
            .font(S8Font.mono(10))
            .tracking(1.5)
            .foregroundColor(color ?? S8Palette.of(scheme).fg3)
    }
}

/// ヘアライン。
struct S8Rule: View {
    var strong = false
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let c = S8Palette.of(scheme)
        Rectangle().fill(strong ? c.lineStrong : c.line).frame(height: 1)
    }
}

// MARK: - Button

struct S8Button: View {
    enum Variant { case primary, secondary, ghost }
    let label: String
    var icon: String? = nil
    var variant: Variant = .primary
    var fillWidth: Bool = true
    var enabled: Bool = true
    let action: () -> Void
    init(_ label: String, icon: String? = nil, variant: Variant = .primary, fillWidth: Bool = true, enabled: Bool = true, action: @escaping () -> Void) {
        self.label = label; self.icon = icon; self.variant = variant; self.fillWidth = fillWidth; self.enabled = enabled; self.action = action
    }
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let c = S8Palette.of(scheme)
        let fg: Color = {
            switch variant {
            case .primary: return enabled ? c.onAccent : c.fg3
            case .secondary: return c.fg1
            case .ghost: return c.fg2
            }
        }()
        let bg: Color = {
            switch variant {
            case .primary: return enabled ? c.accent : c.surface2
            default: return .clear
            }
        }()
        Button(action: action) {
            HStack(spacing: 8) {
                if let icon { S8Icon(name: icon, size: 18, color: fg) }
                Text(label).font(S8Font.jp(15, .bold)).foregroundColor(fg)
            }
            .frame(maxWidth: fillWidth ? .infinity : nil)
            .padding(.horizontal, variant == .ghost ? 12 : 20)
            .padding(.vertical, variant == .ghost ? 10 : 14)
            .background(bg)
            .overlay(
                RoundedRectangle(cornerRadius: S8Radius.md)
                    .stroke(variant == .secondary ? c.lineStrong : .clear, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: S8Radius.md))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}

// MARK: - Chip

struct S8Chip: View {
    let label: String
    var icon: String? = nil
    var selected: Bool = false
    var jp: Bool = true
    let action: () -> Void
    init(_ label: String, icon: String? = nil, selected: Bool = false, jp: Bool = true, action: @escaping () -> Void) {
        self.label = label; self.icon = icon; self.selected = selected; self.jp = jp; self.action = action
    }
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let c = S8Palette.of(scheme)
        let fg = selected ? c.onAccent : c.fg2
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon { S8Icon(name: icon, size: 14, color: fg) }
                Text(jp ? label : label.uppercased())
                    .font(jp ? S8Font.jp(13, .medium) : S8Font.mono(10.5))
                    .tracking(jp ? 0 : 0.8)
                    .foregroundColor(fg)
            }
            .padding(.horizontal, 11).padding(.vertical, 7)
            .background(selected ? c.accent : .clear)
            .overlay(RoundedRectangle(cornerRadius: S8Radius.md).stroke(selected ? c.accent : c.lineStrong, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: S8Radius.md))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Tag (mono meta)

struct S8Tag: View {
    let label: String
    var icon: String? = nil
    var color: Color? = nil
    init(_ label: String, icon: String? = nil, color: Color? = nil) {
        self.label = label; self.icon = icon; self.color = color
    }
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let c = color ?? S8Palette.of(scheme).fg3
        HStack(spacing: 5) {
            if let icon { S8Icon(name: icon, size: 12, color: c) }
            Text(label.uppercased()).font(S8Font.mono(9.5)).tracking(1.1).foregroundColor(c)
        }
    }
}

// MARK: - Toggle

struct S8Toggle: View {
    let on: Bool
    let action: () -> Void
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let c = S8Palette.of(scheme)
        Button(action: action) {
            ZStack(alignment: on ? .trailing : .leading) {
                Capsule().fill(on ? c.accent : c.surface2)
                    .overlay(Capsule().stroke(on ? c.accent : c.lineStrong, lineWidth: 1))
                    .frame(width: 42, height: 24)
                Circle().fill(c.paper).frame(width: 18, height: 18).padding(2)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - TTL meter

struct S8Ttl: View {
    let remain: Int
    let ttl: Int
    var segs: Int = 6
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let c = S8Palette.of(scheme)
        let frac = max(0, min(1, Double(remain) / Double(max(1, ttl))))
        let lit = max(remain > 0 ? 1 : 0, Int((frac * Double(segs)).rounded()))
        let on = remain <= 5 ? c.danger : c.accent
        HStack(spacing: 2) {
            ForEach(0..<segs, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1).fill(i < lit ? on : c.lineStrong).frame(width: 5, height: 3)
            }
        }
    }
}

// MARK: - Field

struct S8Field: View {
    var label: String? = nil
    var placeholder: String = ""
    @Binding var text: String
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let c = S8Palette.of(scheme)
        VStack(alignment: .leading, spacing: 7) {
            if let label { Text(label).font(S8Font.jp(13, .medium)).foregroundColor(c.fg2) }
            TextField(placeholder, text: $text)
                .font(S8Font.jp(15, .regular))
                .foregroundColor(c.fg1)
                .padding(.horizontal, 14).padding(.vertical, 13)
                .background(c.surface)
                .overlay(RoundedRectangle(cornerRadius: S8Radius.md).stroke(c.lineStrong, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: S8Radius.md))
        }
    }
}

// MARK: - Status bar

struct S8StatusBar: View {
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let c = S8Palette.of(scheme)
        HStack {
            Text("9:41").font(S8Font.mono(12)).tracking(0.5).foregroundColor(c.fg1)
            Spacer()
            HStack(spacing: 5) { ForEach(0..<3, id: \.self) { _ in Circle().fill(c.fg1).frame(width: 4, height: 4) } }
        }
        .padding(.horizontal, 24).frame(height: 48)
    }
}

// MARK: - Top bar（h1 + mono sub + trailing アクション）

struct S8TopBar<Trailing: View>: View {
    let title: String
    let sub: String
    @ViewBuilder var trailing: () -> Trailing
    init(_ title: String, sub: String, @ViewBuilder trailing: @escaping () -> Trailing) {
        self.title = title; self.sub = sub; self.trailing = trailing
    }
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let c = S8Palette.of(scheme)
        HStack(alignment: .bottom, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(S8Font.jp(23, .bold)).foregroundColor(c.fg1)
                Text(sub.uppercased()).font(S8Font.mono(10)).tracking(1.6).foregroundColor(c.fg3)
            }
            Spacer(minLength: 0)
            trailing()
        }
        .padding(.horizontal, 24).padding(.top, 8).padding(.bottom, 16)
    }
}

// MARK: - Icon button（38×38）

struct S8IconButton: View {
    let icon: String
    var accent: Bool = false
    let action: () -> Void
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let c = S8Palette.of(scheme)
        Button(action: action) {
            S8Icon(name: icon, size: 22, color: accent ? c.accent : c.fg2)
                .frame(width: 38, height: 38)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - FAB（話をはじめる / 貼る）

struct S8FAB: View {
    var icon: String = "plus"
    let action: () -> Void
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let c = S8Palette.of(scheme)
        Button(action: action) {
            S8Icon(name: icon, size: 26, color: c.onAccent)
                .frame(width: 56, height: 56)
                .background(c.accent)
                .clipShape(Circle())
                .shadow(color: Color.black.opacity(0.20), radius: 12, x: 0, y: 6)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Avatar（頭文字・近接バッジ）

struct S8Avatar: View {
    let name: String
    /// プロフィールのアイコン絵文字。空なら名前の頭文字にフォールバック。
    var emoji: String = ""
    var near: Bool = false
    var dim: CGFloat = 44
    var dimmed: Bool = false
    @Environment(\.colorScheme) private var scheme
    private var initial: String { String(name.first ?? "?") }
    var body: some View {
        let c = S8Palette.of(scheme)
        ZStack(alignment: .bottomTrailing) {
            Group {
                if emoji.isEmpty {
                    Text(initial).font(S8Font.jp(dim * 0.34, .bold)).foregroundColor(c.fg2)
                } else {
                    Text(emoji).font(.system(size: dim * 0.5))
                }
            }
                .frame(width: dim, height: dim)
                .background(c.surface2)
                .overlay(Circle().stroke(c.line, lineWidth: 1))
                .clipShape(Circle())
                .opacity(dimmed ? 0.6 : 1)
            if near {
                Circle().fill(c.ok)
                    .frame(width: 12, height: 12)
                    .overlay(Circle().stroke(c.paper, lineWidth: 2))
                    .offset(x: 1, y: 1)
            }
        }
    }
}

// MARK: - S8SetRow（設定画面の共通行）
//
// str(8)_Talk S8Profile.swift と同じ流儀：
//   [icon fg2] [label] Spacer [trailing view] [(chevron/onTap)]

struct S8SetRow<Trailing: View>: View {
    let icon: String
    let label: String
    @ViewBuilder var trailing: () -> Trailing
    var onTap: (() -> Void)? = nil
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let c = S8Palette.of(scheme)
        let row = HStack(spacing: 14) {
            S8Icon(name: icon, size: 20, color: c.fg2)
            Text(label).font(S8Font.jp(15)).foregroundColor(c.fg1)
            Spacer(minLength: 8)
            trailing()
        }
        .padding(.horizontal, 24).padding(.vertical, 15)
        .contentShape(Rectangle())

        if let onTap {
            Button(action: onTap) { row }.buttonStyle(.plain)
        } else {
            row
        }
    }
}

// MARK: - Section label

struct S8SectionLabel: View {
    let text: String
    var trailing: String? = nil
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let c = S8Palette.of(scheme)
        HStack {
            Text(text.uppercased()).font(S8Font.mono(10)).tracking(1.5).foregroundColor(c.fg3)
            Spacer()
            if let trailing {
                Text(trailing).font(S8Font.mono(10)).tracking(1.5).foregroundColor(c.fg3)
            }
        }
        .padding(.horizontal, 24).padding(.top, 22).padding(.bottom, 8)
    }
}

// MARK: - 通信品質バー（小型・ヘッダ用）

/// linkQuality(0〜3) をホイール中心と同じ 3 本バーで表す小型インジケータ。
struct S8QualityBars: View {
    let quality: Int
    let connected: Bool
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let c = S8Palette.of(scheme)
        let qColor: Color = !connected ? c.fg3 : (quality >= 2 ? c.ok : c.warn)
        HStack(alignment: .bottom, spacing: 1.5) {
            ForEach(0..<3, id: \.self) { i in
                RoundedRectangle(cornerRadius: 0.8)
                    .fill(quality > i ? qColor : c.line)
                    .frame(width: 3, height: 4 + CGFloat(i) * 3)
            }
        }
        .frame(height: 10, alignment: .bottom)
    }
}

// MARK: - Toast

struct S8ToastView: View {
    let text: String
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let c = S8Palette.of(scheme)
        HStack(spacing: 10) {
            S8Icon(name: "check", size: 18, color: c.accent)
            Text(text).font(S8Font.jp(14, .medium)).foregroundColor(c.paper)
        }
        .padding(.horizontal, 16).padding(.vertical, 13)
        .background(c.fg1)
        .clipShape(RoundedRectangle(cornerRadius: S8Radius.md))
        .shadow(color: Color.black.opacity(0.20), radius: 12, x: 0, y: 6)
    }
}

// MARK: - 上端だけ角丸の Shape（ボトムシート用・全 iOS 対応）

struct S8TopRounded: Shape {
    var radius: CGFloat
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let r = min(radius, min(rect.width, rect.height) / 2)
        p.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY + r))
        p.addQuadCurve(to: CGPoint(x: rect.minX + r, y: rect.minY), control: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX - r, y: rect.minY))
        p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY + r), control: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

// MARK: - ボトムシート（scrim + 下からせり上がるカード）

struct S8BottomSheet<SheetContent: View>: ViewModifier {
    @Binding var isPresented: Bool
    @ViewBuilder var sheetContent: () -> SheetContent
    @Environment(\.colorScheme) private var scheme
    @State private var drag: CGFloat = 0        // 下スワイプの追従量
    @State private var sheetH: CGFloat = 420    // 実測シート高（スライドアウト距離に使う）
    @State private var dismissing = false       // スワイプ閉じのスライドアウト中

    /// 0(定位置)→1(画面外)。scrim のフェードをドラッグに追従させる。
    private var dragProgress: Double { Double(min(1, max(0, drag / max(1, sheetH)))) }

    func body(content: Content) -> some View {
        let c = S8Palette.of(scheme)
        ZStack(alignment: .bottom) {
            content
            if isPresented {
                // scrim はドラッグ量に追従して薄くなる（閉じ動作と一体に見せる）
                Color.black.opacity(0.42 * (1 - dragProgress)).ignoresSafeArea()
                    .onTapGesture { dismissBySlide() }
                    .transition(.opacity)
                VStack(spacing: 0) {
                    Capsule().fill(c.lineStrong)
                        .frame(width: 36, height: 4)
                        .padding(.top, 8).padding(.bottom, 14)
                    sheetContent()
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 24)
                .padding(.bottom, 20)
                // 背景はホイール同様セーフ領域を越えて物理最下部まで張り付かせる
                .background(
                    S8TopRounded(radius: S8Radius.lg)
                        .fill(c.surface)
                        .ignoresSafeArea(.container, edges: .bottom)
                )
                // 実高を測ってスライドアウト距離に使う
                .background(
                    GeometryReader { g in
                        Color.clear
                            .onAppear { sheetH = g.size.height }
                            .onChange(of: g.size.height) { _, h in sheetH = h }
                    }
                )
                .offset(y: drag)
                // タップ（scrim）に加えて下スワイプでも閉じる
                .gesture(
                    DragGesture(minimumDistance: 8)
                        .onChanged { g in
                            guard !dismissing else { return }
                            drag = max(0, g.translation.height)
                        }
                        .onEnded { g in
                            guard !dismissing else { return }
                            if g.translation.height > 80 || g.predictedEndTranslation.height > 200 {
                                // 現在位置からそのまま画面外までスライドさせてから取り外す
                                // （以前は即 isPresented=false にしていたため、途中でアニメが切れていた）
                                dismissBySlide()
                            } else {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) { drag = 0 }
                            }
                        }
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.22), value: isPresented)
        .onChange(of: isPresented) { _, p in
            if p { drag = 0; dismissing = false }   // 再表示時に追従量をリセット
        }
    }

    /// ドラッグ位置から連続して画面外へスライドアウトし、見えなくなってから取り外す。
    private func dismissBySlide() {
        guard !dismissing else { return }
        dismissing = true
        let distance = sheetH + 80
        // 残距離に応じて時間を縮める（途中まで引いていたら短く）＝速度が連続して見える
        let remain = max(0.05, 1 - dragProgress)
        let duration = 0.24 * remain
        withAnimation(.easeIn(duration: duration)) { drag = distance }
        DispatchQueue.main.asyncAfter(deadline: .now() + duration + 0.02) {
            isPresented = false
            dismissing = false
        }
    }
}

extension View {
    func s8BottomSheet<C: View>(isPresented: Binding<Bool>, @ViewBuilder content: @escaping () -> C) -> some View {
        modifier(S8BottomSheet(isPresented: isPresented, sheetContent: content))
    }
}

// MARK: - Haptics（S8Wheel 内 private の複製を避けるためモジュール共通で提供）

enum S8HapticFB {
    static func tick() { UISelectionFeedbackGenerator().selectionChanged() }
    static func tap() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
}

// MARK: - S8Slider（連続値スライダー・iOS 標準 Slider 代替）

struct S8Slider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double = 1
    var height: CGFloat = 28
    @Environment(\.colorScheme) private var scheme
    @State private var dragging = false

    var body: some View {
        let c = S8Palette.of(scheme)
        GeometryReader { g in
            let w = max(1, g.size.width)
            let clamped = min(max(value, range.lowerBound), range.upperBound)
            let span = max(0.0001, range.upperBound - range.lowerBound)
            let frac = CGFloat((clamped - range.lowerBound) / span)
            let x = w * frac
            ZStack(alignment: .leading) {
                Capsule().fill(c.lineStrong).frame(height: 4)
                Capsule().fill(c.accent).frame(width: x, height: 4)
                Circle().fill(c.accent)
                    .overlay(Circle().stroke(c.paper, lineWidth: 2))
                    .frame(width: 18, height: 18)
                    .offset(x: x - 9)
                    .scaleEffect(dragging ? 1.1 : 1.0)
                    .animation(.spring(response: 0.2), value: dragging)
            }
            .frame(maxWidth: .infinity, minHeight: height, maxHeight: height)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        dragging = true
                        let ratio = Double(min(max(0, drag.location.x), w) / w)
                        let raw = range.lowerBound + ratio * span
                        let snapped = (raw / step).rounded() * step
                        let v = min(max(range.lowerBound, snapped), range.upperBound)
                        if v != value {
                            value = v
                            S8HapticFB.tick()
                        }
                    }
                    .onEnded { _ in dragging = false }
            )
        }
        .frame(height: height)
    }
}

// MARK: - S8Stepper（整数増減・iOS 標準 Stepper 代替）

struct S8Stepper: View {
    @Binding var value: Int
    let range: ClosedRange<Int>
    var step: Int = 1
    var unit: String = ""
    var width: CGFloat = 128
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let c = S8Palette.of(scheme)
        let canDec = value - step >= range.lowerBound
        let canInc = value + step <= range.upperBound
        HStack(spacing: 6) {
            stepBtn("−", enabled: canDec) {
                let v = max(range.lowerBound, value - step)
                if v != value { value = v; S8HapticFB.tick() }
            }
            Text("\(value)\(unit)")
                .font(S8Font.mono(14, .bold))
                .foregroundColor(c.fg1)
                .frame(maxWidth: .infinity)
            stepBtn("+", enabled: canInc) {
                let v = min(range.upperBound, value + step)
                if v != value { value = v; S8HapticFB.tick() }
            }
        }
        .frame(width: width)
    }

    private func stepBtn(_ glyph: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        let c = S8Palette.of(scheme)
        return Button(action: action) {
            Text(glyph)
                .font(S8Font.mono(16, .bold))
                .foregroundColor(enabled ? c.fg1 : c.fg3)
                .frame(width: 32, height: 32)
                .overlay(RoundedRectangle(cornerRadius: S8Radius.md).stroke(c.lineStrong, lineWidth: 1))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}

// MARK: - S8Picker（単一選択・iOS 標準 Picker 代替）

enum S8PickerStyle { case chips, sheet }

struct S8Picker<T: Hashable>: View {
    @Binding var selection: T
    let options: [(T, String)]
    var style: S8PickerStyle = .chips
    var placeholder: String = "選択"
    @State private var showSheet = false
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let c = S8Palette.of(scheme)
        Group {
            switch style {
            case .chips:
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(options.indices, id: \.self) { i in
                            let opt = options[i]
                            S8Chip(opt.1, selected: opt.0 == selection) {
                                selection = opt.0
                                S8HapticFB.tick()
                            }
                        }
                    }
                }
            case .sheet:
                Button(action: { showSheet = true }) {
                    HStack(spacing: 6) {
                        Text(currentLabel).font(S8Font.jp(15)).foregroundColor(c.fg1).lineLimit(1)
                        S8Icon(name: "chevron-down", size: 14, color: c.fg3)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .sheet(isPresented: $showSheet) {
            S8PickerSheetBody(options: options, selection: $selection, dismiss: { showSheet = false })
                .presentationDetents([.medium, .large])
                .presentationBackground(c.paper)
                .presentationDragIndicator(.visible)
        }
    }

    private var currentLabel: String {
        options.first(where: { $0.0 == selection })?.1 ?? placeholder
    }
}

private struct S8PickerSheetBody<T: Hashable>: View {
    let options: [(T, String)]
    @Binding var selection: T
    let dismiss: () -> Void
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let c = S8Palette.of(scheme)
        VStack(spacing: 0) {
            S8SectionLabel(text: "選択")
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(options.indices, id: \.self) { i in
                        let opt = options[i]
                        Button(action: {
                            selection = opt.0
                            S8HapticFB.tap()
                            dismiss()
                        }) {
                            HStack(spacing: 10) {
                                Text(opt.1).font(S8Font.jp(15)).foregroundColor(c.fg1)
                                Spacer()
                                if opt.0 == selection {
                                    S8Icon(name: "check", size: 16, color: c.accent)
                                }
                            }
                            .padding(.horizontal, 24).padding(.vertical, 15)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        if i < options.count - 1 { S8Rule() }
                    }
                }
            }
        }
        .background(c.paper.ignoresSafeArea())
    }
}

// MARK: - S8DatePicker（日付＋任意で時刻・iOS 標準 DatePicker 代替）

struct S8DatePicker: View {
    @Binding var date: Date
    var showTime: Bool = true
    var minuteStep: Int = 5
    @State private var showSheet = false
    @Environment(\.colorScheme) private var scheme

    private var summaryText: String {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "ja_JP")
        fmt.dateFormat = showTime ? "M/d(EEE) HH:mm" : "M/d(EEE)"
        return fmt.string(from: date)
    }

    var body: some View {
        let c = S8Palette.of(scheme)
        Button(action: { showSheet = true }) {
            HStack(spacing: 6) {
                Text(summaryText).font(S8Font.mono(13)).foregroundColor(c.fg1)
                S8Icon(name: "chevron-down", size: 14, color: c.fg3)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showSheet) {
            S8DatePickerSheet(date: $date, showTime: showTime, minuteStep: minuteStep, dismiss: { showSheet = false })
                .presentationDetents([.large])
                .presentationBackground(c.paper)
                .presentationDragIndicator(.visible)
        }
    }
}

private struct S8DatePickerSheet: View {
    @Binding var date: Date
    let showTime: Bool
    let minuteStep: Int
    let dismiss: () -> Void
    @State private var visibleMonth: Date
    @Environment(\.colorScheme) private var scheme

    private static var jaCalendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.locale = Locale(identifier: "ja_JP")
        c.firstWeekday = 1
        return c
    }
    private var cal: Calendar { Self.jaCalendar }

    init(date: Binding<Date>, showTime: Bool, minuteStep: Int, dismiss: @escaping () -> Void) {
        self._date = date
        self.showTime = showTime
        self.minuteStep = minuteStep
        self.dismiss = dismiss
        let comp = Self.jaCalendar.dateComponents([.year, .month], from: date.wrappedValue)
        let first = Self.jaCalendar.date(from: comp) ?? date.wrappedValue
        self._visibleMonth = State(initialValue: first)
    }

    var body: some View {
        let c = S8Palette.of(scheme)
        VStack(spacing: 0) {
            monthHeader
            S8Rule()
            weekdayRow
            dayGrid
                .padding(.horizontal, 24).padding(.top, 4)
            if showTime {
                S8SectionLabel(text: "時刻")
                timeRow
            }
            Spacer(minLength: 8)
            S8Button("決定") {
                S8HapticFB.tap()
                dismiss()
            }
            .padding(.horizontal, 24).padding(.bottom, 24)
        }
        .background(c.paper.ignoresSafeArea())
    }

    private var monthHeader: some View {
        let c = S8Palette.of(scheme)
        let title: String = {
            let f = DateFormatter()
            f.locale = Locale(identifier: "ja_JP")
            f.dateFormat = "yyyy年 M月"
            return f.string(from: visibleMonth)
        }()
        return HStack {
            S8IconButton(icon: "chevron-left") {
                if let m = cal.date(byAdding: .month, value: -1, to: visibleMonth) { visibleMonth = m }
            }
            Spacer()
            Text(title).font(S8Font.jp(15, .bold)).foregroundColor(c.fg1)
            Spacer()
            S8IconButton(icon: "chevron-right") {
                if let m = cal.date(byAdding: .month, value: 1, to: visibleMonth) { visibleMonth = m }
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
    }

    private var weekdayRow: some View {
        let c = S8Palette.of(scheme)
        let labels = ["日","月","火","水","木","金","土"]
        return HStack(spacing: 0) {
            ForEach(0..<7, id: \.self) { i in
                Text(labels[i])
                    .font(S8Font.mono(10)).tracking(1.0)
                    .foregroundColor(c.fg3)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 24).padding(.vertical, 8)
    }

    private var dayGrid: some View {
        let c = S8Palette.of(scheme)
        let cells = monthGridCells()
        let cols = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)
        return LazyVGrid(columns: cols, spacing: 4) {
            ForEach(cells.indices, id: \.self) { i in
                let cell = cells[i]
                let isSelected = cal.isDate(cell.date, inSameDayAs: date)
                let isToday = cal.isDateInToday(cell.date)
                Button(action: {
                    S8HapticFB.tick()
                    date = mergeDate(cell.date, keepingTimeFrom: date)
                }) {
                    Text("\(cal.component(.day, from: cell.date))")
                        .font(S8Font.mono(14, isSelected ? .bold : .regular))
                        .foregroundColor(isSelected ? c.onAccent : (cell.inMonth ? c.fg1 : c.fg3))
                        .frame(width: 36, height: 36)
                        .background(
                            Circle()
                                .fill(isSelected ? c.accent : Color.clear)
                        )
                        .overlay(
                            Circle().stroke((isToday && !isSelected) ? c.lineStrong : Color.clear, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var timeRow: some View {
        let hr = cal.component(.hour, from: date)
        let mn = cal.component(.minute, from: date)
        return VStack(alignment: .leading, spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(0..<24, id: \.self) { h in
                        S8Chip(String(format: "%02d", h), selected: h == hr, jp: false) {
                            date = setHour(h, minute: mn)
                            S8HapticFB.tick()
                        }
                    }
                }.padding(.horizontal, 24)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    let steps = Array(stride(from: 0, to: 60, by: minuteStep))
                    ForEach(steps, id: \.self) { m in
                        S8Chip(String(format: ":%02d", m), selected: m == mn, jp: false) {
                            date = setHour(hr, minute: m)
                            S8HapticFB.tick()
                        }
                    }
                }.padding(.horizontal, 24)
            }
        }
        .padding(.bottom, 8)
    }

    private struct DayCell { let date: Date; let inMonth: Bool }

    private func monthGridCells() -> [DayCell] {
        let comps = cal.dateComponents([.year, .month], from: visibleMonth)
        guard let first = cal.date(from: comps) else { return [] }
        let range = cal.range(of: .day, in: .month, for: first) ?? 1..<2
        let firstWeekday = cal.component(.weekday, from: first)
        let leading = (firstWeekday - cal.firstWeekday + 7) % 7
        let totalCells = ((leading + range.count + 6) / 7) * 7
        guard let gridStart = cal.date(byAdding: .day, value: -leading, to: first) else { return [] }
        var cells: [DayCell] = []
        cells.reserveCapacity(totalCells)
        for i in 0..<totalCells {
            if let d = cal.date(byAdding: .day, value: i, to: gridStart) {
                let inMonth = cal.component(.month, from: d) == cal.component(.month, from: first)
                cells.append(DayCell(date: d, inMonth: inMonth))
            }
        }
        return cells
    }

    private func mergeDate(_ newDay: Date, keepingTimeFrom old: Date) -> Date {
        let dc = cal.dateComponents([.year, .month, .day], from: newDay)
        let tc = cal.dateComponents([.hour, .minute, .second], from: old)
        var comp = DateComponents()
        comp.year = dc.year; comp.month = dc.month; comp.day = dc.day
        comp.hour = tc.hour; comp.minute = tc.minute; comp.second = tc.second
        return cal.date(from: comp) ?? old
    }

    private func setHour(_ h: Int, minute m: Int) -> Date {
        var comp = cal.dateComponents([.year, .month, .day], from: date)
        comp.hour = h; comp.minute = m; comp.second = 0
        return cal.date(from: comp) ?? date
    }
}

// MARK: - 自己チェック（primitives の丸め・月グリッド）
#if DEBUG
@discardableResult
func s8ComponentsSelfCheck() -> Bool {
    func snap(_ v: Double, in r: ClosedRange<Double>, step: Double) -> Double {
        let snapped = (v / step).rounded() * step
        return min(max(r.lowerBound, snapped), r.upperBound)
    }
    assert(snap(0.37, in: 0...1, step: 0.25) == 0.5)
    assert(snap(1.6, in: 0...5, step: 1) == 2)
    assert(snap(10, in: 0...5, step: 1) == 5)
    assert(snap(-5, in: 0...5, step: 1) == 0)

    var cal = Calendar(identifier: .gregorian)
    cal.locale = Locale(identifier: "ja_JP")
    cal.firstWeekday = 1
    let comps = DateComponents(year: 2026, month: 8, day: 1)
    if let d = cal.date(from: comps) {
        assert(cal.component(.weekday, from: d) == 7)   // 2026-08-01 は土曜
    }
    return true
}
#endif
