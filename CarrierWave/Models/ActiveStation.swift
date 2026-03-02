import CarrierWaveCore
import SwiftUI

// MARK: - ActiveStation

/// A station heard on-air, from either POTA spots or RBN
struct ActiveStation: Identifiable, Sendable {
    enum Source: Sendable {
        case pota(park: String)
        case sota(summit: String, points: Int)
        case wwff(reference: String)
        case rbn(snr: Int)
    }

    let id: String
    let callsign: String
    let frequencyMHz: Double
    let mode: String
    let timestamp: Date
    let source: Source

    var band: String {
        BandUtilities.deriveBand(from: frequencyMHz * 1_000) ?? "Other"
    }

    var timeAgo: String {
        let seconds = Date().timeIntervalSince(timestamp)
        if seconds < 60 {
            return "\(Int(seconds))s ago"
        }
        if seconds < 3_600 {
            return "\(Int(seconds / 60))m ago"
        }
        return "\(Int(seconds / 3_600))h ago"
    }

    var ageColor: Color {
        let seconds = Date().timeIntervalSince(timestamp)
        if seconds < 120 {
            return .green
        }
        if seconds < 600 {
            return .blue
        }
        if seconds < 1_800 {
            return .orange
        }
        return .secondary
    }

    var sourceLabel: String {
        switch source {
        case let .pota(park): park
        case let .sota(summit, _): summit
        case let .wwff(reference): reference
        case let .rbn(snr): "\(snr) dB"
        }
    }

    static func fromPOTA(_ spot: POTASpot) -> ActiveStation? {
        guard let kHz = spot.frequencyKHz else {
            return nil
        }
        return ActiveStation(
            id: "pota-\(spot.spotId)",
            callsign: spot.activator,
            frequencyMHz: kHz / 1_000.0,
            mode: spot.mode,
            timestamp: spot.timestamp ?? Date(),
            source: .pota(park: spot.reference)
        )
    }

    static func fromRBN(_ spot: RBNSpot) -> ActiveStation {
        ActiveStation(
            id: "rbn-\(spot.id)",
            callsign: spot.callsign,
            frequencyMHz: spot.frequencyMHz,
            mode: spot.mode,
            timestamp: spot.timestamp,
            source: .rbn(snr: spot.snr)
        )
    }

    static func fromSOTA(_ spot: SOTASpot) -> ActiveStation? {
        guard let mhz = spot.frequencyMHz else {
            return nil
        }
        return ActiveStation(
            id: "sota-\(spot.id)",
            callsign: spot.activatorCallsign,
            frequencyMHz: mhz,
            mode: spot.mode.uppercased(),
            timestamp: spot.parsedTimestamp ?? Date(),
            source: .sota(summit: spot.fullSummitReference, points: spot.points)
        )
    }
}
