import CoreLocation
import Foundation
import MapKit

/// Drives the map screen: fetches nearby locations for the visible region and
/// applies the active type filters. (Roadmap Steps 8–9.)
@MainActor
final class MapViewModel: ObservableObject {
    @Published var locations: [Location] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    /// Selected filter group labels. Empty == show everything.
    @Published var activeFilters: Set<String> = []

    private let api: APIClient
    private var lastFetchCenter: CLLocationCoordinate2D?

    init(api: APIClient = .shared) {
        self.api = api
    }

    var selectedTypes: [LocationType]? {
        guard !activeFilters.isEmpty else { return nil }
        let groups = LocationType.filterGroups.filter { activeFilters.contains($0.label) }
        let types = groups.flatMap(\.types)
        return types.isEmpty ? nil : types
    }

    func toggleFilter(_ label: String) {
        if activeFilters.contains(label) {
            activeFilters.remove(label)
        } else {
            activeFilters.insert(label)
        }
    }

    /// Locations after applying client-side type filtering.
    var visibleLocations: [Location] {
        guard let types = selectedTypes else { return locations }
        let set = Set(types)
        return locations.filter { set.contains($0.type) }
    }

    func load(center: CLLocationCoordinate2D, radius: Double) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            locations = try await api.nearby(center: center, radius: radius, types: selectedTypes)
            lastFetchCenter = center
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// Re-fetch only if the map has moved meaningfully from the last fetch.
    func loadIfMoved(center: CLLocationCoordinate2D, radius: Double, threshold: Double = 400) async {
        if let last = lastFetchCenter {
            let moved = CLLocation(latitude: last.latitude, longitude: last.longitude)
                .distance(from: CLLocation(latitude: center.latitude, longitude: center.longitude))
            if moved < threshold { return }
        }
        await load(center: center, radius: radius)
    }
}
