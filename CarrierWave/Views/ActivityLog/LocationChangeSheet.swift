import CarrierWaveCore
import CoreLocation
import SwiftUI

// MARK: - LocationChangeSheet

/// Sheet shown when the user's grid square has changed since last use.
/// Offers to update the grid and optionally switch station profiles.
struct LocationChangeSheet: View {
    // MARK: Internal

    let oldGrid: String
    let newGrid: String
    let profiles: [StationProfile]
    let currentProfileId: UUID?
    let onUpdate: (String, UUID?) -> Void
    let onKeep: () -> Void

    var body: some View {
        // swiftlint:disable:next redundant_discardable_let
        let _ = useMetricUnits // Trigger re-render when unit preference changes
        NavigationStack {
            VStack(spacing: 20) {
                locationIcon
                titleSection
                gridChangeCard
                actionButtons
                profileSwitcher
            }
            .padding()
            .navigationTitle("Location Changed")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Dismiss") { onKeep() }
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }

    // MARK: Private

    @AppStorage("useMetricUnits") private var useMetricUnits = false

    @State private var selectedProfileId: UUID?

    private var distanceText: String? {
        guard let oldCoord = MaidenheadConverter.coordinate(from: oldGrid),
              let newCoord = MaidenheadConverter.coordinate(from: newGrid)
        else {
            return nil
        }
        let loc1 = CLLocation(latitude: oldCoord.latitude, longitude: oldCoord.longitude)
        let loc2 = CLLocation(latitude: newCoord.latitude, longitude: newCoord.longitude)
        let km = loc1.distance(from: loc2) / 1_000.0
        return "\u{2248} \(UnitFormatter.distance(km)) moved"
    }

    private var locationIcon: some View {
        Image(systemName: "location.fill")
            .font(.largeTitle)
            .foregroundStyle(.blue)
    }

    private var titleSection: some View {
        VStack(spacing: 4) {
            Text("Location Changed")
                .font(.title3.weight(.semibold))
            Text("Your grid square appears to have changed.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private var gridChangeCard: some View {
        VStack(spacing: 4) {
            HStack(spacing: 8) {
                Text(oldGrid)
                    .font(.title3.monospaced())
                Image(systemName: "arrow.right")
                    .foregroundStyle(.secondary)
                Text(newGrid)
                    .font(.title3.monospaced().weight(.semibold))
            }

            if let distanceText {
                Text(distanceText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var actionButtons: some View {
        VStack(spacing: 8) {
            Button {
                onUpdate(newGrid, selectedProfileId)
            } label: {
                Text("Update to \(newGrid)")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)

            Button {
                onKeep()
            } label: {
                Text("Keep \(oldGrid)")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
    }

    @ViewBuilder
    private var profileSwitcher: some View {
        if profiles.count > 1 {
            VStack(alignment: .leading, spacing: 8) {
                Text("Switch station profile?")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(profiles) { profile in
                            profileChip(profile)
                        }
                    }
                }
            }
        }
    }

    private func profileChip(_ profile: StationProfile) -> some View {
        let isSelected = (selectedProfileId ?? currentProfileId) == profile.id
        return Button {
            selectedProfileId = profile.id
        } label: {
            Text(profile.name)
                .font(.caption.weight(.medium))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .foregroundStyle(isSelected ? .blue : .secondary)
                .background(
                    isSelected
                        ? Color.blue.opacity(0.15)
                        : Color(.tertiarySystemFill)
                )
                .clipShape(Capsule())
        }
    }
}
