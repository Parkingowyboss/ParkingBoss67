import SwiftUI

enum AppAppearance: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return "Systemowy"
        case .light: return "Jasny"
        case .dark: return "Ciemny"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

/// App-wide preferences, persisted to UserDefaults. (Roadmap Step 19.)
@MainActor
final class AppSettings: ObservableObject {
    @Published var searchRadius: Double { didSet { defaults.set(searchRadius, forKey: Keys.radius) } }
    @Published var notificationsEnabled: Bool { didSet { defaults.set(notificationsEnabled, forKey: Keys.notifications) } }
    @Published var appearance: AppAppearance { didSet { defaults.set(appearance.rawValue, forKey: Keys.appearance) } }
    @Published var hasOnboarded: Bool { didSet { defaults.set(hasOnboarded, forKey: Keys.onboarded) } }

    /// Selectable search radii in metres, for the settings picker.
    static let radiusOptions: [Double] = [200, 500, 1000, 2000]

    /// Anonymous, stable per-install id used to attribute occupancy reports
    /// (no account required).
    let clientId: String

    private let defaults: UserDefaults

    private enum Keys {
        static let radius = "settings.radius"
        static let notifications = "settings.notifications"
        static let appearance = "settings.appearance"
        static let onboarded = "settings.onboarded"
        static let clientId = "settings.clientId"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        searchRadius = (defaults.object(forKey: Keys.radius) as? Double) ?? 1000
        notificationsEnabled = defaults.bool(forKey: Keys.notifications)
        appearance = AppAppearance(rawValue: defaults.string(forKey: Keys.appearance) ?? "") ?? .system
        hasOnboarded = defaults.bool(forKey: Keys.onboarded)
        if let existing = defaults.string(forKey: Keys.clientId) {
            clientId = existing
        } else {
            let generated = UUID().uuidString
            defaults.set(generated, forKey: Keys.clientId)
            clientId = generated
        }
    }
}
