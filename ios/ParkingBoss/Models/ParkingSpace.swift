import CoreLocation
import SwiftUI

/// Crowd-sourced occupancy state of an individual stall.
enum SpaceStatus: String, Codable {
    case free
    case occupied
    case unknown

    var color: Color {
        switch self {
        case .free: return .green
        case .occupied: return .red
        case .unknown: return .gray
        }
    }

    var label: String {
        switch self {
        case .free: return "Wolne"
        case .occupied: return "Zajęte"
        case .unknown: return "Nieznany"
        }
    }
}

/// A single parking stall. Matches the backend `/spaces` JSON.
struct ParkingSpace: Identifiable, Codable, Equatable {
    let id: String
    let lat: Double
    let lng: Double
    let ref: String?
    let fee: Bool?
    let disabled: Bool?
    let status: SpaceStatus
    /// Footprint as [[lng, lat], ...] (closed ring) for drawing the real stall shape.
    let polygon: [[Double]]?

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: lat, longitude: lng)
    }

    /// The stall outline as map coordinates, or nil if no footprint.
    var ringCoordinates: [CLLocationCoordinate2D]? {
        guard let polygon, polygon.count >= 4 else { return nil }
        return polygon.compactMap { pair in
            pair.count == 2 ? CLLocationCoordinate2D(latitude: pair[1], longitude: pair[0]) : nil
        }
    }

    var title: String {
        if let ref, !ref.isEmpty { return "Miejsce \(ref)" }
        return disabled == true ? "Miejsce dla niepełnosprawnych" : "Miejsce parkingowe"
    }
}

struct SpaceListResponse: Codable {
    let count: Int
    let capped: Bool
    let items: [ParkingSpace]
}
