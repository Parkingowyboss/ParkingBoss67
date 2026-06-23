import SwiftUI

/// Horizontal scroll of type-filter chips, à la Airbnb. (Roadmap Step 9.)
struct FilterChips: View {
    @ObservedObject var viewModel: MapViewModel

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(LocationType.filterGroups, id: \.label) { group in
                    let isActive = viewModel.activeFilters.contains(group.label)
                    Button {
                        viewModel.toggleFilter(group.label)
                    } label: {
                        Text(group.label)
                            .font(.subheadline.weight(.medium))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(isActive ? Color.accentColor : Color(.systemBackground))
                            .foregroundStyle(isActive ? .white : .primary)
                            .clipShape(Capsule())
                            .overlay(
                                Capsule().stroke(Color(.separator), lineWidth: isActive ? 0 : 1)
                            )
                            .shadow(color: .black.opacity(0.08), radius: 2, y: 1)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
        }
    }
}
