import MapKit
import SwiftUI

/// Main map screen: Warsaw-centered clustered map with color-coded markers,
/// search bar, filter chips, user location and a tappable detail sheet.
/// (Roadmap Steps 8, 9, 10, 11, 13, 14.)
struct MapScreen: View {
    @EnvironmentObject private var locationManager: LocationManager
    @EnvironmentObject private var settings: AppSettings
    @StateObject private var viewModel = MapViewModel()

    @State private var region = MapScreen.warsawRegion
    @State private var selected: Location?
    @State private var selectedSpace: ParkingSpace?
    @State private var recenter: CLLocationCoordinate2D?
    @State private var showSearch = false
    @State private var zoomCommand: ClusteredMapView.ZoomCommand?

    static let warsawRegion = MKCoordinateRegion(
        center: LocationManager.warsaw,
        span: MKCoordinateSpan(latitudeDelta: 0.08, longitudeDelta: 0.08)
    )

    var body: some View {
        ClusteredMapView(
            locations: viewModel.visibleLocations,
            spaces: viewModel.spaces,
            initialRegion: Self.warsawRegion,
            recenter: recenter,
            zoom: zoomCommand,
            onRegionChange: { newRegion in
                region = newRegion
                Task {
                    await viewModel.loadIfMoved(center: newRegion.center, radius: radius(for: newRegion))
                    await viewModel.loadSpaces(for: newRegion)
                }
            },
            onSelect: { selected = $0 },
            onSelectSpace: { selectedSpace = $0 },
            onRecentered: { recenter = nil },
            onZoomHandled: { zoomCommand = nil }
        )
        .ignoresSafeArea(edges: .bottom)
        .overlay(alignment: .top) { topBar }
        .overlay(alignment: .trailing) { zoomButtons }
        .overlay(alignment: .bottom) { statusBar }
        .sheet(item: $selected) { LocationDetailSheet(location: $0) }
        .sheet(item: $selectedSpace) { space in
            SpaceReportSheet(space: space) { status in
                do {
                    let updated = try await APIClient.shared.report(
                        spaceId: space.id, status: status, clientId: settings.clientId
                    )
                    viewModel.apply(updated)
                    return updated
                } catch {
                    return nil
                }
            }
        }
        .sheet(isPresented: $showSearch) {
            SearchScreen { coordinate, location in
                showSearch = false
                recenter = coordinate
                selected = location
            }
        }
        .onChange(of: viewModel.activeFilters) { _, _ in
            Task { await viewModel.load(center: region.center, radius: radius(for: region)) }
        }
        .task {
            locationManager.requestPermission()
            await viewModel.load(center: region.center, radius: radius(for: region))
            await viewModel.loadSpaces(for: region)
        }
    }

    private var zoomButtons: some View {
        VStack(spacing: 0) {
            zoomButton(systemImage: "plus", factor: 0.5, accessibility: "Przybliż")
            Divider().frame(width: 36)
            zoomButton(systemImage: "minus", factor: 2.0, accessibility: "Oddal")
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(.separator), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.15), radius: 3, y: 1)
        .padding(.trailing, 12)
    }

    private func zoomButton(systemImage: String, factor: Double, accessibility: String) -> some View {
        Button {
            zoomCommand = .init(id: UUID(), factor: factor)
        } label: {
            Image(systemName: systemImage)
                .font(.title3.weight(.semibold))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibility)
    }

    private var topBar: some View {
        VStack(spacing: 8) {
            Button { showSearch = true } label: {
                HStack {
                    Image(systemName: "magnifyingglass")
                    Text("Szukaj miejsca lub adresu")
                    Spacer()
                }
                .foregroundStyle(.secondary)
                .padding(12)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            .padding(.horizontal)

            FilterChips(viewModel: viewModel)
        }
        .padding(.top, 8)
    }

    @ViewBuilder
    private var statusBar: some View {
        if viewModel.isLoading {
            ProgressView()
                .padding(8)
                .background(.thinMaterial, in: Capsule())
                .padding(.bottom, 24)
        } else if let error = viewModel.errorMessage {
            Text(error)
                .font(.footnote)
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(.thinMaterial, in: Capsule())
                .padding(.bottom, 24)
        } else if !viewModel.shouldShowSpaces(for: region) {
            Label("Przybliż, aby zobaczyć pojedyncze miejsca", systemImage: "plus.magnifyingglass")
                .font(.footnote)
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(.thinMaterial, in: Capsule())
                .padding(.bottom, 24)
        }
    }

    /// Approximate visible radius in metres from a region's span.
    private func radius(for region: MKCoordinateRegion) -> Double {
        let latMeters = region.span.latitudeDelta * 111_000
        return min(max(latMeters / 2, 300), 20_000)
    }
}
