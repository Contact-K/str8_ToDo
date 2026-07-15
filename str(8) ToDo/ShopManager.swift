// ShopManager.swift — ポイント残高・購入・キャップ計算の中央管理。
//
// - シングルトン `ShopManager.shared`。ContentView が `@State private var shop = ShopManager.shared`
//   のように保持すると @Observable の変更で子ビューが再描画される。
// - 通貨は UserDefaults の Int スカラー（App Group を使わないので端末ローカル）。
// - 履歴（StarTransaction）は今回はまだ持たない。必要なら後で移植元と同じ SwiftData 分離コンテナを追加。
// - iosapp との pt 共有・IAP 連携なし。

import Foundation
import SwiftUI

@MainActor
@Observable
final class ShopManager {
    static let shared = ShopManager()

    // MARK: - 永続状態

    private(set) var starBalance: Int = 0
    private(set) var purchasedItems: Set<String> = []
    private(set) var lastDailyBonusDate: Date?
    private(set) var currentTheme: AquariumTheme = .default

    // MARK: - UserDefaults keys

    private enum K {
        static let balance = "shop.starBalance"
        static let purchased = "shop.purchasedItems"
        static let lastDaily = "shop.lastDailyBonus"
        static let theme = "shop.currentTheme"
        static let firstLaunch = "shop.firstLaunchBonusGiven"
    }

    private init() {
        load()
    }

    // MARK: - Load / Save

    private func load() {
        let d = UserDefaults.standard
        starBalance = d.integer(forKey: K.balance)
        if let arr = d.stringArray(forKey: K.purchased) { purchasedItems = Set(arr) }
        lastDailyBonusDate = d.object(forKey: K.lastDaily) as? Date
        if let raw = d.string(forKey: K.theme), let t = AquariumTheme(rawValue: raw) {
            currentTheme = t
        }
        // 初回起動ボーナス
        if !d.bool(forKey: K.firstLaunch) {
            earn(.firstLaunch, amount: 50)
            d.set(true, forKey: K.firstLaunch)
        }
    }

    private func saveBalance() {
        let d = UserDefaults.standard
        d.set(starBalance, forKey: K.balance)
        d.set(Array(purchasedItems), forKey: K.purchased)
    }

    // MARK: - Earn / Spend

    /// ポイント獲得。amount 省略時は reason から既定量を引く。
    func earn(_ reason: StarEarningReason, amount: Int? = nil) {
        let n = amount ?? defaultAmount(for: reason)
        guard n > 0 else { return }
        starBalance += n
        saveBalance()
        #if DEBUG
        print("⭐ +\(n) pt: \(reason.rawValue) (残高: \(starBalance))")
        #endif
    }

    private func defaultAmount(for reason: StarEarningReason) -> Int {
        switch reason {
        case .taskApproved: return 1
        case .weekReviewClosed: return 5
        case .dailyBonus: return 10
        case .firstLaunch: return 50
        case .debug: return 100
        }
    }

    // MARK: - 購入

    /// 購入試行。成功時 true。失敗ケース: 不明 id / 所有済 / 残高不足。
    @discardableResult
    func purchase(_ itemID: String) -> Bool {
        guard let item = ShopCatalog.items.first(where: { $0.id == itemID }) else { return false }
        guard !purchasedItems.contains(itemID) else { return false }
        guard starBalance >= item.price else { return false }

        starBalance -= item.price
        purchasedItems.insert(itemID)
        saveBalance()

        #if DEBUG
        print("🛒 購入: \(item.name) (-\(item.price)pt, 残高 \(starBalance))")
        #endif
        return true
    }

    func isPurchased(_ itemID: String) -> Bool {
        purchasedItems.contains(itemID)
    }

    // MARK: - デイリーボーナス

    var canClaimDailyBonus: Bool {
        guard let last = lastDailyBonusDate else { return true }
        return !Calendar.current.isDate(last, inSameDayAs: .now)
    }

    @discardableResult
    func claimDailyBonus() -> Bool {
        guard canClaimDailyBonus else { return false }
        lastDailyBonusDate = .now
        UserDefaults.standard.set(lastDailyBonusDate, forKey: K.lastDaily)
        earn(.dailyBonus)
        return true
    }

    // MARK: - テーマ選択

    /// テーマ変更（購入済 or default のみ）。
    func setTheme(_ theme: AquariumTheme) {
        guard theme == .default || purchasedItems.contains(theme.rawValue) else { return }
        currentTheme = theme
        UserDefaults.standard.set(theme.rawValue, forKey: K.theme)
    }

    /// 現在の砂紋 tint（S8SamonPaper に渡す）。
    func currentTint(isDark: Bool) -> Color? {
        s8SamonTint(currentTheme, isDark: isDark)
    }

    // MARK: - キャップ

    var profileCap: Int { 3 + purchasedSlotCount(prefix: "profile_slot_") }
    var categoryCap: Int { 5 + purchasedSlotCount(prefix: "category_slot_") }
    var presetCap: Int { min(6, 3 + purchasedSlotCount(prefix: "preset_slot_")) }

    private func purchasedSlotCount(prefix: String) -> Int {
        purchasedItems.filter { $0.hasPrefix(prefix) }.count
    }

    // MARK: - 動的パレット

    var availableIcons: [String] {
        var out = ShopCatalog.baseIcons
        for (packID, icons) in ShopCatalog.iconsByPack where purchasedItems.contains(packID) {
            out.append(contentsOf: icons)
        }
        return out
    }

    var availableColors: [String] {
        var out = ShopCatalog.baseColors
        for (packID, colors) in ShopCatalog.colorsByPack where purchasedItems.contains(packID) {
            out.append(contentsOf: colors)
        }
        return out
    }

    // MARK: - Debug

    #if DEBUG
    /// 開発用: デバッグから +N pt。
    func debugGrant(_ n: Int) {
        starBalance += n
        saveBalance()
    }
    #endif
}
