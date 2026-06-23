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

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: lat, longitude: lng)
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
