import CoreLocation
import Foundation

/// A parking spot, EV charger or gas station. Matches the backend `/locations` JSON.
struct Location: Identifiable, Codable, Equatable, Hashable {
    let id: String
    let type: LocationType
    let name: String?
    let address: String?
    let lat: Double
    let lng: Double
    let totalSpots: Int?
    let availableSpots: Int?
    let pricePerHour: Double?
    let currency: String?
    /// Present only on /locations (nearby) responses.
    let distanceM: Double?

    enum CodingKeys: String, CodingKey {
        case id, type, name, address, lat, lng
        case totalSpots = "total_spots"
        case availableSpots = "available_spots"
        case pricePerHour = "price_per_hour"
        case currency
        case distanceM = "distance_m"
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: lat, longitude: lng)
    }

    var title: String {
        name ?? type.displayName
    }

    /// e.g. "4,50 PLN/h"
    var priceLabel: String? {
        guard let price = pricePerHour else { return nil }
        let formatted = String(format: "%.2f", price).replacingOccurrences(of: ".", with: ",")
        return "\(formatted) \(currency ?? "PLN")/h"
    }

    /// e.g. "320 m" or "1,2 km"
    var distanceLabel: String? {
        guard let d = distanceM else { return nil }
        if d < 1000 { return "\(Int(d.rounded())) m" }
        let km = String(format: "%.1f", d / 1000).replacingOccurrences(of: ".", with: ",")
        return "\(km) km"
    }
}

/// Wrapper for GET /locations and /locations/search.
struct LocationListResponse: Codable {
    let count: Int
    let items: [Location]
}
