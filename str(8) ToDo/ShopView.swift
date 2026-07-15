// ShopView.swift — ⭐pt でカスタマイズ・拡張を購入する画面。ホイール7つ目のタブ。
//
// 構造: S8TopBar → 残高カード → デイリーボーナス → 背景テーマ選択 → セクション別カタログ
// 背景の砂紋は ContentView 側でグローバルに敷いているので、ここは透過。

import SwiftUI

struct ShopView: View {
    @Environment(\.colorScheme) private var scheme
    private var c: S8Palette { S8Palette.of(scheme) }
    /// @Observable の再描画を確実に受けるためインスタンスを保持。
    @State private var shop = ShopManager.shared

    // MARK: - DEBUG Konami コード（↑↑↓↓←→←→タップタップ で +100pt）
    #if DEBUG
    private enum KonamiInput { case up, down, left, right, tap }
    private static let konamiSequence: [KonamiInput] = [.up, .up, .down, .down, .left, .right, .left, .right, .tap, .tap]
    @State private var konamiProgress: Int = 0
    private func konamiIngest(_ input: KonamiInput) {
        let expected = Self.konamiSequence[konamiProgress]
        if input == expected {
            konamiProgress += 1
            if konamiProgress >= Self.konamiSequence.count {
                konamiProgress = 0
                shop.debugGrant(100)
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            }
        } else {
            // 途中失敗: 最初の入力に一致するなら 1 から再スタート、そうでなければリセット
            konamiProgress = (input == Self.konamiSequence[0]) ? 1 : 0
        }
    }
    #endif

    var body: some View {
        let c = self.c
        VStack(spacing: 0) {
            S8TopBar("ショップ", sub: "unlock caps · themes") {
                HStack(spacing: 4) {
                    Text("⭐").font(.system(size: 13))
                    Text("\(shop.starBalance)")
                        .font(S8Font.mono(14, .bold)).foregroundColor(c.accentInk)
                    Text("pt").font(S8Font.mono(9)).tracking(1.2).foregroundColor(c.fg3)
                }
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(c.accentWash)
                .clipShape(Capsule())
            }

            ScrollView {
                VStack(spacing: 0) {
                    balanceCard
                        .padding(.horizontal, 24).padding(.top, 8)

                    if shop.canClaimDailyBonus {
                        dailyBonusButton
                            .padding(.horizontal, 24).padding(.top, 12)
                    }

                    // 現在テーマ（購入済みから選択）
                    themePicker
                        .padding(.top, 22)

                    ForEach(ShopItem.Category.allCases, id: \.self) { cat in
                        section(for: cat)
                            .padding(.top, 22)
                    }

                    Color.clear.frame(height: 40)
                }
            }
        }
    }

    // MARK: - 残高カード

    private var balanceCard: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(c.accentWash)
                Text("⭐").font(.system(size: 28))
            }
            .frame(width: 56, height: 56)
            VStack(alignment: .leading, spacing: 2) {
                Text("残高").font(S8Font.mono(9)).tracking(1.4).foregroundColor(c.fg3)
                HStack(alignment: .lastTextBaseline, spacing: 3) {
                    Text("\(shop.starBalance)")
                        .font(S8Font.mono(30, .bold)).foregroundColor(c.fg1)
                    Text("pt").font(S8Font.mono(12)).foregroundColor(c.fg3)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("承認 = +1pt").font(S8Font.jp(11)).foregroundColor(c.fg3)
                Text("週次締め = +5pt").font(S8Font.jp(11)).foregroundColor(c.fg3)
            }
        }
        .padding(14)
        .background(c.surface)
        .overlay(RoundedRectangle(cornerRadius: S8Radius.md).stroke(c.lineStrong, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: S8Radius.md))
        .contentShape(Rectangle())
        #if DEBUG
        // デバッグ用 Konami: ↑↑↓↓←→←→タップタップ で +100pt（Release では無効）。
        // ScrollView 内のドラッグ競合を避けるため highPriorityGesture で優先。
        .highPriorityGesture(
            DragGesture(minimumDistance: 0)
                .onEnded { g in
                    let w = g.translation.width
                    let h = g.translation.height
                    let mag = max(abs(w), abs(h))
                    if mag < 15 {
                        konamiIngest(.tap)
                    } else if abs(h) > abs(w) {
                        konamiIngest(h > 0 ? .down : .up)
                    } else {
                        konamiIngest(w > 0 ? .right : .left)
                    }
                }
        )
        #endif
    }

    // MARK: - デイリーボーナス

    private var dailyBonusButton: some View {
        S8Button("今日のボーナス +10pt", icon: "gift", variant: .primary, fillWidth: true, action: {
            _ = shop.claimDailyBonus()
        })
    }

    // MARK: - 背景テーマ選択

    private var themePicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionCap("BACKGROUND", jp: "現在の背景（購入済のみ選択可）")
                .padding(.horizontal, 24)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(AquariumTheme.allCases, id: \.self) { theme in
                        themeChip(theme)
                    }
                }
                .padding(.horizontal, 24)
            }
        }
    }

    private func themeChip(_ theme: AquariumTheme) -> some View {
        let isSelected = shop.currentTheme == theme
        let isAvailable = theme == .default || shop.isPurchased(theme.rawValue)
        let tint = s8SamonTint(theme, isDark: scheme == .dark) ?? c.lineStrong
        return Button(action: {
            if isAvailable { shop.setTheme(theme) }
        }) {
            VStack(spacing: 4) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8).fill(c.surface)
                    RoundedRectangle(cornerRadius: 8).stroke(tint, lineWidth: 2)
                    if !isAvailable {
                        Image(systemName: "lock.fill").foregroundColor(c.fg3).font(.system(size: 14))
                    }
                }
                .frame(width: 56, height: 40)
                Text(theme.displayName)
                    .font(S8Font.jp(10, isSelected ? .bold : .regular))
                    .foregroundColor(isAvailable ? (isSelected ? c.accent : c.fg2) : c.fg3)
            }
        }
        .buttonStyle(.plain)
        .disabled(!isAvailable)
    }

    // MARK: - カテゴリ別セクション

    private func section(for category: ShopItem.Category) -> some View {
        let items = ShopCatalog.items.filter { $0.category == category }
        return VStack(spacing: 0) {
            sectionCap(category.rawValue.uppercased(), jp: category.rawValue)
                .padding(.horizontal, 24).padding(.bottom, 4)
            ForEach(items) { item in
                itemRow(item)
                S8Rule()
            }
        }
    }

    private func itemRow(_ item: ShopItem) -> some View {
        let owned = shop.isPurchased(item.id)
        let affordable = shop.starBalance >= item.price
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(item.name).font(S8Font.jp(14, .bold)).foregroundColor(c.fg1)
                Text(item.description).font(S8Font.jp(11)).foregroundColor(c.fg3)
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
            if owned {
                Text("所有済").font(S8Font.mono(10, .bold)).tracking(1.2)
                    .foregroundColor(c.fg3)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(c.surface2)
                    .clipShape(Capsule())
            } else {
                Button(action: { _ = shop.purchase(item.id) }) {
                    Text("\(item.price)pt")
                        .font(S8Font.mono(12, .bold))
                        .foregroundColor(affordable ? c.onAccent : c.fg3)
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(affordable ? c.accent : c.surface2)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(!affordable)
            }
        }
        .padding(.horizontal, 24).padding(.vertical, 12)
    }

    private func sectionCap(_ tag: String, jp: String) -> some View {
        HStack(spacing: 10) {
            Text(tag).font(S8Font.mono(10)).tracking(1.6).foregroundColor(c.fg3)
            Text(jp).font(S8Font.jp(13, .medium)).foregroundColor(c.fg2)
            S8Rule()
        }
    }
}

#Preview {
    ShopView()
}
