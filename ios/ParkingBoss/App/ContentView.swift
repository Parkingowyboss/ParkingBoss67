import SwiftUI

/// Root tab shell. Shows onboarding once, applies the chosen appearance.
struct ContentView: View {
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        TabView {
            MapScreen()
                .tabItem { Label("Mapa", systemImage: "map.fill") }
            ListScreen()
                .tabItem { Label("Lista", systemImage: "list.bullet") }
            FavoritesScreen()
                .tabItem { Label("Ulubione", systemImage: "heart.fill") }
            SettingsScreen()
                .tabItem { Label("Ustawienia", systemImage: "gearshape.fill") }
        }
        .preferredColorScheme(settings.appearance.colorScheme)
        .fullScreenCover(isPresented: Binding(
            get: { !settings.hasOnboarded },
            set: { _ in }
        )) {
            OnboardingView()
        }
    }
}
