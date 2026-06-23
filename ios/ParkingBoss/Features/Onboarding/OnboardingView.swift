import SwiftUI

/// One-time 3-screen intro; the final button asks for location permission.
/// (Roadmap Step 18.)
struct OnboardingView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var locationManager: LocationManager
    @Environment(\.dismiss) private var dismiss
    @State private var page = 0

    private struct Page {
        let icon: String
        let title: String
        let subtitle: String
        let tint: Color
    }

    private let pages: [Page] = [
        Page(icon: "map.fill", title: "Znajdź parking w Warszawie",
             subtitle: "Wszystkie parkingi publiczne i prywatne na jednej mapie.", tint: .blue),
        Page(icon: "bolt.car.fill", title: "Ładowarki EV i stacje paliw",
             subtitle: "Filtruj według tego, czego właśnie potrzebujesz.", tint: .green),
        Page(icon: "arrow.triangle.turn.up.right.diamond.fill", title: "Nawigacja do celu",
             subtitle: "Jeden tap i jedziesz prosto na wybrane miejsce.", tint: .orange),
    ]

    var body: some View {
        VStack {
            TabView(selection: $page) {
                ForEach(pages.indices, id: \.self) { index in
                    let item = pages[index]
                    VStack(spacing: 24) {
                        Spacer()
                        Image(systemName: item.icon)
                            .font(.system(size: 96))
                            .foregroundStyle(item.tint)
                        Text(item.title)
                            .font(.title.bold())
                            .multilineTextAlignment(.center)
                        Text(item.subtitle)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        Spacer()
                    }
                    .padding(.horizontal, 32)
                    .tag(index)
                }
            }
            .tabViewStyle(.page)
            .indexViewStyle(.page(backgroundDisplayMode: .always))

            Button(action: advance) {
                Text(page == pages.count - 1 ? "Zaczynamy" : "Dalej")
                    .frame(maxWidth: .infinity)
                    .font(.headline)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
    }

    private func advance() {
        if page < pages.count - 1 {
            withAnimation { page += 1 }
        } else {
            locationManager.requestPermission()
            settings.hasOnboarded = true
            dismiss()
        }
    }
}
