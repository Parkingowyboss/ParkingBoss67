import MapKit
import SwiftUI
import UIKit

/// MKAnnotation wrapper around a `Location`.
final class LocationAnnotation: NSObject, MKAnnotation {
    let location: Location
    var coordinate: CLLocationCoordinate2D { location.coordinate }
    var title: String? { location.title }
    init(_ location: Location) { self.location = location }
}

/// MKAnnotation wrapper around an individual stall.
final class SpaceAnnotation: NSObject, MKAnnotation {
    let space: ParkingSpace
    var coordinate: CLLocationCoordinate2D { space.coordinate }
    var title: String? { space.title }
    init(_ space: ParkingSpace) { self.space = space }
}

/// Cache of small colored dot images, one per status, for stall annotations.
private enum SpaceDot {
    static let cache = NSCache<NSString, UIImage>()

    static func image(for color: UIColor, diameter: CGFloat = 12) -> UIImage {
        let key = "\(color.hashValue)-\(diameter)" as NSString
        if let cached = cache.object(forKey: key) { return cached }
        let size = CGSize(width: diameter, height: diameter)
        let image = UIGraphicsImageRenderer(size: size).image { ctx in
            color.setFill()
            ctx.cgContext.fillEllipse(in: CGRect(origin: .zero, size: size))
            UIColor.white.setStroke()
            ctx.cgContext.setLineWidth(1.5)
            ctx.cgContext.strokeEllipse(in: CGRect(origin: .zero, size: size).insetBy(dx: 0.75, dy: 0.75))
        }
        cache.setObject(image, forKey: key)
        return image
    }
}

/// MKMapView wrapped for SwiftUI to get real marker clustering
/// (`MKClusterAnnotation`), which the SwiftUI `Map` does not provide.
/// (Roadmap Step 10.)
struct ClusteredMapView: UIViewRepresentable {
    var locations: [Location]
    /// Individual stalls; rendered as colored dots, no clustering.
    var spaces: [ParkingSpace] = []
    let initialRegion: MKCoordinateRegion
    /// When set, the map animates to this coordinate, then calls `onRecentered`.
    var recenter: CLLocationCoordinate2D?
    var onRegionChange: (MKCoordinateRegion) -> Void
    var onSelect: (Location) -> Void
    var onSelectSpace: (ParkingSpace) -> Void = { _ in }
    var onRecentered: () -> Void

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
        map.register(MKAnnotationView.self, forAnnotationViewWithReuseIdentifier: "space")

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
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var parent: ClusteredMapView
        var lastRecenter: CLLocationCoordinate2D?
        private var currentIDs: Set<String> = []
        // Keyed by id+status so a status change re-renders the dot.
        private var currentSpaceKeys: Set<String> = []

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

        /// Replace stall annotations when the id+status set changes.
        func syncSpaces(_ spaces: [ParkingSpace], on map: MKMapView) {
            let newKeys = Set(spaces.map { "\($0.id):\($0.status.rawValue)" })
            if newKeys == currentSpaceKeys { return }
            currentSpaceKeys = newKeys
            let existing = map.annotations.compactMap { $0 as? SpaceAnnotation }
            map.removeAnnotations(existing)
            map.addAnnotations(spaces.map(SpaceAnnotation.init))
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

            if let space = annotation as? SpaceAnnotation {
                let view = mapView.dequeueReusableAnnotationView(withIdentifier: "space", for: space)
                view.image = SpaceDot.image(for: UIColor(space.space.status.color))
                view.canShowCallout = false
                // Draw every stall — no decluttering — so all spaces are highlighted.
                view.collisionMode = .none
                view.displayPriority = .required
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
                // Zoom into the cluster.
                let span = MKCoordinateSpan(
                    latitudeDelta: max(mapView.region.span.latitudeDelta / 3, 0.001),
                    longitudeDelta: max(mapView.region.span.longitudeDelta / 3, 0.001)
                )
                mapView.setRegion(MKCoordinateRegion(center: cluster.coordinate, span: span), animated: true)
                mapView.deselectAnnotation(cluster, animated: false)
            } else if let loc = view.annotation as? LocationAnnotation {
                parent.onSelect(loc.location)
                mapView.deselectAnnotation(loc, animated: false)
            } else if let space = view.annotation as? SpaceAnnotation {
                parent.onSelectSpace(space.space)
                mapView.deselectAnnotation(space, animated: false)
            }
        }
    }
}
