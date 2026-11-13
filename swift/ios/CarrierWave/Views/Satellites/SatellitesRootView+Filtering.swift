import SwiftUI

// MARK: - Filter application

/// How the shared satellite filter (mode buckets + band letters +
/// heard-recently + favorites + minimum next-pass elevation + clear-sky
/// sectors) applies to the map dots and the next-pass strip, split out
/// of the main root-view file.
extension SatellitesRootView {
    /// One shot of the transmitter-level filter selections.
    var filterSelections: SatelliteFilterSelections {
        SatelliteFilterSelections(
            modeRaw: modeFilterRaw,
            uplinkRaw: uplinkBandRaw,
            downlinkRaw: downlinkBandRaw,
            heardRecentlyOnly: heardRecentlyOnly
        )
    }

    var horizonMask: [SkySector: Int] {
        SatelliteModeFilter.horizonMask(from: skySectorsRaw)
    }

    /// NORAD ids with an upcoming pass (12 h sweep) peaking at or above
    /// the elevation threshold AND clearing the horizon mask — nil when
    /// both gates are off or the sweep hasn't loaded yet (never blank
    /// the map on missing data).
    var sweepQualifiedIDs: Set<Int>? {
        let mask = horizonMask
        guard minPeakElevation > 0 || SatelliteModeFilter.horizonActive(mask),
              !nextPasses.isEmpty
        else {
            return nil
        }
        return Set(
            nextPasses
                .filter {
                    $0.pass.peakElevationDeg >= Double(minPeakElevation)
                        && SatelliteModeFilter.horizonAllows(
                            peakAzimuthDeg: $0.pass.peakAzimuthDeg,
                            peakElevationDeg: $0.pass.peakElevationDeg,
                            mask: mask
                        )
                }
                .map(\.noradID)
        )
    }

    /// Map dots under every filter; the explicitly selected bird always
    /// stays visible so selection and the info card never disagree.
    var filteredPositions: [SatellitePosition] {
        let selections = filterSelections
        let qualified = sweepQualifiedIDs
        let favoriteIDs = favoritesOnly ? FavoriteSatellitesStore.shared.noradIDs : nil
        return model.positions.filter { position in
            position.noradID == model.selectedNoradID
                || (
                    (favoriteIDs?.contains(position.noradID) ?? true)
                        && SatelliteModeFilter.matches(
                            model.transmitters(for: position.noradID), selections: selections
                        )
                        && (qualified?.contains(position.noradID) ?? true)
                )
        }
    }

    /// The strip's passes: favorited birds when any exist (all birds
    /// otherwise), fully filtered, peaking at or above the recommendation
    /// (or the elevation threshold when higher), soonest first, capped
    /// at 3.
    var stripPasses: [UpcomingSatellitePass] {
        let favoriteIDs = FavoriteSatellitesStore.shared.noradIDs
        let selections = filterSelections
        let mask = horizonMask
        let now = Date()
        let pool = favoriteIDs.isEmpty
            ? nextPasses
            : nextPasses.filter { favoriteIDs.contains($0.noradID) }
        let floor = max(
            SatelliteWorkability.recommendedPassElevationDeg, Double(minPeakElevation)
        )
        let workable = pool.filter {
            $0.pass.los > now
                && $0.pass.peakElevationDeg >= floor
                && SatelliteModeFilter.horizonAllows(
                    peakAzimuthDeg: $0.pass.peakAzimuthDeg,
                    peakElevationDeg: $0.pass.peakElevationDeg,
                    mask: mask
                )
                && SatelliteModeFilter.matches(
                    model.transmitters(for: $0.noradID), selections: selections
                )
        }
        return Array(workable.prefix(3))
    }
}
