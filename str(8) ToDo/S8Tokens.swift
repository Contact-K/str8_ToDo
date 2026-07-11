// S8Tokens.swift — str(8) デザインシステム「直線 / PLAIN」のトークン（SwiftUI 版）
// design/str8_Talk_handoff の colors_and_type.css をそのまま移植。
// フォントは実機安全のため当面 system fallback（Hanken Grotesk / Zen Kaku / Space Mono は後差し可）。

import SwiftUI

extension Color {
    /// 0xRRGGBB の 16 進から生成。
    init(s8 hex: UInt32) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8) & 0xFF) / 255.0
        let b = Double(hex & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b)
    }
}

/// 2 つの 16 進色を t (0=a, 1=b) で混合。アクセント派生色の生成に使う。
private func s8Mix(_ a: UInt32, _ b: UInt32, _ t: Double) -> UInt32 {
    func ch(_ x: UInt32, _ y: UInt32) -> UInt32 {
        let v = Double(x) * (1 - t) + Double(y) * t
        return UInt32(max(0, min(255, v.rounded())))
    }
    return (ch((a >> 16) & 0xFF, (b >> 16) & 0xFF) << 16)
         | (ch((a >> 8) & 0xFF, (b >> 8) & 0xFF) << 8)
         | ch(a & 0xFF, b & 0xFF)
}

// MARK: - アクセントカラー（無料で選択可・項目 R3-④）
//
// ベース色 1 つから light/dark の accent / accentInk / accentWash / onAccent を派生する。
// 既存の「砂紋の色テーマ」（ShopManager.AquariumTheme）はショップに残置（別機能）。

enum S8Accent: String, CaseIterable, Identifiable {
    case anzu       // 杏（既定・従来色）
    case yamabuki   // 山吹 RGB(203,143,26)
    case matsu      // 松葉 RGB(67,89,72)
    case ai         // 藍   RGB(52,73,105)
    case benigara   // 紅殻 RGB(165,80,57)
    case sumire     // 菫（追加）
    case sakura     // 桜鼠（追加）

    var id: String { rawValue }

    var name: String {
        switch self {
        case .anzu: return "杏"
        case .yamabuki: return "山吹"
        case .matsu: return "松葉"
        case .ai: return "藍"
        case .benigara: return "紅殻"
        case .sumire: return "菫"
        case .sakura: return "桜鼠"
        }
    }

    /// ベース色（light の accent そのもの）。
    var base: UInt32 {
        switch self {
        case .anzu: return 0xDC8B28
        case .yamabuki: return 0xCB8F1A
        case .matsu: return 0x435948
        case .ai: return 0x344969
        case .benigara: return 0xA55039
        case .sumire: return 0x6B5280
        case .sakura: return 0xB56C82
        }
    }

    /// スウォッチ表示用。
    var color: Color { Color(s8: base) }
}

/// 紙 & 墨パレット（杏アクセント）。light / dark を `of(_:)` で切替。
struct S8Palette {
    let paper, surface, surface2: Color
    let fg1, fg2, fg3, fgInverse: Color
    let line, lineStrong: Color
    let accent, accentInk, accentWash, onAccent: Color
    let ok, okWash, warn, danger, dangerWash, info, infoWash: Color
    let isDark: Bool

    static let light = S8Palette(
        paper: Color(s8: 0xF4F2EA), surface: Color(s8: 0xFBFAF5), surface2: Color(s8: 0xEDEAE0),
        fg1: Color(s8: 0x1F1E1A), fg2: Color(s8: 0x46443E), fg3: Color(s8: 0x8A877C), fgInverse: Color(s8: 0xF4F2EA),
        line: Color(s8: 0xE2DED2), lineStrong: Color(s8: 0xC9C4B5),
        accent: Color(s8: 0xDC8B28), accentInk: Color(s8: 0xB06D17), accentWash: Color(s8: 0xF8EBD0), onAccent: Color(s8: 0x2A1E0A),
        ok: Color(s8: 0x3D5A47), okWash: Color(s8: 0xE2EAE1), warn: Color(s8: 0xB57A2A),
        danger: Color(s8: 0xB24A33), dangerWash: Color(s8: 0xF3E0DA), info: Color(s8: 0x2E4A6B), infoWash: Color(s8: 0xE0E6EE),
        isDark: false
    )

    static let dark = S8Palette(
        paper: Color(s8: 0x15140F), surface: Color(s8: 0x1E1C16), surface2: Color(s8: 0x100F0B),
        fg1: Color(s8: 0xF1EFE6), fg2: Color(s8: 0xB8B5A8), fg3: Color(s8: 0x7C7A6F), fgInverse: Color(s8: 0x15140F),
        line: Color(s8: 0x322F26), lineStrong: Color(s8: 0x46422F),
        accent: Color(s8: 0xEDA948), accentInk: Color(s8: 0xF3BB69), accentWash: Color(s8: 0x2E2515), onAccent: Color(s8: 0x1A1407),
        ok: Color(s8: 0x6E9379), okWash: Color(s8: 0x1C2620), warn: Color(s8: 0xD69A45),
        danger: Color(s8: 0xD2715A), dangerWash: Color(s8: 0x2A1B16), info: Color(s8: 0x6E8CB0), infoWash: Color(s8: 0x161E28),
        isDark: true
    )

    /// 現在のアクセント選択（設定で変更・"s8_accent" に永続。S8Root が起動時/変更時に設定する）。
    /// メインスレッドからのみ触る前提の単純なグローバル。
    nonisolated(unsafe) static var currentAccent: S8Accent = .anzu

    static func of(_ scheme: ColorScheme) -> S8Palette {
        let base = scheme == .dark ? dark : light
        // 既定の杏はオリジナルの手調整値をそのまま使う
        guard currentAccent != .anzu else { return base }
        return base.applyingAccent(currentAccent, isDark: scheme == .dark)
    }

    /// ベース色 1 つからアクセント 4 色を派生して差し替えたパレットを返す。
    func applyingAccent(_ a: S8Accent, isDark: Bool) -> S8Palette {
        let b = a.base
        let accent: UInt32, ink: UInt32, wash: UInt32, on: UInt32
        if isDark {
            accent = s8Mix(b, 0xFFFFFF, 0.22)   // 暗所では少し持ち上げる
            ink    = s8Mix(b, 0xFFFFFF, 0.40)
            wash   = s8Mix(b, 0x15140F, 0.82)   // ほぼ紙（dark）に寄せた淡色
            on     = s8Mix(b, 0x000000, 0.82)
        } else {
            accent = b
            ink    = s8Mix(b, 0x000000, 0.22)
            wash   = s8Mix(b, 0xF4F2EA, 0.82)   // ほぼ紙（light）に寄せた淡色
            on     = s8Mix(b, 0x000000, 0.80)
        }
        return S8Palette(
            paper: paper, surface: surface, surface2: surface2,
            fg1: fg1, fg2: fg2, fg3: fg3, fgInverse: fgInverse,
            line: line, lineStrong: lineStrong,
            accent: Color(s8: accent), accentInk: Color(s8: ink),
            accentWash: Color(s8: wash), onAccent: Color(s8: on),
            ok: ok, okWash: okWash, warn: warn,
            danger: danger, dangerWash: dangerWash, info: info, infoWash: infoWash,
            isDark: isDark
        )
    }
}

/// Environment 経由で `@Environment(\.s8) var c` のように使えるようにする。
private struct S8PaletteKey: EnvironmentKey {
    static let defaultValue: S8Palette = .light
}
extension EnvironmentValues {
    var s8: S8Palette {
        get { self[S8PaletteKey.self] }
        set { self[S8PaletteKey.self] = newValue }
    }
}

/// 余白（4px base）。
enum S8Space {
    static let s1: CGFloat = 4
    static let s2: CGFloat = 8
    static let s3: CGFloat = 12
    static let s4: CGFloat = 16
    static let s5: CGFloat = 24
    static let s6: CGFloat = 32
    static let s7: CGFloat = 48
    static let s8: CGFloat = 64
    static let s9: CGFloat = 96
}

/// 角丸（最小・直線寄り）。
enum S8Radius {
    static let sm: CGFloat = 2
    static let md: CGFloat = 4
    static let lg: CGFloat = 8
    static let pill: CGFloat = 999
}

/// タイポ。意匠は Hanken Grotesk(sans) / Zen Kaku(jp) / Space Mono(mono)。当面 system fallback。
enum S8Font {
    static func sans(_ size: CGFloat, _ weight: Font.Weight = .medium) -> Font { .system(size: size, weight: weight) }
    static func jp(_ size: CGFloat, _ weight: Font.Weight = .medium) -> Font { .system(size: size, weight: weight) }
    static func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font { .system(size: size, weight: weight, design: .monospaced) }
}
