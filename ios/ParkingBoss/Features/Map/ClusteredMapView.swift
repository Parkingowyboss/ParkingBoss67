import MapKit
import SwiftUI
import UIKit

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

/// MKAnnotation wrapper around a `Location`.
final class LocationAnnotation: NSObject, MKAnnotation {
    let location: Location
    var coordinate: CLLocationCoordinate2D { location.coordinate }
    var title: String? { location.title }
    init(_ location: Location) { self.location = location }
}

/// All stalls of one status grouped into a single overlay, so the whole stall
/// layer is just 3 renderers instead of one per stall.
final class SpaceMultiPolygon: MKMultiPolygon {
    var status: SpaceStatus = .unknown
}

/// Prettier per-status styling for the stall layer.
private enum StallStyle {
    static func fill(_ status: SpaceStatus) -> UIColor {
        switch status {
        case .free:     return UIColor(red: 0.30, green: 0.78, blue: 0.45, alpha: 0.90)
        case .occupied: return UIColor(red: 0.95, green: 0.38, blue: 0.36, alpha: 0.88)
        case .unknown:  return UIColor(red: 0.62, green: 0.66, blue: 0.73, alpha: 0.45)
        }
    }

    static func stroke(_ status: SpaceStatus) -> UIColor {
        switch status {
        case .free:     return UIColor(red: 0.16, green: 0.55, blue: 0.30, alpha: 0.65)
        case .occupied: return UIColor(red: 0.70, green: 0.20, blue: 0.18, alpha: 0.60)
        case .unknown:  return .clear
        }
    }
}

/// MKMapView wrapped for SwiftUI: facility marker clustering plus individual
/// parking stalls drawn as real, color-coded polygon footprints.
struct ClusteredMapView: UIViewRepresentable {
    var locations: [Location]
    /// Individual stalls; drawn as oriented rectangles colored by status.
    var spaces: [ParkingSpace] = []
    let initialRegion: MKCoordinateRegion
    /// When set, the map animates to this coordinate, then calls `onRecentered`.
    var recenter: CLLocationCoordinate2D?
    /// A zoom request from the +/- buttons; `factor` < 1 zooms in, > 1 zooms out.
    var zoom: ZoomCommand?
    var onRegionChange: (MKCoordinateRegion) -> Void
    var onSelect: (Location) -> Void
    var onSelectSpace: (ParkingSpace) -> Void = { _ in }
    var onRecentered: () -> Void
    var onZoomHandled: () -> Void = {}

    struct ZoomCommand: Equatable {
        let id: UUID
        let factor: Double
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.showsUserLocation = true
        map.pointOfInterestFilter = .excludingAll
        map.setRegion(initialRegion, animated: false)
        map.register(
            MKMarkerAnnotationView.self,
            forAnnotationViewWithReuseIdentifier: MKMapViewDefaultAnnotationViewReuseIdentifier
        )
        map.register(
            MKMarkerAnnotationView.self,
            forAnnotationViewWithReuseIdentifier: MKMapViewDefaultClusterAnnotationViewReuseIdentifier
        )

        // Tap-to-select a stall (overlays don't get didSelect).
        let tap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleTap(_:))
        )
        tap.delegate = context.coordinator
        tap.cancelsTouchesInView = false
        map.addGestureRecognizer(tap)

        let tracking = MKUserTrackingButton(mapView: map)
        tracking.translatesAutoresizingMaskIntoConstraints = false
        tracking.backgroundColor = UIColor.systemBackground.withAlphaComponent(0.9)
        tracking.layer.cornerRadius = 8
        tracking.layer.masksToBounds = true
        map.addSubview(tracking)
        NSLayoutConstraint.activate([
            tracking.trailingAnchor.constraint(equalTo: map.trailingAnchor, constant: -12),
            tracking.bottomAnchor.constraint(equalTo: map.safeAreaLayoutGuide.bottomAnchor, constant: -110),
        ])
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.sync(locations: locations, on: map)
        context.coordinator.syncSpaces(spaces, on: map)
        if let recenter, context.coordinator.shouldRecenter(to: recenter) {
            let region = MKCoordinateRegion(
                center: recenter,
                span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
            )
            map.setRegion(region, animated: true)
            context.coordinator.lastRecenter = recenter
            DispatchQueue.main.async { onRecentered() }
        }

        if let zoom, zoom.id != context.coordinator.lastZoomId {
            context.coordinator.lastZoomId = zoom.id
            var region = map.region
            let lat = (region.span.latitudeDelta * zoom.factor).clamped(to: 0.0009...60)
            let lng = (region.span.longitudeDelta * zoom.factor).clamped(to: 0.0009...60)
            region.span = MKCoordinateSpan(latitudeDelta: lat, longitudeDelta: lng)
            map.setRegion(region, animated: true)
            DispatchQueue.main.async { onZoomHandled() }
        }
    }

    final class Coordinator: NSObject, MKMapViewDelegate, UIGestureRecognizerDelegate {
        var parent: ClusteredMapView
        var lastRecenter: CLLocationCoordinate2D?
        var lastZoomId: UUID?
        private var currentIDs: Set<String> = []
        private var currentSpaceKeys: Set<String> = []
        private var spaceOverlays: [SpaceMultiPolygon] = []

        init(_ parent: ClusteredMapView) { self.parent = parent }

        func shouldRecenter(to coord: CLLocationCoordinate2D) -> Bool {
            guard let last = lastRecenter else { return true }
            return abs(last.latitude - coord.latitude) > 1e-7
                || abs(last.longitude - coord.longitude) > 1e-7
        }

        /// Replace location annotations only when the set of IDs actually changes.
        func sync(locations: [Location], on map: MKMapView) {
            let newIDs = Set(locations.map(\.id))
            if newIDs == currentIDs { return }
            currentIDs = newIDs
            let existing = map.annotations.compactMap { $0 as? LocationAnnotation }
            map.removeAnnotations(existing)
            map.addAnnotations(locations.map(LocationAnnotation.init))
        }

        /// Rebuild the stall layer (3 grouped overlays) when the id+status set changes.
        func syncSpaces(_ spaces: [ParkingSpace], on map: MKMapView) {
            let newKeys = Set(spaces.map { "\($0.id):\($0.status.rawValue)" })
            if newKeys == currentSpaceKeys { return }
            currentSpaceKeys = newKeys

            var byStatus: [SpaceStatus: [MKPolygon]] = [:]
            for s in spaces {
                guard let ring = s.ringCoordinates, ring.count >= 3 else { continue }
                byStatus[s.status, default: []].append(MKPolygon(coordinates: ring, count: ring.count))
            }

            map.removeOverlays(spaceOverlays)
            var overlays: [SpaceMultiPolygon] = []
            // Draw unknown first so free/occupied sit visually on top.
            for status in [SpaceStatus.unknown, .free, .occupied] {
                guard let polys = byStatus[status], !polys.isEmpty else { continue }
                let multi = SpaceMultiPolygon(polys)
                multi.status = status
                overlays.append(multi)
            }
            spaceOverlays = overlays
            map.addOverlays(overlays, level: .aboveRoads)
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let multi = overlay as? SpaceMultiPolygon {
                let renderer = MKMultiPolygonRenderer(multiPolygon: multi)
                renderer.fillColor = StallStyle.fill(multi.status)
                renderer.strokeColor = StallStyle.stroke(multi.status)
                renderer.lineWidth = multi.status == .unknown ? 0 : 0.5
                return renderer
            }
            return MKOverlayRenderer(overlay: overlay)
        }

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            parent.onRegionChange(mapView.region)
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if annotation is MKUserLocation { return nil }

            if let cluster = annotation as? MKClusterAnnotation {
                let view = mapView.dequeueReusableAnnotationView(
                    withIdentifier: MKMapViewDefaultClusterAnnotationViewReuseIdentifier,
                    for: cluster
                ) as! MKMarkerAnnotationView
                view.markerTintColor = .darkGray
                view.glyphText = "\(cluster.memberAnnotations.count)"
                return view
            }

            guard let loc = annotation as? LocationAnnotation else { return nil }
            let view = mapView.dequeueReusableAnnotationView(
                withIdentifier: MKMapViewDefaultAnnotationViewReuseIdentifier,
                for: loc
            ) as! MKMarkerAnnotationView
            view.clusteringIdentifier = "location"
            view.markerTintColor = UIColor(loc.location.type.tint)
            view.glyphImage = UIImage(systemName: loc.location.type.systemImage)
            view.canShowCallout = false
            return view
        }

        func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
            if let cluster = view.annotation as? MKClusterAnnotation {
                let span = MKCoordinateSpan(
                    latitudeDelta: max(mapView.region.span.latitudeDelta / 3, 0.001),
                    longitudeDelta: max(mapView.region.span.longitudeDelta / 3, 0.001)
                )
                mapView.setRegion(MKCoordinateRegion(center: cluster.coordinate, span: span), animated: true)
                mapView.deselectAnnotation(cluster, animated: false)
            } else if let loc = view.annotation as? LocationAnnotation {
                parent.onSelect(loc.location)
                mapView.deselectAnnotation(loc, animated: false)
            }
        }

        // MARK: - Stall tap selection

        @objc func handleTap(_ gr: UITapGestureRecognizer) {
            guard let map = gr.view as? MKMapView else { return }
            let pt = gr.location(in: map)

            // Let markers and on-map controls handle their own taps.
            var hit = map.hitTest(pt, with: nil)
            while let v = hit {
                if v is MKAnnotationView || v is UIControl { return }
                hit = v.superview
            }

            // Stalls are tiny — pick the nearest stall within a touch tolerance.
            var best: (ParkingSpace, CGFloat)?
            for space in parent.spaces {
                let center = map.convert(space.coordinate, toPointTo: map)
                let d = hypot(center.x - pt.x, center.y - pt.y)
                if d < (best?.1 ?? .greatestFiniteMagnitude) { best = (space, d) }
            }
            if let (space, d) = best, d <= 26 {
                parent.onSelectSpace(space)
            }
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
        ) -> Bool {
            true
        }
    }
}
