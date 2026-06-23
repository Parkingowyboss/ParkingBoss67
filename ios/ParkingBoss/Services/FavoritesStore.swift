import Foundation

/// Stores favorite locations locally (no account required). (Roadmap Step 16.)
@MainActor
final class FavoritesStore: ObservableObject {
    @Published private(set) var favorites: [Location] = []

    private let key = "favorites.v1"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }

    func isFavorite(_ location: Location) -> Bool {
        favorites.contains { $0.id == location.id }
    }

    func toggle(_ location: Location) {
        if isFavorite(location) {
            favorites.removeAll { $0.id == location.id }
        } else {
            favorites.append(location)
        }
        save()
    }

    private func load() {
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode([Location].self, from: data) else { return }
        favorites = decoded
    }

    private func save() {
        if let data = try? JSONEncoder().encode(favorites) {
            defaults.set(data, forKey: key)
        }
    }
}
