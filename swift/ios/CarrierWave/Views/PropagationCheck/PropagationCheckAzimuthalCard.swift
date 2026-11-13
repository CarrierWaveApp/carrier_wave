import CarrierWaveCore
import SwiftUI

// MARK: - PropagationCheckAzimuthalCard

/// Azimuthal-equidistant polar plot of a propagation check, centered on the
/// operator's grid. Reuses `AzimuthalMapView` with sector density + spot pins.
/// No compass, no antenna pattern, no map tiles — read-only review surface.
struct PropagationCheckAzimuthalCard: View {
    // MARK: Internal

    let userGrid: String
    let enrichedSpots: [PropagationEnrichedSpot]

    var body: some View {
        let projection = buildProjection()
        VStack(alignment: .leading, spacing: 8) {
            AzimuthalMapView(
                sectors: projection.sectors,
                spotPoints: projection.points,
                qsoPoints: [],
                antennaPattern: nil,
                compassHeading: nil,
                maxDistanceKm: projection.maxDistanceKm
            )
            .frame(height: 320)

            Text("Centered on \(userGrid.isEmpty ? "—" : userGrid) · max \(Int(projection.maxDistanceKm)) km")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: Private

    private struct Projection {
        let points: [AzimuthalSpotPoint]
        let sectors: [BearingSector]
        let maxDistanceKm: Double
    }

    private struct ResolvedSpot {
        let spot: PropagationEnrichedSpot
        let bearing: Double
        let distanceKm: Double
    }

    private func buildProjection() -> Projection {
        let resolved: [ResolvedSpot] = enrichedSpots.compactMap { spot in
            guard let bearing = spot.bearing, let distance = spot.distanceKm else {
                return nil
            }
            return ResolvedSpot(spot: spot, bearing: bearing, distanceKm: distance)
        }
        let maxDistance = max(1_000, (resolved.map(\.distanceKm).max() ?? 5_000) * 1.05)
        let points: [AzimuthalSpotPoint] = resolved.map { resolved in
            let point = AzimuthalProjection.project(
                bearing: resolved.bearing,
                distanceKm: resolved.distanceKm,
                maxDistanceKm: maxDistance
            )
            return AzimuthalSpotPoint(
                id: resolved.spot.id,
                callsign: resolved.spot.entry.skimmerCall,
                bearing: point.bearing,
                distanceKm: point.distanceKm,
                normalizedRadius: point.normalizedRadius,
                isSpot: true,
                band: resolved.spot.entry.band,
                source: spotSource(for: resolved.spot.entry.source)
            )
        }
        let sectors = AzimuthalProjection.binIntoSectors(
            items: points.map { (bearing: $0.bearing, isSpot: true) },
            sectorCount: 36
        )
        return Projection(points: points, sectors: sectors, maxDistanceKm: maxDistance)
    }

    private func spotSource(for source: PropagationSpotSource) -> SpotSource {
        switch source {
        case .rbn: .rbn
        case .pskr: .pskr
        }
    }
}
