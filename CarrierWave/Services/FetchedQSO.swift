import CarrierWaveCore
import Foundation

// MARK: - FetchedQSO

/// Common format for QSOs fetched from any service
struct FetchedQSO: Sendable {
    let callsign: String
    let band: String
    let mode: String
    let frequency: Double?
    let timestamp: Date
    let rstSent: String?
    let rstReceived: String?
    let myCallsign: String
    let myGrid: String?
    let theirGrid: String?
    let parkReference: String?
    let theirParkReference: String?
    let notes: String?
    let rawADIF: String?

    // Contact info
    let name: String?
    let qth: String?
    let state: String?
    let country: String?
    let power: Int?
    let myRig: String?
    let sotaRef: String?

    // QRZ-specific
    let qrzLogId: String?
    let qrzConfirmed: Bool
    let lotwConfirmedDate: Date?
    let lotwConfirmed: Bool

    /// DXCC entity (from LoTW)
    let dxcc: Int?

    /// Source tracking
    let source: ServiceType

    var deduplicationKey: String {
        let roundedTimestamp = timestamp.timeIntervalSince1970
        let rounded = Int(roundedTimestamp / 120) * 120
        return "\(callsign.uppercased())|\(band.uppercased())|\(mode.uppercased())|\(rounded)"
    }

    /// Debug dictionary for logging
    var debugFields: [String: String] {
        var fields: [String: String] = [
            "callsign": callsign,
            "band": band,
            "mode": mode,
            "timestamp": ISO8601DateFormatter().string(from: timestamp),
            "myCallsign": myCallsign,
        ]
        if let freq = frequency {
            fields["frequency"] = String(format: "%.4f MHz", freq)
        }
        if let grid = myGrid {
            fields["myGrid"] = grid
        }
        if let grid = theirGrid {
            fields["theirGrid"] = grid
        }
        if let park = parkReference {
            fields["parkReference"] = park
        }
        if let park = theirParkReference {
            fields["theirParkReference"] = park
        }
        if let rst = rstSent {
            fields["rstSent"] = rst
        }
        if let rst = rstReceived {
            fields["rstReceived"] = rst
        }
        if let logId = qrzLogId {
            fields["qrzLogId"] = logId
        }
        if let callName = name {
            fields["name"] = callName
        }
        if let qthValue = qth {
            fields["qth"] = qthValue
        }
        if let stateValue = state {
            fields["state"] = stateValue
        }
        if let countryValue = country {
            fields["country"] = countryValue
        }
        if let powerValue = power {
            fields["power"] = String(powerValue)
        }
        if let sota = sotaRef {
            fields["sotaRef"] = sota
        }
        return fields
    }
}

// MARK: - FetchedQSO Factory Methods

extension FetchedQSO {
    /// Create from QRZ fetched QSO
    static func fromQRZ(_ qrz: QRZFetchedQSO) -> FetchedQSO {
        FetchedQSO(
            callsign: qrz.callsign,
            band: qrz.band,
            mode: qrz.mode,
            frequency: qrz.frequency,
            timestamp: qrz.timestamp,
            rstSent: qrz.rstSent,
            rstReceived: qrz.rstReceived,
            myCallsign: qrz.myCallsign ?? "",
            myGrid: qrz.myGrid,
            theirGrid: qrz.theirGrid,
            parkReference: qrz.parkReference.flatMap { ParkReference.sanitizeMulti($0) },
            theirParkReference: qrz.theirParkReference.flatMap { ParkReference.sanitize($0) },
            notes: qrz.notes,
            rawADIF: qrz.rawADIF,
            name: nil,
            qth: nil,
            state: nil,
            country: nil,
            power: nil,
            myRig: nil,
            sotaRef: nil,
            qrzLogId: qrz.qrzLogId,
            qrzConfirmed: qrz.qrzConfirmed,
            lotwConfirmedDate: qrz.lotwConfirmedDate,
            lotwConfirmed: false,
            dxcc: qrz.dxcc,
            source: .qrz
        )
    }

    /// Create from POTA fetched QSO
    static func fromPOTA(_ pota: POTAFetchedQSO) -> FetchedQSO {
        FetchedQSO(
            callsign: pota.callsign,
            band: pota.band,
            mode: pota.mode,
            frequency: nil,
            timestamp: pota.timestamp,
            rstSent: pota.rstSent,
            rstReceived: pota.rstReceived,
            myCallsign: pota.myCallsign,
            myGrid: nil,
            theirGrid: nil,
            parkReference: pota.parkReference.flatMap { ParkReference.sanitizeMulti($0) },
            theirParkReference: nil,
            notes: nil,
            rawADIF: nil,
            name: nil,
            qth: nil,
            state: nil,
            country: nil,
            power: nil,
            myRig: nil,
            sotaRef: nil,
            qrzLogId: nil,
            qrzConfirmed: false,
            lotwConfirmedDate: nil,
            lotwConfirmed: false,
            dxcc: nil,
            source: .pota
        )
    }

    /// Create from LoFi fetched QSO
    static func fromLoFi(_ lofi: LoFiQso, operation: LoFiOperation) -> FetchedQSO? {
        guard let callsign = lofi.theirCall,
              let band = lofi.band,
              let mode = lofi.mode,
              let timestamp = lofi.timestamp
        else {
            return nil
        }

        let parkRef = lofi.myPotaRef(from: operation.refs)

        return FetchedQSO(
            callsign: callsign,
            band: band,
            mode: mode,
            frequency: lofi.freqMHz,
            timestamp: timestamp,
            rstSent: lofi.rstSent,
            rstReceived: lofi.rstRcvd,
            myCallsign: lofi.ourCall ?? operation.stationCall,
            myGrid: operation.grid,
            theirGrid: lofi.theirGrid,
            parkReference: parkRef.flatMap { ParkReference.sanitizeMulti($0) },
            theirParkReference: lofi.theirPotaRef.flatMap { ParkReference.sanitize($0) },
            notes: lofi.notes,
            rawADIF: nil,
            name: lofi.their?.guess?.name,
            qth: nil,
            state: lofi.their?.guess?.state,
            country: lofi.their?.guess?.country,
            power: nil,
            myRig: nil,
            sotaRef: nil,
            qrzLogId: nil,
            qrzConfirmed: false,
            lotwConfirmedDate: nil,
            lotwConfirmed: false,
            dxcc: nil,
            source: .lofi
        )
    }

    /// Create from HAMRS fetched QSO with logbook info
    static func fromHAMRS(_ qso: HAMRSQSO, logbook: HAMRSLogbook) -> FetchedQSO? {
        guard let callsign = qso.call,
              let band = qso.band,
              let mode = qso.mode,
              let timestamp = qso.timestamp
        else {
            return nil
        }

        return FetchedQSO(
            callsign: callsign,
            band: band,
            mode: mode,
            frequency: qso.freq?.doubleValue,
            timestamp: timestamp,
            rstSent: qso.rstSent,
            rstReceived: qso.rstRcvd,
            myCallsign: logbook.operatorCall ?? "",
            myGrid: logbook.myGridsquare,
            theirGrid: qso.gridsquare,
            parkReference: logbook.myPark.flatMap { ParkReference.sanitizeMulti($0) },
            theirParkReference: qso.potaRef.flatMap { ParkReference.sanitize($0) },
            notes: qso.notes,
            rawADIF: nil,
            name: qso.name,
            qth: qso.qth,
            state: qso.state,
            country: qso.country,
            power: qso.txPwr?.intValue,
            myRig: nil,
            sotaRef: qso.sotaRef,
            qrzLogId: nil,
            qrzConfirmed: false,
            lotwConfirmedDate: nil,
            lotwConfirmed: false,
            dxcc: nil,
            source: .hamrs
        )
    }

    /// Create from LoTW fetched QSO
    static func fromLoTW(_ lotw: LoTWFetchedQSO) -> FetchedQSO {
        FetchedQSO(
            callsign: lotw.callsign,
            band: lotw.band,
            mode: lotw.mode,
            frequency: lotw.frequency,
            timestamp: lotw.timestamp,
            rstSent: lotw.rstSent,
            rstReceived: lotw.rstReceived,
            myCallsign: lotw.myCallsign ?? "",
            myGrid: lotw.myGrid,
            theirGrid: lotw.theirGrid,
            parkReference: nil,
            theirParkReference: nil,
            notes: nil,
            rawADIF: lotw.rawADIF,
            name: nil,
            qth: nil,
            state: lotw.state,
            country: lotw.country,
            power: nil,
            myRig: nil,
            sotaRef: nil,
            qrzLogId: nil,
            qrzConfirmed: false,
            lotwConfirmedDate: lotw.qslReceivedDate,
            lotwConfirmed: lotw.qslReceived,
            dxcc: lotw.dxcc,
            source: .lotw
        )
    }
}
