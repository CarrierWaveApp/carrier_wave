//
//  QSOSnapshot.swift
//  CarrierWaveCore
//
//  Lightweight, Sendable representation of a QSO for deduplication and matching.
//

import Foundation

/// Sendable snapshot of QSO data needed for deduplication and matching.
/// This allows deduplication logic to be tested without SwiftData dependencies.
public struct QSOSnapshot: Sendable, Equatable, Identifiable {
    // MARK: Lifecycle

    public init(
        id: UUID,
        callsign: String,
        timestamp: Date,
        band: String,
        mode: String,
        parkReference: String? = nil,
        frequency: Double? = nil,
        rstSent: String? = nil,
        rstReceived: String? = nil,
        myGrid: String? = nil,
        theirGrid: String? = nil,
        notes: String? = nil,
        rawADIF: String? = nil,
        name: String? = nil,
        qth: String? = nil,
        state: String? = nil,
        country: String? = nil,
        power: Int? = nil,
        theirLicenseClass: String? = nil,
        syncedServicesCount: Int = 0
    ) {
        self.id = id
        self.callsign = callsign
        self.timestamp = timestamp
        self.band = band
        self.mode = mode
        self.parkReference = parkReference
        self.frequency = frequency
        self.rstSent = rstSent
        self.rstReceived = rstReceived
        self.myGrid = myGrid
        self.theirGrid = theirGrid
        self.notes = notes
        self.rawADIF = rawADIF
        self.name = name
        self.qth = qth
        self.state = state
        self.country = country
        self.power = power
        self.theirLicenseClass = theirLicenseClass
        self.syncedServicesCount = syncedServicesCount
    }

    // MARK: Public

    public let id: UUID
    public let callsign: String
    public let timestamp: Date
    public let band: String
    public let mode: String
    public let parkReference: String?
    public let frequency: Double?

    // Optional fields for merging decisions
    public let rstSent: String?
    public let rstReceived: String?
    public let myGrid: String?
    public let theirGrid: String?
    public let notes: String?
    public let rawADIF: String?
    public let name: String?
    public let qth: String?
    public let state: String?
    public let country: String?
    public let power: Int?
    public let theirLicenseClass: String?

    /// Count of services where this QSO is confirmed present (for winner selection)
    public let syncedServicesCount: Int

    /// Count of populated optional fields (for deduplication tiebreaker)
    public var fieldRichnessScore: Int {
        var score = 0
        if rstSent != nil {
            score += 1
        }
        if rstReceived != nil {
            score += 1
        }
        if myGrid != nil {
            score += 1
        }
        if theirGrid != nil {
            score += 1
        }
        if parkReference != nil {
            score += 1
        }
        if notes != nil {
            score += 1
        }
        if rawADIF != nil {
            score += 1
        }
        if frequency != nil {
            score += 1
        }
        if name != nil {
            score += 1
        }
        if qth != nil {
            score += 1
        }
        if state != nil {
            score += 1
        }
        if country != nil {
            score += 1
        }
        if power != nil {
            score += 1
        }
        if theirLicenseClass != nil {
            score += 1
        }
        return score
    }

    /// Normalized callsign (uppercase)
    public var normalizedCallsign: String {
        callsign.uppercased()
    }

    /// Normalized band (uppercase, trimmed)
    public var normalizedBand: String {
        band.trimmingCharacters(in: .whitespaces).uppercased()
    }

    /// Normalized mode (uppercase)
    public var normalizedMode: String {
        mode.uppercased()
    }

    /// Normalized park reference (uppercase, trimmed, or nil)
    public var normalizedParkReference: String? {
        guard let parkRef = parkReference?.trimmingCharacters(in: .whitespaces),
              !parkRef.isEmpty
        else {
            return nil
        }
        return parkRef.uppercased()
    }
}
