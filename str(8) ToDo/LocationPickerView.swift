import SwiftUI
import SwiftData
import MapKit

/// 場所選択ピッカー。EventComposerView の「どこ」フォーカスシートから contentContainer 直下に
/// 埋め込まれるため、独自の NavigationStack / ヘッダは持たない。UI は S8 デザインシステム準拠。
@MainActor
struct LocationPickerView: View {
    @Environment(\.modelContext) var modelContext
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) private var scheme
    private var c: S8Palette { S8Palette.of(scheme) }

    @Binding var place: PlaceTag?

    @State private var searchText: String = ""
    @State private var searchResults: [(name: String, coordinate: CLLocationCoordinate2D)] = []
    @State private var isSearching: Bool = false

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                if let current = place {
                    S8SectionLabel(text: "現在の場所")
                    S8SetRow(icon: "map-pin", label: current.name, trailing: {
                        S8Icon(name: "check", size: 16, color: c.accent)
                    })
                }

                S8SectionLabel(text: "検索")
                VStack(alignment: .leading, spacing: 0) {
                    S8Field(placeholder: "住所または地名（例: 新宿駅 / 大学図書館）", text: $searchText)
                        .padding(.horizontal, 24).padding(.vertical, 8)
                        .onChange(of: searchText) { _, new in performSearch(new) }
                    if isSearching {
                        HStack(spacing: 10) {
                            ProgressView().scaleEffect(0.8)
                            Text("検索中...").font(S8Font.jp(12)).foregroundColor(c.fg3)
                            Spacer()
                        }
                        .padding(.horizontal, 24).padding(.vertical, 10)
                    }
                }

                if !searchResults.isEmpty {
                    S8SectionLabel(text: "候補")
                    ForEach(Array(searchResults.enumerated()), id: \.offset) { i, result in
                        S8SetRow(icon: "map-pin", label: result.name, trailing: {
                            S8Icon(name: "chevron-right", size: 14, color: c.fg3)
                        }, onTap: {
                            selectLocation(name: result.name, coordinate: result.coordinate)
                        })
                        if i < searchResults.count - 1 { S8Rule() }
                    }
                }

                if place != nil {
                    S8SectionLabel(text: "操作")
                    S8SetRow(icon: "x", label: "場所をクリア", trailing: { EmptyView() }, onTap: {
                        place = nil
                    })
                }

                Color.clear.frame(height: 24)
            }
        }
    }

    private func performSearch(_ query: String) {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else {
            searchResults = []
            return
        }

        isSearching = true
        Task {
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = query
            let search = MKLocalSearch(request: request)

            do {
                let response = try await search.start()
                searchResults = response.mapItems.compactMap { mapItem in
                    let name = mapItem.name ?? mapItem.address?.shortAddress ?? "Unknown"
                    let coordinate = mapItem.location.coordinate
                    return (name: name, coordinate: coordinate)
                }
            } catch {
                searchResults = []
            }
            isSearching = false
        }
    }

    private func selectLocation(name: String, coordinate: CLLocationCoordinate2D) {
        let tag = PlaceTag(
            name: name,
            latitude: coordinate.latitude,
            longitude: coordinate.longitude
        )
        modelContext.insert(tag)
        try? modelContext.save()
        place = tag
        dismiss()
    }
}

#Preview {
    LocationPickerView(place: .constant(nil))
        .modelContainer(PreviewData.container)
}
