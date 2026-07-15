// ShopModels.swift — ショップの型定義（str8_Talk/iosApp の ShopManager から抽出・スリム化）
//
// - ポイント通貨: 「⭐ pt」（内部単位）。UserDefaults に整数で保持。
// - カタログ: 背景テーマ／スロット拡張／アイコン&色パック の4カテゴリ。
// - キャップ拡張: 段階的な同シリーズアイテム（profile_slot_4, _5, _6 ...）を購入して +1 ずつ緩める。
// - iosapp との共有はしない（App Group 未使用、通貨も別勘定）。

import Foundation
import SwiftUI

// MARK: - Aquarium theme（砂紋 tint）

/// 背景砂紋の色テーマ。default 以外は購入後に選択可能。
enum AquariumTheme: String, CaseIterable, Codable {
    case `default` = "default"
    case ocean = "theme_ocean"
    case sunset = "theme_sunset"
    case sakura = "theme_sakura"
    case midnight = "theme_midnight"
    case wakatake = "theme_wakatake"
    case sumi = "theme_sumi"

    var displayName: String {
        switch self {
        case .default: return "デフォルト"
        case .ocean: return "オーシャン"
        case .sunset: return "サンセット"
        case .sakura: return "桜"
        case .midnight: return "深海"
        case .wakatake: return "若竹"
        case .sumi: return "墨"
        }
    }
}

// MARK: - Earning reason（獲得理由）

enum StarEarningReason: String {
    case taskApproved = "タスク承認"
    case weekReviewClosed = "週次締めボーナス"
    case dailyBonus = "デイリーボーナス"
    case firstLaunch = "初回起動ボーナス"
    case debug = "デバッグ"
}

// MARK: - Shop item

struct ShopItem: Identifiable {
    enum Category: String, CaseIterable {
        case background = "背景テーマ"
        case slot = "スロット拡張"
        case iconPack = "アイコンパック"
        case colorPack = "カラーパック"
    }

    let id: String
    let name: String
    let description: String
    let price: Int
    let category: Category
}

// MARK: - カタログ定義

enum ShopCatalog {

    /// 全アイテム。ShopView と ShopManager.purchase の両方が参照する唯一の真実。
    static let items: [ShopItem] = backgrounds + slots + iconPacks + colorPacks

    // 背景テーマ
    static let backgrounds: [ShopItem] = [
        .init(id: AquariumTheme.sumi.rawValue,     name: "墨",       description: "濃いめの線で締める",   price: 80,  category: .background),
        .init(id: AquariumTheme.ocean.rawValue,    name: "オーシャン", description: "藍がかった線",         price: 100, category: .background),
        .init(id: AquariumTheme.sunset.rawValue,   name: "サンセット", description: "夕暮れの茜線",         price: 100, category: .background),
        .init(id: AquariumTheme.midnight.rawValue, name: "深海",     description: "沈んだ藍",             price: 100, category: .background),
        .init(id: AquariumTheme.wakatake.rawValue, name: "若竹",     description: "淡い青緑の線",         price: 100, category: .background),
        .init(id: AquariumTheme.sakura.rawValue,   name: "桜",       description: "紅がかった線",         price: 120, category: .background),
    ]

    // スロット拡張（段階購入）
    static let slots: [ShopItem] = [
        .init(id: "profile_slot_4",  name: "プロフィール4枠目", description: "上限を3→4に",  price: 40,  category: .slot),
        .init(id: "profile_slot_5",  name: "プロフィール5枠目", description: "上限を4→5に",  price: 60,  category: .slot),
        .init(id: "profile_slot_6",  name: "プロフィール6枠目", description: "上限を5→6に",  price: 80,  category: .slot),
        .init(id: "category_slot_6", name: "カテゴリ6枠目",     description: "上限を5→6に",  price: 40,  category: .slot),
        .init(id: "category_slot_7", name: "カテゴリ7枠目",     description: "上限を6→7に",  price: 60,  category: .slot),
        .init(id: "category_slot_8", name: "カテゴリ8枠目",     description: "上限を7→8に",  price: 80,  category: .slot),
        .init(id: "category_slot_9", name: "カテゴリ9枠目",     description: "上限を8→9に",  price: 100, category: .slot),
        .init(id: "category_slot_10", name: "カテゴリ10枠目",   description: "上限を9→10に", price: 120, category: .slot),
        .init(id: "preset_slot_4",   name: "プリセット4枠目",   description: "上限を3→4に",  price: 60,  category: .slot),
        .init(id: "preset_slot_5",   name: "プリセット5枠目",   description: "上限を4→5に",  price: 80,  category: .slot),
        .init(id: "preset_slot_6",   name: "プリセット6枠目",   description: "上限を5→6に",  price: 120, category: .slot),
    ]

    // アイコンパック（既存 S8IconPreset.symbols の行単位で分割。無料は tag/star/heart/bookmark/bell/flame）
    static let iconPacks: [ShopItem] = [
        .init(id: "icon_pack_life",   name: "Life パック",   description: "book / briefcase / house / cart / fork.knife / gift",   price: 30, category: .iconPack),
        .init(id: "icon_pack_play",   name: "Play パック",   description: "music / camera / gamecontroller / tv / film / headphones", price: 30, category: .iconPack),
        .init(id: "icon_pack_move",   name: "Move パック",   description: "figure.run / dumbbell / bicycle / car / airplane / tram", price: 30, category: .iconPack),
        .init(id: "icon_pack_work",   name: "Work パック",   description: "graduationcap / pencil / paperclip / folder / doc / envelope", price: 30, category: .iconPack),
        .init(id: "icon_pack_nature", name: "Nature パック", description: "sparkles / bolt / cloud.sun / moon.stars / drop / leaf", price: 30, category: .iconPack),
    ]

    // 色パック（既存6色に追加）
    static let colorPacks: [ShopItem] = [
        .init(id: "color_pack_pastel", name: "Pastel パック", description: "6色: 淡ピンク / 水色 / 若葉 / クリーム / ラベンダー / ライラック", price: 40, category: .colorPack),
        .init(id: "color_pack_deep",   name: "Deep パック",   description: "6色: 深藍 / ワイン / 森緑 / 墨 / 銅 / 暁",                  price: 40, category: .colorPack),
    ]

    // MARK: - パックの中身定義

    /// 無料で使えるアイコン（`S8IconPreset.symbols` の1行目）。
    static let baseIcons: [String] = [
        "tag.fill", "star.fill", "heart.fill", "bookmark.fill", "bell.fill", "flame.fill"
    ]

    /// アイコンパックの id → 追加アイコンリスト。
    static let iconsByPack: [String: [String]] = [
        "icon_pack_life":   ["book.fill", "briefcase.fill", "house.fill", "cart.fill", "fork.knife", "gift.fill"],
        "icon_pack_play":   ["music.note", "camera.fill", "gamecontroller.fill", "tv.fill", "film.fill", "headphones"],
        "icon_pack_move":   ["figure.run", "dumbbell.fill", "bicycle", "car.fill", "airplane", "tram.fill"],
        "icon_pack_work":   ["graduationcap.fill", "pencil", "paperclip", "folder.fill", "doc.fill", "envelope.fill"],
        "icon_pack_nature": ["sparkles", "bolt.fill", "cloud.sun.fill", "moon.stars.fill", "drop.fill", "leaf.fill"],
    ]

    /// 無料の色（既存プリセット）。
    static let baseColors: [String] = ["4F8DFD", "34C759", "FF9500", "FF2D55", "AF52DE", "8E8E93"]

    /// 色パックの id → 追加色リスト（hex 6桁）。
    static let colorsByPack: [String: [String]] = [
        "color_pack_pastel": ["F7C6D6", "BEE3F0", "C6E7C6", "F6E4B0", "D9CBEF", "E3C6E9"],
        "color_pack_deep":   ["1E2A4A", "6B1F2E", "234436", "3A342A", "8A5A2B", "C2624B"],
    ]
}

// MARK: - 砂紋テーマ tint

/// AquariumTheme → 砂紋の線色。default は nil（palette の line を使う）。
/// 移植元 `str8_Talk/iosApp/Q1E/str8/S8Aquarium.swift:25-35` と同値。
func s8SamonTint(_ theme: AquariumTheme, isDark: Bool) -> Color? {
    switch theme {
    case .default:  return nil
    case .ocean:    return Color(s8: isDark ? 0x2C4A60 : 0xB9CFDD)
    case .sunset:   return Color(s8: isDark ? 0x5C3B22 : 0xE9C7A4)
    case .sakura:   return Color(s8: isDark ? 0x57303E : 0xEAC4D0)
    case .midnight: return Color(s8: isDark ? 0x23344E : 0x9FB0C8)
    case .wakatake: return Color(s8: isDark ? 0x2E4A38 : 0xAECDB8)
    case .sumi:     return Color(s8: isDark ? 0x4A463C : 0xA8A294)
    }
}
