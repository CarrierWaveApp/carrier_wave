// FFI Spot Adapters — legacy model reconstruction
//
// `POTASpotsView`, `OnAirCard`, and the Logger's S2S enrichment render
// `POTASpot`/`SOTASpot` view models. Rather than rewrite those row/sheet
// layers, engine spots are reconstructed into the legacy shapes here —
// same "replace internals, keep contracts" seam as SpotMonitoringService.
// Fields no iOS surface reads (SOTA activatorName/userID/highlightColor)
// are defaulted.

import CarrierWaveCore
import CarrierWaveCwFfi
import UIKit

extension FfiEnrichedSpot {
    /// Rebuild a `POTASpot` from an engine spot. `nil` for non-POTA sources.
    nonisolated var appPotaSpot: POTASpot? {
        guard source == .pota else {
            return nil
        }
        return POTASpot(
            spotId: Int64(id.dropFirst("pota-".count)) ?? Int64(id.hashValue),
            activator: callsign,
            frequency: Self.kHzString(frequencyKhz),
            mode: mode,
            reference: parkRef ?? "",
            parkName: parkName,
            spotTime: Self.iso8601(timestamp),
            spotter: spotter ?? "",
            comments: comments,
            source: potaSource,
            name: operatorName,
            locationDesc: locationDesc
        )
    }

    /// Rebuild a `SOTASpot` from an engine spot. `nil` for non-SOTA sources.
    /// `summitDetails` is reassembled as "<name>, <points> points" — the
    /// exact shape `SOTASpot.summitName`/`points` parse back out.
    nonisolated var appSotaSpot: SOTASpot? {
        guard source == .sota else {
            return nil
        }
        let fullRef = summitCode ?? ""
        let refParts = fullRef.split(separator: "/", maxSplits: 1)
        return SOTASpot(
            id: Int(id.dropFirst("sota-".count)) ?? id.hashValue,
            userID: 0,
            activatorCallsign: callsign,
            activatorName: "",
            spotterCallsign: spotter ?? "",
            associationCode: refParts.first.map(String.init) ?? "",
            summitCode: refParts.count > 1 ? String(refParts[1]) : "",
            summitDetails: "\(summitName ?? ""), \(summitPoints ?? 0) points",
            frequency: String(format: "%.3f", frequencyKhz / 1_000.0),
            mode: mode,
            comments: comments,
            highlightColor: nil,
            timeStamp: Self.iso8601(timestamp)
        )
    }

    // MARK: - Formatting helpers

    /// kHz string the way POTA's API writes it — integral when whole.
    nonisolated private static func kHzString(_ khz: Double) -> String {
        khz.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0f", khz)
            : String(format: "%.1f", khz)
    }

    /// "2026-07-02T18:41:00" (UTC, no timezone suffix) — the format both
    /// `POTASpot.parseSpotTime` and `SOTASpot.parsedTimestamp` accept.
    nonisolated private static func iso8601(_ epochSeconds: Int64) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate, .withTime, .withColonSeparatorInTime]
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.string(from: Date(timeIntervalSince1970: TimeInterval(epochSeconds)))
    }
}
