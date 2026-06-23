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

/// MKMapView wrapped for SwiftUI to get real marker clustering
/// (`MKClusterAnnotation`), which the SwiftUI `Map` does not provide.
/// (Roadmap Step 10.)
struct ClusteredMapView: UIViewRepresentable {
    var locations: [Location]
    let initialRegion: MKCoordinateRegion
    /// When set, the map animates to this coordinate, then calls `onRecentered`.
    var recenter: CLLocationCoordinate2D?
    var onRegionChange: (MKCoordinateRegion) -> Void
    var onSelect: (Location) -> Void
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
            }
        }
    }
}
