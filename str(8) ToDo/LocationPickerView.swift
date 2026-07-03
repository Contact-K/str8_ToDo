import SwiftUI
import SwiftData
import MapKit

@MainActor
struct LocationPickerView: View {
    @Environment(\.modelContext) var modelContext
    @Environment(\.dismiss) var dismiss

    @Binding var place: PlaceTag?

    @State private var searchText: String = ""
    @State private var searchResults: [(name: String, coordinate: CLLocationCoordinate2D)] = []
    @State private var isSearching: Bool = false
    @State private var searchCompleter: MKLocalSearchCompleter = MKLocalSearchCompleter()

    var body: some View {
        Form {
            Section("検索") {
                TextField("住所または地名", text: $searchText)
                    .onChange(of: searchText) { old, new in
                        performSearch(new)
                    }
            }

            if isSearching {
                Section {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                }
            }

            if !searchResults.isEmpty {
                Section("候補") {
                    ForEach(Array(searchResults.enumerated()), id: \.offset) { index, result in
                        Button(action: {
                            selectLocation(name: result.name, coordinate: result.coordinate)
                        }) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(result.name)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.primary)
                            }
                        }
                    }
                }
            }

            Section {
                Button(action: {
                    place = nil
                    dismiss()
                }) {
                    HStack {
                        Image(systemName: "xmark.circle.fill")
                        Text("場所をクリア")
                    }
                    .foregroundColor(.red)
                }
            }
        }
        .navigationTitle("場所を選択")
        .navigationBarTitleDisplayMode(.inline)
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
                    let name = mapItem.name ?? mapItem.placemark.name ?? "Unknown"
                    let coordinate = mapItem.placemark.coordinate
                    return (name: name, coordinate: coordinate)
                }
            } catch {
                searchResults = []
            }
            isSearching = false
        }
    }

    private func selectLocation(name: String, coordinate: CLLocationCoordinate2D) {
        place = PlaceTag(
            name: name,
            latitude: coordinate.latitude,
            longitude: coordinate.longitude
        )
        modelContext.insert(place!)
        try? modelContext.save()
        dismiss()
    }
}

#Preview {
    NavigationStack {
        LocationPickerView(place: .constant(nil))
            .modelContainer(PreviewData.container)
    }
}
