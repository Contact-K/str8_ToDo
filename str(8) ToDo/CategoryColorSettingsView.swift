import SwiftUI
import SwiftData

struct CategoryColorSettingsView: View {
    @Environment(\.modelContext) var modelContext
    @Environment(\.colorScheme) private var scheme
    private var c: S8Palette { S8Palette.of(scheme) }
    @Query(sort: \Category.name) var categories: [Category]

    var body: some View {
        VStack(spacing: 0) {
            S8TopBar("カテゴリ色", sub: "category colors") { EmptyView() }
            ScrollView {
                VStack(spacing: 0) {
                    S8SectionLabel(text: "カテゴリ色")
                    ForEach(Array(categories.enumerated()), id: \.element.id) { index, category in
                        HStack(spacing: 12) {
                            Text(category.name)
                                .font(S8Font.jp(15))
                                .foregroundColor(c.fg1)
                                .lineLimit(1)

                            Spacer()

                            // 現在色スウォッチ
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color(hex: category.colorHex))
                                .frame(width: 24, height: 24)

                            // プリセットhexスウォッチ群（ショップで購入した色パックも含む）
                            HStack(spacing: 8) {
                                ForEach(ShopManager.shared.availableColors, id: \.self) { rawHex in
                                    let hex = "#\(rawHex)"
                                    Button(action: {
                                        category.colorHex = hex
                                        try? modelContext.save()
                                    }) {
                                        RoundedRectangle(cornerRadius: 6)
                                            .fill(Color(hex: hex))
                                            .frame(width: 20, height: 20)
                                            .overlay(
                                                category.colorHex == hex
                                                    ? RoundedRectangle(cornerRadius: 6)
                                                        .stroke(Color.primary, lineWidth: 2)
                                                    : nil
                                            )
                                    }
                                    .buttonStyle(.borderless)
                                    .accessibilityLabel("色を変更: \(hex)")
                                }
                            }
                        }
                        .padding(.horizontal, 24)
                        .padding(.vertical, 15)

                        if index < categories.count - 1 { S8Rule() }
                    }

                    Color.clear.frame(height: 32)
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        CategoryColorSettingsView()
    }
    .modelContainer(PreviewData.container)
}
