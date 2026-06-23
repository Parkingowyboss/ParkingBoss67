import SwiftUI

/// Root tab shell. Shows onboarding once, applies the chosen appearance.
struct ContentView: View {
    @EnvironmentObject private var settings: AppSettings
    // Drive the cover from local state so it transitions false->true on appear;
    // a cover that is already `true` on first render won't present.
    @State private var showOnboarding = false

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
        .onAppear { if !settings.hasOnboarded { showOnboarding = true } }
        .fullScreenCover(isPresented: $showOnboarding) {
            OnboardingView()
        }
    }
}
