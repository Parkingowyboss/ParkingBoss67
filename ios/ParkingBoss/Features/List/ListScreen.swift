import SwiftUI

/// Nearby locations as a distance-sorted list — an alternative to the map.
/// (Roadmap Step 15.)
struct ListScreen: View {
    @EnvironmentObject private var locationManager: LocationManager
    @StateObject private var viewModel = MapViewModel()
    @State private var selected: Location?

    private var sorted: [Location] {
        viewModel.visibleLocations.sorted { ($0.distanceM ?? .greatestFiniteMagnitude) < ($1.distanceM ?? .greatestFiniteMagnitude) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading && sorted.isEmpty {
                    ProgressView("Ładowanie…")
                } else if sorted.isEmpty {
                    ContentUnavailableView("Brak miejsc w pobliżu", systemImage: "mappin.slash")
                } else {
                    List(sorted) { location in
                        Button { selected = location } label: { row(location) }
                            .buttonStyle(.plain)
                    }
                    .listStyle(.plain)
                    .refreshable { await reload() }
                }
            }
            .navigationTitle("W pobliżu")
            .sheet(item: $selected) { LocationDetailSheet(location: $0) }
            .task { await reload() }
        }
    }

    private func row(_ location: Location) -> some View {
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
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                if let distance = location.distanceLabel {
                    Text(distance).font(.subheadline.weight(.semibold))
                }
                if let price = location.priceLabel {
                    Text(price).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func reload() async {
        let center = locationManager.coordinate ?? LocationManager.warsaw
        await viewModel.load(center: center, radius: 2_000)
    }
}
