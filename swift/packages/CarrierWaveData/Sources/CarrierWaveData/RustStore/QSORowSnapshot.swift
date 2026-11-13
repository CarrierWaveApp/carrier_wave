import CarrierWaveCore
import Foundation

// MARK: - PresenceSummary

/// A minimal, Sendable per-service presence summary suitable for rendering the
/// Logbook row badges without a live `ServicePresence` relationship. Carries
/// exactly the fields `ServicePresenceBadge` reads. Produced by either backend:
/// the Rust query projects it; the SwiftData mapper derives it from
/// `qso.servicePresence`.
public struct PresenceSummary: Sendable, Equatable {
    // MARK: Lifecycle

    public init(serviceTypeRawValue: String, isPresent: Bool, isSubmitted: Bool, needsUpload: Bool) {
        self.serviceTypeRawValue = serviceTypeRawValue
        self.isPresent = isPresent
        self.isSubmitted = isSubmitted
        self.needsUpload = needsUpload
    }

    // MARK: Public

    public let serviceTypeRawValue: String
    public let isPresent: Bool
    public let isSubmitted: Bool
    public let needsUpload: Bool
}

// MARK: - QSORowSnapshot

/// A Sendable value-type snapshot of a QSO record suitable for off-main-actor
/// rendering of the Logbook list. Carries every field the row cell, date
/// grouping, and badges need so the view renders identically regardless of the
/// backend (SwiftData mapper or Rust query projection).
public struct QSORowSnapshot: Sendable, Identifiable, Equatable {
    // MARK: Lifecycle

    public init(
        id: String,
        callsign: String,
        band: String?,
        mode: String?,
        timestamp: Date,
        frequency: Double? = nil,
        rstSent: String? = nil,
        theirGrid: String? = nil,
        parkReference: String? = nil,
        name: String? = nil,
        power: Int? = nil,
        state: String? = nil,
        lotwConfirmed: Bool = false,
        qrzConfirmed: Bool = false,
        presence: [PresenceSummary] = []
    ) {
        self.id = id
        self.callsign = callsign
        self.band = band
        self.mode = mode
        self.timestamp = timestamp
        self.frequency = frequency
        self.rstSent = rstSent
        self.theirGrid = theirGrid
        self.parkReference = parkReference
        self.name = name
        self.power = power
        self.state = state
        self.lotwConfirmed = lotwConfirmed
        self.qrzConfirmed = qrzConfirmed
        self.presence = presence
    }

    // MARK: Public

    public let id: String
    public let callsign: String
    public let band: String?
    public let mode: String?
    public let timestamp: Date
    /// Frequency in MHz (matches `QSO.frequency`); `freq_khz / 1000` from the Rust path.
    public let frequency: Double?
    public let rstSent: String?
    public let theirGrid: String?
    public let parkReference: String?
    public let name: String?
    public let power: Int?
    public let state: String?
    public let lotwConfirmed: Bool
    public let qrzConfirmed: Bool
    public let presence: [PresenceSummary]
}

// MARK: - FfiQso initialiser

extension QSORowSnapshot {
    init(ffi: FfiQso) {
        self.init(
            id: ffi.id,
            callsign: ffi.callsign,
            band: ffi.band,
            mode: ffi.mode,
            timestamp: Date(timeIntervalSince1970: TimeInterval(ffi.qsoDate)),
            frequency: ffi.freqKhz.map { $0 / 1_000.0 },
            rstSent: ffi.rstSent,
            theirGrid: ffi.theirGrid,
            parkReference: ffi.park,
            name: ffi.name,
            power: ffi.power.map(Int.init),
            state: ffi.state,
            lotwConfirmed: ffi.lotwConfirmed,
            qrzConfirmed: ffi.qrzConfirmed,
            presence: ffi.presence.map {
                PresenceSummary(
                    serviceTypeRawValue: $0.serviceTypeRawValue,
                    isPresent: $0.isPresent,
                    isSubmitted: $0.isSubmitted,
                    needsUpload: $0.needsUpload
                )
            }
        )
    }
}
