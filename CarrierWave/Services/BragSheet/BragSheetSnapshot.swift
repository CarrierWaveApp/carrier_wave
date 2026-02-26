import CarrierWaveCore
import CoreLocation
import Foundation

// MARK: - BragSheetQSOSnapshot

/// Lightweight, Sendable snapshot of QSO data for brag sheet stat computation.
/// Includes all fields needed for the full stat catalog (distance, power, RST, etc.).
nonisolated struct BragSheetQSOSnapshot: Sendable {
    let id: UUID
    let callsign: String
    let band: String
    let mode: String
    let frequency: Double?
    let timestamp: Date
    let myCallsign: String
    let myGrid: String?
    let theirGrid: String?
    let parkReference: String?
    let theirParkReference: String?
    let dxcc: Int?
    let state: String?
    let country: String?
    let power: Int?
    let rstSent: String?
    let rstReceived: String?
    let loggingSessionId: UUID?

    /// Mode family (CW, phone, digital, other).
    nonisolated var modeFamily: ModeFamily {
        ModeEquivalence.family(for: mode)
    }

    /// Distance in km to the other station, if both grids are available.
    nonisolated var distanceKm: Double? {
        guard let myGrid, myGrid.count >= 4,
              let theirGrid, theirGrid.count >= 4,
              let myCoord = MaidenheadConverter.coordinate(from: myGrid),
              let theirCoord = MaidenheadConverter.coordinate(from: theirGrid)
        else {
            return nil
        }
        let from = CLLocation(latitude: myCoord.latitude, longitude: myCoord.longitude)
        let to = CLLocation(latitude: theirCoord.latitude, longitude: theirCoord.longitude)
        return from.distance(from: to) / 1_000.0
    }

    /// Whether this is a QRP QSO (5W or less).
    nonisolated var isQRP: Bool {
        guard let power else {
            return false
        }
        return power <= 5
    }

    /// Whether this is a milliwatt QSO (less than 1W).
    nonisolated var isMilliwatt: Bool {
        guard let power else {
            return false
        }
        return power < 1
    }

    /// DXCC entity lookup.
    nonisolated var dxccEntity: DXCCEntity? {
        dxcc.flatMap { DescriptionLookup.dxccEntity(forNumber: $0) }
    }

    /// Continent from DXCC entity.
    nonisolated var continent: String? {
        dxcc.flatMap { ContinentMapper.continent(forDXCC: $0) }
    }

    /// UTC date only (for daily grouping).
    nonisolated var utcDateOnly: Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar.startOfDay(for: timestamp)
    }
}

// MARK: - Conversion from QSO

nonisolated extension BragSheetQSOSnapshot {
    init(from qso: QSO) {
        id = qso.id
        callsign = qso.callsign
        band = qso.band
        mode = qso.mode
        frequency = qso.frequency
        timestamp = qso.timestamp
        myCallsign = qso.myCallsign
        myGrid = qso.myGrid
        theirGrid = qso.theirGrid
        parkReference = qso.parkReference
        theirParkReference = qso.theirParkReference
        dxcc = qso.dxcc
        state = qso.state
        country = qso.country
        power = qso.power
        rstSent = qso.rstSent
        rstReceived = qso.rstReceived
        loggingSessionId = qso.loggingSessionId
    }
}
