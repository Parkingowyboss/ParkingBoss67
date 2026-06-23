import SwiftUI

/// Saved locations, available offline. (Roadmap Step 16.)
struct FavoritesScreen: View {
    @EnvironmentObject private var favorites: FavoritesStore
    @State private var selected: Location?

    var body: some View {
        NavigationStack {
            Group {
                if favorites.favorites.isEmpty {
                    ContentUnavailableView(
                        "Brak ulubionych",
                        systemImage: "heart",
                        description: Text("Dodaj miejsca przyciskiem serca, aby szybko do nich wracać.")
                    )
                } else {
                    List(favorites.favorites) { location in
                        Button { selected = location } label: {
                            HStack(spacing: 12) {
                                Image(systemName: location.type.systemImage)
                                    .font(.title3)
                                    .foregroundStyle(location.type.tint)
                                    .frame(width: 32)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(location.title).font(.body.weight(.medium))
                                    if let address = location.address {
                                        Text(address).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                    }
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Ulubione")
            .sheet(item: $selected) { LocationDetailSheet(location: $0) }
        }
    }
}
