import MapKit
import SwiftUI

/// Bottom sheet shown when a marker is tapped. (Roadmap Steps 11, 12, 16.)
struct LocationDetailSheet: View {
    let location: Location
    @EnvironmentObject private var favorites: FavoritesStore

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: location.type.systemImage)
                    .font(.title2)
                    .foregroundStyle(location.type.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(location.title)
                        .font(.title3.weight(.semibold))
                    Text(location.type.displayName)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    favorites.toggle(location)
                } label: {
                    Image(systemName: favorites.isFavorite(location) ? "heart.fill" : "heart")
                        .font(.title2)
                        .foregroundStyle(.pink)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(favorites.isFavorite(location) ? "Usuń z ulubionych" : "Dodaj do ulubionych")
            }

            if let address = location.address {
                Label(address, systemImage: "mappin.and.ellipse")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 24) {
                if let price = location.priceLabel {
                    stat(title: "Cena", value: price)
                }
                if let total = location.totalSpots {
                    stat(title: "Miejsca", value: "\(location.availableSpots ?? total)/\(total)")
                }
                if let distance = location.distanceLabel {
                    stat(title: "Odległość", value: distance)
                }
            }

            Button(action: navigate) {
                Label("Nawiguj", systemImage: "arrow.triangle.turn.up.right.diamond.fill")
                    .frame(maxWidth: .infinity)
                    .font(.headline)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)

            Spacer(minLength: 0)
        }
        .padding()
        .presentationDetents([.height(280), .large])
        .presentationDragIndicator(.visible)
    }

    private func stat(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.headline)
        }
    }

    /// Opens Apple Maps with driving directions to this location. (Step 12, v1.)
    private func navigate() {
        let placemark = MKPlacemark(coordinate: location.coordinate)
        let item = MKMapItem(placemark: placemark)
        item.name = location.title
        item.openInMaps(launchOptions: [
            MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving
        ])
    }
}
