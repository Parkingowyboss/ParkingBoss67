import MapKit
import SwiftUI

/// Search sheet for named places (backend) and addresses (Apple).
/// On pick, returns a coordinate to recenter the map plus an optional Location.
struct SearchScreen: View {
    var onPick: (CLLocationCoordinate2D, Location?) -> Void

    @StateObject private var viewModel = SearchViewModel()
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""

    var body: some View {
        NavigationStack {
            List {
                if !viewModel.placeResults.isEmpty {
                    Section("Miejsca") {
                        ForEach(viewModel.placeResults) { location in
                            Button { onPick(location.coordinate, location) } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: location.type.systemImage)
                                        .foregroundStyle(location.type.tint)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(location.title).foregroundStyle(.primary)
                                        if let address = location.address {
                                            Text(address).font(.caption).foregroundStyle(.secondary)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                if !viewModel.addressResults.isEmpty {
                    Section("Adresy") {
                        ForEach(viewModel.addressResults, id: \.self) { completion in
                            Button {
                                Task {
                                    if let coord = await viewModel.resolve(completion) {
                                        onPick(coord, nil)
                                    }
                                }
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "mappin.circle.fill").foregroundStyle(.red)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(completion.title).foregroundStyle(.primary)
                                        if !completion.subtitle.isEmpty {
                                            Text(completion.subtitle).font(.caption).foregroundStyle(.secondary)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .listStyle(.plain)
            .searchable(text: $text, placement: .navigationBarDrawer(displayMode: .always), prompt: "Szukaj miejsca lub adresu")
            .onChange(of: text) { _, query in viewModel.update(query: query) }
            .navigationTitle("Szukaj")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Anuluj") { dismiss() }
                }
            }
        }
    }
}
