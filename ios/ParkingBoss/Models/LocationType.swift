import SwiftUI

/// Mirrors the backend `location_type` enum.
enum LocationType: String, Codable, CaseIterable, Identifiable {
    case parkingPublic = "parking_public"
    case parkingPrivate = "parking_private"
    case evCharger = "ev_charger"
    case gasStation = "gas_station"

    var id: String { rawValue }

    /// Short label used in filter chips.
    var filterLabel: String {
        switch self {
        case .parkingPublic, .parkingPrivate: return "Parking"
        case .evCharger: return "Ładowarka EV"
        case .gasStation: return "Stacja paliw"
        }
    }

    var displayName: String {
        switch self {
        case .parkingPublic: return "Parking publiczny"
        case .parkingPrivate: return "Parking prywatny"
        case .evCharger: return "Ładowarka EV"
        case .gasStation: return "Stacja paliw"
        }
    }

    var systemImage: String {
        switch self {
        case .parkingPublic, .parkingPrivate: return "parkingsign.circle.fill"
        case .evCharger: return "bolt.car.fill"
        case .gasStation: return "fuelpump.fill"
        }
    }

    var tint: Color {
        switch self {
        case .parkingPublic: return .blue
        case .parkingPrivate: return .indigo
        case .evCharger: return .green
        case .gasStation: return .orange
        }
    }

    /// Filter chips for the facility pins. Parking itself is shown as individual
    /// stall footprints, so it isn't a facility chip.
    static var filterGroups: [(label: String, types: [LocationType])] {
        [
            ("Ładowarka EV", [.evCharger]),
            ("Stacja paliw", [.gasStation]),
        ]
    }
}
