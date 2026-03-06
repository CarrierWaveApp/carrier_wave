//
//  AzimuthalDataProvider.swift
//  CarrierWave
//
//  Transforms spots and QSOs into sector-binned data for the azimuthal map view.
//

import CarrierWaveCore
import CarrierWaveData
import Foundation

// MARK: - AzimuthalSpotPoint

/// A spot or QSO projected onto the azimuthal view
struct AzimuthalSpotPoint: Identifiable, Sendable {
    let id: String
    let callsign: String
    let bearing: Double
    let distanceKm: Double
    let normalizedRadius: Double
    let isSpot: Bool // true = spot, false = QSO
    let band: String?
    let source: String // "rbn", "pota", "sota", "qso"
}

// MARK: - AzimuthalDataProvider

enum AzimuthalDataProvider {
    /// Project spots into azimuthal points relative to the operator's grid
    static func projectSpots(
        _ spots: [UnifiedSpot],
        from myGrid: String,
        maxDistanceKm: Double = AzimuthalProjection.earthHalfCircumferenceKm
    ) -> [AzimuthalSpotPoint] {
        spots.compactMap { spot in
            guard let grid = spot.callsignGrid ?? spot.spotterGrid,
                  let point = AzimuthalProjection.project(
                      from: myGrid,
                      to: grid,
                      maxDistanceKm: maxDistanceKm
                  )
            else {
                return nil
            }
            return AzimuthalSpotPoint(
                id: spot.id,
                callsign: spot.callsign,
                bearing: point.bearing,
                distanceKm: point.distanceKm,
                normalizedRadius: point.normalizedRadius,
                isSpot: true,
                band: BandUtilities.deriveBand(from: spot.frequencyKHz),
                source: String(describing: spot.source)
            )
        }
    }

    /// Project QSOs into azimuthal points relative to the operator's grid
    static func projectQSOs(
        _ qsos: [QSO],
        from myGrid: String,
        maxDistanceKm: Double = AzimuthalProjection.earthHalfCircumferenceKm
    ) -> [AzimuthalSpotPoint] {
        qsos.compactMap { qso in
            guard let theirGrid = qso.theirGrid,
                  let point = AzimuthalProjection.project(
                      from: myGrid,
                      to: theirGrid,
                      maxDistanceKm: maxDistanceKm
                  )
            else {
                return nil
            }
            return AzimuthalSpotPoint(
                id: qso.id.uuidString,
                callsign: qso.callsign,
                bearing: point.bearing,
                distanceKm: point.distanceKm,
                normalizedRadius: point.normalizedRadius,
                isSpot: false,
                band: qso.band,
                source: "qso"
            )
        }
    }

    /// Build sector data from projected points
    static func buildSectors(
        spots: [AzimuthalSpotPoint],
        qsos: [AzimuthalSpotPoint],
        sectorCount: Int = 36
    ) -> [BearingSector] {
        var items: [(bearing: Double, isSpot: Bool)] = []
        items.append(contentsOf: spots.map { ($0.bearing, true) })
        items.append(contentsOf: qsos.map { ($0.bearing, false) })
        return AzimuthalProjection.binIntoSectors(items: items, sectorCount: sectorCount)
    }
}
