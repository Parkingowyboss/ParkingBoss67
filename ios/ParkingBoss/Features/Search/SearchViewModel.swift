import Foundation
import MapKit

/// Powers the search sheet: named places come from our backend, address
/// suggestions from Apple's MKLocalSearchCompleter. (Roadmap Step 14.)
@MainActor
final class SearchViewModel: NSObject, ObservableObject {
    @Published var placeResults: [Location] = []
    @Published var addressResults: [MKLocalSearchCompletion] = []

    private let api: APIClient
    private let completer = MKLocalSearchCompleter()
    private var searchTask: Task<Void, Never>?

    init(api: APIClient = .shared) {
        self.api = api
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest]
        completer.region = MKCoordinateRegion(
            center: LocationManager.warsaw,
            span: MKCoordinateSpan(latitudeDelta: 0.4, longitudeDelta: 0.4)
        )
    }

    func update(query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        completer.queryFragment = trimmed
        searchTask?.cancel()

        guard trimmed.count >= 2 else {
            placeResults = []
            return
        }
        searchTask = Task {
            // Debounce keystrokes.
            try? await Task.sleep(nanoseconds: 250_000_000)
            if Task.isCancelled { return }
            let results = (try? await api.search(query: trimmed)) ?? []
            if !Task.isCancelled { placeResults = results }
        }
    }

    /// Resolve an address suggestion to a coordinate.
    func resolve(_ completion: MKLocalSearchCompletion) async -> CLLocationCoordinate2D? {
        let request = MKLocalSearch.Request(completion: completion)
        let response = try? await MKLocalSearch(request: request).start()
        return response?.mapItems.first?.placemark.coordinate
    }
}

extension SearchViewModel: MKLocalSearchCompleterDelegate {
    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        let results = completer.results
        Task { @MainActor in self.addressResults = results }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        Task { @MainActor in self.addressResults = [] }
    }
}
