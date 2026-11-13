// Nearby Reference Suggestions
//
// Compact inline suggestions for the closest POTA parks, SOTA summits,
// and WWFF references, shown directly in the session start form so
// users can tap to select without opening the full picker sheet.
//
// Everything here is fully synchronous — the grid → coordinate conversion
// is pure math, the catalog snapshots are in-memory dictionaries already
// loaded at app launch, and `nearby*` is a haversine pass over those
// snapshots. No async, no spinners. If the user doesn't have a grid set
// yet (e.g. fresh-install before the wizard's location service has filled
// in `myGrid`), the section just hides until a grid arrives.

import CarrierWaveData
import CoreLocation
import SwiftUI

// MARK: - Constants

/// Maximum number of nearby suggestions to show in the wizard.
private let nearbyLimit = 3

/// Search radius for nearby suggestions, in kilometers (~10 mi).
private let nearbyMaxDistanceKm: Double = 16

// MARK: - Helpers

/// Resolve coordinates from a Maidenhead grid square. Pure math, synchronous.
/// Returns `nil` only if the grid is empty or unparseable.
private func coordinateFromGrid(_ grid: String?) -> (latitude: Double, longitude: Double)? {
    guard let grid, !grid.trimmingCharacters(in: .whitespaces).isEmpty,
          let coord = MaidenheadConverter.coordinate(from: grid)
    else {
        return nil
    }
    return (coord.latitude, coord.longitude)
}

// MARK: - NearbyParkSuggestions

/// Shows up to `nearbyLimit` closest POTA parks within `nearbyMaxDistanceKm`.
struct NearbyParkSuggestions: View {
    // MARK: Internal

    let userGrid: String?
    let defaultCountry: String
    let selectedParks: [String]
    let onAdd: (POTAPark) -> Void

    var body: some View {
        let results = nearbyResults()
        if !results.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                NearbyHeader(maxDistanceKm: nearbyMaxDistanceKm)
                ForEach(results, id: \.park.reference) { item in
                    NearbyParkRow(
                        park: item.park,
                        distanceKm: item.distanceKm,
                        isSelected: isSelected(item.park),
                        onTap: { onAdd(item.park) }
                    )
                }
            }
        }
    }

    /// No-op kept for call-site compatibility with the previous async API.
    func loadOnAppear() -> some View {
        self
    }

    // MARK: Private

    private func nearbyResults() -> [(park: POTAPark, distanceKm: Double)] {
        guard let coord = coordinateFromGrid(userGrid) else {
            return []
        }
        return POTAParksCache.shared.nearbyParks(
            latitude: coord.latitude,
            longitude: coord.longitude,
            limit: nearbyLimit,
            maxDistanceKm: nearbyMaxDistanceKm
        )
    }

    private func isSelected(_ park: POTAPark) -> Bool {
        selectedParks.contains { $0.uppercased() == park.reference.uppercased() }
    }
}

// MARK: - NearbyParkRow

/// Compact row for a nearby park suggestion
private struct NearbyParkRow: View {
    let park: POTAPark
    let distanceKm: Double
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "plus.circle")
                    .font(.subheadline)
                    .foregroundStyle(isSelected ? .green : .blue)

                Text(park.reference)
                    .font(.caption.monospaced().weight(.semibold))
                    .foregroundStyle(.green)

                Text(park.name)
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Spacer()

                Text(UnitFormatter.distance(distanceKm))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
            .background(Color(.tertiarySystemFill))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .disabled(isSelected)
    }
}

// MARK: - NearbySummitSuggestions

/// Shows up to `nearbyLimit` closest SOTA summits within `nearbyMaxDistanceKm`.
struct NearbySummitSuggestions: View {
    // MARK: Internal

    let userGrid: String?
    let currentReference: String
    let onSelect: (SOTASummit) -> Void

    var body: some View {
        if currentReference.trimmingCharacters(in: .whitespaces).isEmpty {
            let results = nearbyResults()
            if !results.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    NearbyHeader(maxDistanceKm: nearbyMaxDistanceKm)
                    ForEach(results, id: \.summit.code) { item in
                        NearbySummitRow(
                            summit: item.summit,
                            distanceKm: item.distanceKm,
                            onTap: { onSelect(item.summit) }
                        )
                    }
                }
            }
        }
    }

    /// No-op kept for call-site compatibility with the previous async API.
    func loadOnAppear() -> some View {
        self
    }

    // MARK: Private

    private func nearbyResults() -> [(summit: SOTASummit, distanceKm: Double)] {
        guard let coord = coordinateFromGrid(userGrid) else {
            return []
        }
        return SOTASummitsCache.shared.nearbySummits(
            latitude: coord.latitude,
            longitude: coord.longitude,
            limit: nearbyLimit,
            maxDistanceKm: nearbyMaxDistanceKm
        )
    }
}

// MARK: - NearbySummitRow

/// Compact row for a nearby summit suggestion
private struct NearbySummitRow: View {
    let summit: SOTASummit
    let distanceKm: Double
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                Image(systemName: "plus.circle")
                    .font(.subheadline)
                    .foregroundStyle(.blue)

                Text(summit.code)
                    .font(.caption.monospaced().weight(.semibold))
                    .foregroundStyle(.green)

                Text(summit.name)
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Spacer()

                Text(UnitFormatter.distance(distanceKm))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
            .background(Color(.tertiarySystemFill))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - NearbyWWFFSuggestions

/// Shows up to `nearbyLimit` closest WWFF references within `nearbyMaxDistanceKm`.
struct NearbyWWFFSuggestions: View {
    // MARK: Internal

    let userGrid: String?
    let currentReference: String
    let onSelect: (WWFFReference) -> Void

    var body: some View {
        if currentReference.trimmingCharacters(in: .whitespaces).isEmpty {
            let results = nearbyResults()
            if !results.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    NearbyHeader(maxDistanceKm: nearbyMaxDistanceKm)
                    ForEach(results, id: \.reference.reference) { item in
                        NearbyWWFFRow(
                            reference: item.reference,
                            distanceKm: item.distanceKm,
                            onTap: { onSelect(item.reference) }
                        )
                    }
                }
            }
        }
    }

    /// No-op kept for call-site compatibility with the previous async API.
    func loadOnAppear() -> some View {
        self
    }

    // MARK: Private

    private func nearbyResults() -> [(reference: WWFFReference, distanceKm: Double)] {
        guard let coord = coordinateFromGrid(userGrid) else {
            return []
        }
        return WWFFReferencesCache.shared.nearbyReferences(
            latitude: coord.latitude,
            longitude: coord.longitude,
            limit: nearbyLimit,
            maxDistanceKm: nearbyMaxDistanceKm
        )
    }
}

// MARK: - NearbyWWFFRow

/// Compact row for a nearby WWFF reference suggestion
private struct NearbyWWFFRow: View {
    let reference: WWFFReference
    let distanceKm: Double
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                Image(systemName: "plus.circle")
                    .font(.subheadline)
                    .foregroundStyle(.blue)

                Text(reference.reference)
                    .font(.caption.monospaced().weight(.semibold))
                    .foregroundStyle(.mint)

                Text(reference.name)
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Spacer()

                Text(UnitFormatter.distance(distanceKm))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
            .background(Color(.tertiarySystemFill))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - NearbyHeader

/// Section header for nearby suggestions, e.g. "NEARBY (10 MI)" or "NEARBY (16 KM)".
private struct NearbyHeader: View {
    let maxDistanceKm: Double

    var body: some View {
        Text("Nearby (within \(UnitFormatter.distance(maxDistanceKm)))")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
    }
}
