// LoFi QSO computed property helpers

import CarrierWaveCore
import Foundation

// MARK: - QSO Helpers

extension LoFiQso {
    var theirCall: String? {
        their?.call
    }

    var ourCall: String? {
        our?.call
    }

    var rstSent: String? {
        our?.sent
    }

    var rstRcvd: String? {
        their?.sent
    }

    var theirGrid: String? {
        their?.guess?.grid
    }

    var theirName: String? {
        their?.guess?.name
    }

    var theirState: String? {
        their?.guess?.state
    }

    var theirCountry: String? {
        their?.guess?.entityName
    }

    /// Frequency in MHz (API returns kHz)
    var freqMHz: Double? {
        freq.map { $0 / 1_000.0 }
    }

    /// QSO timestamp as Date (returns nil if startAtMillis is missing)
    var timestamp: Date? {
        startAtMillis.map { Date(timeIntervalSince1970: $0 / 1_000.0) }
    }

    /// Get their POTA reference
    var theirPotaRef: String? {
        refs?.first { $0.refType == "pota" || $0.program == "POTA" }?.reference
    }

    /// Get our POTA reference(s) from operation refs (comma-separated for two-fers)
    func myPotaRef(from operationRefs: [LoFiOperationRef]) -> String? {
        let parks =
            operationRefs
                .filter { $0.refType == "potaActivation" }
                .compactMap(\.reference)
        return parks.isEmpty ? nil : parks.joined(separator: ", ")
    }
}
