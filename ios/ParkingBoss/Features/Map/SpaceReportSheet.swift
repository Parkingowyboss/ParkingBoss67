import SwiftUI

/// Bottom sheet for a single stall: shows current status and lets the user
/// report it free or occupied (the crowd-sourced occupancy layer).
struct SpaceReportSheet: View {
    let space: ParkingSpace
    /// Called with the chosen status; returns the updated stall (or nil on failure).
    let onReport: (SpaceStatus) async -> ParkingSpace?

    @Environment(\.dismiss) private var dismiss
    @State private var current: ParkingSpace
    @State private var submitting: SpaceStatus?

    init(space: ParkingSpace, onReport: @escaping (SpaceStatus) async -> ParkingSpace?) {
        self.space = space
        self.onReport = onReport
        _current = State(initialValue: space)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 12) {
                Circle()
                    .fill(current.status.color)
                    .frame(width: 16, height: 16)
                    .overlay(Circle().stroke(.white, lineWidth: 1.5))
                VStack(alignment: .leading, spacing: 2) {
                    Text(current.title).font(.headline)
                    Text("Status: \(current.status.label)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if current.fee == true {
                    Label("Płatne", systemImage: "creditcard")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Text("Pomóż innym kierowcom — oznacz to miejsce:")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                reportButton(.free, systemImage: "checkmark.circle.fill")
                reportButton(.occupied, systemImage: "xmark.circle.fill")
            }

            Spacer(minLength: 0)
        }
        .padding()
        .presentationDetents([.height(240)])
        .presentationDragIndicator(.visible)
    }

    private func reportButton(_ status: SpaceStatus, systemImage: String) -> some View {
        Button {
            Task {
                submitting = status
                if let updated = await onReport(status) { current = updated }
                submitting = nil
            }
        } label: {
            Group {
                if submitting == status {
                    ProgressView()
                } else {
                    Label(status.label, systemImage: systemImage)
                }
            }
            .frame(maxWidth: .infinity)
            .font(.headline)
            .padding(.vertical, 14)
        }
        .buttonStyle(.borderedProminent)
        .tint(status.color)
        .disabled(submitting != nil)
    }
}
