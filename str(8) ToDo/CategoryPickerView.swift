import SwiftUI
import SwiftData

/// str(8) 標準のアイコンプリセット（36 個）。カテゴリ・プロフィール双方で共用。
enum S8IconPreset {
    static let symbols: [String] = [
        "tag.fill", "star.fill", "heart.fill", "bookmark.fill", "bell.fill", "flame.fill",
        "book.fill", "briefcase.fill", "house.fill", "cart.fill", "fork.knife", "gift.fill",
        "music.note", "camera.fill", "gamecontroller.fill", "tv.fill", "film.fill", "headphones",
        "figure.run", "dumbbell.fill", "bicycle", "car.fill", "airplane", "tram.fill",
        "graduationcap.fill", "pencil", "paperclip", "folder.fill", "doc.fill", "envelope.fill",
        "sparkles", "bolt.fill", "cloud.sun.fill", "moon.stars.fill", "drop.fill", "leaf.fill"
    ]
}

@MainActor
struct CategoryPickerView: View {
    @Environment(\.modelContext) var modelContext
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) private var scheme
    private var c: S8Palette { S8Palette.of(scheme) }
    @Query(sort: \Category.name) var existingCategories: [Category]

    @Binding var selection: Category?

    @State private var newCategoryName: String = ""
    @State private var newCategoryColor: String = "4F8DFD"
    @State private var newCategorySymbol: String = "tag.fill"

    // ShopManager.availableIcons / availableColors を購読するため、参照時に都度取得。
    private var colorPresets: [String] { ShopManager.shared.availableColors }
    private var iconPresets: [String] { ShopManager.shared.availableIcons }
    private let iconColumns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 6)

    var body: some View {
        let c = self.c
        ScrollView {
            VStack(spacing: 0) {
                S8SectionLabel(text: "既存カテゴリ")
                if existingCategories.isEmpty {
                    HStack(spacing: 14) {
                        S8Icon(name: "info", size: 16, color: c.fg3)
                        Text("カテゴリなし").font(S8Font.jp(13)).foregroundColor(c.fg3)
                        Spacer()
                    }
                    .padding(.horizontal, 24).padding(.vertical, 15)
                } else {
                    ForEach(Array(existingCategories.enumerated()), id: \.element.id) { i, cat in
                        S8SetRow(icon: cat.symbolName, label: cat.name, trailing: {
                            HStack(spacing: 8) {
                                Circle().fill(Color(hex: cat.colorHex)).frame(width: 12, height: 12)
                                if selection?.id == cat.id {
                                    S8Icon(name: "check", size: 16, color: c.accent)
                                }
                            }
                        }, onTap: {
                            selection = cat
                            dismiss()
                        })
                        if i < existingCategories.count - 1 { S8Rule() }
                    }
                }

                S8SectionLabel(text: "新規カテゴリ")
                VStack(alignment: .leading, spacing: 12) {
                    S8Field(placeholder: "名前", text: $newCategoryName)

                    // アイコンをグリッドから選択。アクセントカラーで tint。
                    Text("アイコン")
                        .font(S8Font.mono(10)).tracking(1.4).foregroundColor(c.fg3)
                    LazyVGrid(columns: iconColumns, spacing: 10) {
                        ForEach(iconPresets, id: \.self) { sym in
                            let isSelected = newCategorySymbol == sym
                            Button(action: { newCategorySymbol = sym }) {
                                Image(systemName: sym)
                                    .font(.system(size: 20))
                                    .foregroundStyle(isSelected ? c.onAccent : c.fg1)
                                    .frame(width: 40, height: 40)
                                    .background(
                                        RoundedRectangle(cornerRadius: S8Radius.md)
                                            .fill(isSelected ? c.accent : c.surface)
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: S8Radius.md)
                                            .stroke(isSelected ? c.accent : c.lineStrong, lineWidth: 1)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    // 色プリセット。選択中はダブルリング。
                    Text("色")
                        .font(S8Font.mono(10)).tracking(1.4).foregroundColor(c.fg3)
                    HStack(spacing: 12) {
                        ForEach(colorPresets, id: \.self) { hex in
                            Button(action: { newCategoryColor = hex }) {
                                ZStack {
                                    Circle().fill(Color(hex: hex))
                                    if newCategoryColor == hex {
                                        Circle().stroke(c.fg1, lineWidth: 2).padding(-3)
                                        S8Icon(name: "check", size: 13, color: .white)
                                    }
                                }
                                .frame(width: 32, height: 32)
                                .contentShape(Circle())
                            }
                            .buttonStyle(.plain)
                        }
                        Spacer()
                    }

                    let capReached = existingCategories.count >= ShopManager.shared.categoryCap
                    S8Button("追加", icon: "plus", variant: .primary,
                             enabled: !newCategoryName.trimmingCharacters(in: .whitespaces).isEmpty && !capReached,
                             action: createNewCategory)
                        .padding(.top, 4)
                    if capReached {
                        Text("上限（\(ShopManager.shared.categoryCap)）に達しています。ショップで枠を追加できます")
                            .font(S8Font.jp(11)).foregroundColor(c.fg3)
                    }
                }
                .padding(.horizontal, 24).padding(.vertical, 12)

                Color.clear.frame(height: 32)
            }
        }
        .background(c.paper.ignoresSafeArea())
        .navigationTitle("カテゴリを選択")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private func createNewCategory() {
        guard existingCategories.count < ShopManager.shared.categoryCap else { return }
        let newCat = Category(
            name: newCategoryName.trimmingCharacters(in: .whitespaces),
            colorHex: newCategoryColor,
            symbolName: newCategorySymbol.isEmpty ? "tag.fill" : newCategorySymbol
        )
        modelContext.insert(newCat)
        try? modelContext.save()
        selection = newCat
        dismiss()
    }
}

#Preview {
    NavigationStack {
        CategoryPickerView(selection: .constant(nil))
            .modelContainer(PreviewData.container)
    }
}
