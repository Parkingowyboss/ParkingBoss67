import SwiftUI

/// Preferences screen. (Roadmap Step 19.)
struct SettingsScreen: View {
    @EnvironmentObject private var settings: AppSettings

    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
        return "\(v) (\(b))"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Wyszukiwanie") {
                    Picker("Domyślny promień", selection: $settings.searchRadius) {
                        ForEach(AppSettings.radiusOptions, id: \.self) { meters in
                            Text(radiusLabel(meters)).tag(meters)
                        }
                    }
                }

                Section("Wygląd") {
                    Picker("Motyw", selection: $settings.appearance) {
                        ForEach(AppAppearance.allCases) { option in
                            Text(option.label).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Powiadomienia") {
                    Toggle("Powiadomienia o ulubionych", isOn: $settings.notificationsEnabled)
                }

                Section("O aplikacji") {
                    LabeledContent("Wersja", value: appVersion)
                    Link("Polityka prywatności", destination: URL(string: "https://parkingboss.pl/privacy")!)
                }
            }
            .navigationTitle("Ustawienia")
        }
    }

    private func radiusLabel(_ meters: Double) -> String {
        meters >= 1000 ? "\(String(format: "%.0f", meters / 1000)) km" : "\(Int(meters)) m"
    }
}
