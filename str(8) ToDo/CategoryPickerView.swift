import SwiftUI
import SwiftData

@MainActor
struct CategoryPickerView: View {
    @Environment(\.modelContext) var modelContext
    @Environment(\.dismiss) var dismiss
    @Query(sort: \Category.name) var existingCategories: [Category]

    @Binding var selection: Category?

    @State private var newCategoryName: String = ""
    @State private var newCategoryColor: String = "4F8DFD"
    @State private var newCategorySymbol: String = "tag.fill"

    private let colorPresets: [String] = ["4F8DFD", "34C759", "FF9500", "FF2D55", "AF52DE", "8E8E93"]

    var body: some View {
        Form {
            Section("既存カテゴリ") {
                if existingCategories.isEmpty {
                    Text("カテゴリなし")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(existingCategories) { cat in
                        Button(action: {
                            selection = cat
                            dismiss()
                        }) {
                            HStack {
                                Circle()
                                    .fill(Color(hex: cat.colorHex))
                                    .frame(width: 16, height: 16)
                                Text(cat.name)
                                Spacer()
                                if selection?.id == cat.id {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.blue)
                                }
                            }
                            .foregroundColor(.primary)
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }

            Section("新規カテゴリ") {
                TextField("名前", text: $newCategoryName)

                VStack(alignment: .leading, spacing: 8) {
                    Text("色を選択")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    HStack(spacing: 12) {
                        ForEach(colorPresets, id: \.self) { hex in
                            Button(action: { newCategoryColor = hex }) {
                                Circle()
                                    .fill(Color(hex: hex))
                                    .frame(width: 40, height: 40)
                                    .overlay(
                                        newCategoryColor == hex
                                            ? Circle().stroke(.black, lineWidth: 2)
                                            : nil
                                    )
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                    .padding(.vertical, 8)
                }

                TextField("SF Symbol (デフォルト: tag.fill)", text: $newCategorySymbol)

                Button(action: createNewCategory) {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                        Text("追加")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(8)
                }
                .buttonStyle(.borderless)
                .disabled(newCategoryName.trimmingCharacters(in: .whitespaces).isEmpty)
                .listRowInsets(EdgeInsets())
            }
        }
        .navigationTitle("カテゴリを選択")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func createNewCategory() {
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
