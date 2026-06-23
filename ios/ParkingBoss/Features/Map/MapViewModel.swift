import CoreLocation
import Foundation
import MapKit

/// Drives the map screen: fetches nearby locations for the visible region and
/// applies the active type filters. (Roadmap Steps 8–9.)
@MainActor
final class MapViewModel: ObservableObject {
    @Published var locations: [Location] = []
    /// Individual stalls in the current viewport (only when zoomed in).
    @Published var spaces: [ParkingSpace] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    /// Stalls render only once the map is zoomed in past this span (~1.3 km tall).
    static let spacesZoomThreshold = 0.012
    /// Backend rejects bboxes larger than this per side; keep requests under it.
    private static let maxBboxDeg = 0.055

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

    /// Whether individual stalls should be shown for this region.
    func shouldShowSpaces(for region: MKCoordinateRegion) -> Bool {
        region.span.latitudeDelta <= Self.spacesZoomThreshold
    }

    /// Load stalls for the visible rectangle; clears them when zoomed out.
    func loadSpaces(for region: MKCoordinateRegion) async {
        guard shouldShowSpaces(for: region) else {
            if !spaces.isEmpty { spaces = [] }
            return
        }
        // Build a bbox from the region, clamped to the backend's max side length.
        let halfLat = min(region.span.latitudeDelta / 2, Self.maxBboxDeg / 2)
        let halfLng = min(region.span.longitudeDelta / 2, Self.maxBboxDeg / 2)
        let c = region.center
        let bbox = (
            minLng: c.longitude - halfLng,
            minLat: c.latitude - halfLat,
            maxLng: c.longitude + halfLng,
            maxLat: c.latitude + halfLat
        )
        do {
            spaces = try await api.spaces(bbox: bbox)
        } catch {
            // Non-fatal: keep whatever stalls we already have.
        }
    }

    /// Replace a stall in place after a report updates its status.
    func apply(_ updated: ParkingSpace) {
        if let i = spaces.firstIndex(where: { $0.id == updated.id }) {
            spaces[i] = updated
        }
    }
}
