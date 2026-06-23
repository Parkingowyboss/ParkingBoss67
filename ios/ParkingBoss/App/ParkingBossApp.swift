import SwiftUI

@main
struct ParkingBossApp: App {
    @StateObject private var locationManager = LocationManager()
    @StateObject private var settings = AppSettings()
    @StateObject private var favorites = FavoritesStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(locationManager)
                .environmentObject(settings)
                .environmentObject(favorites)
        }
    }
}
