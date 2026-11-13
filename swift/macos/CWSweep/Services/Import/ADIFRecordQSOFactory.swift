// ADIF Record → QSO Factory
//
// Shared construction path for QSOs that originate as ADIF records: the file
// importer (`ADIFImportActor`) and the S.A.T. satellite-tracker listener
// (`SatLogListenerService`) both go through here so field mapping — including
// the satellite fields SAT_NAME / PROP_MODE — stays in one place.

import CarrierWaveCore
import CarrierWaveData
import Foundation
import SwiftData

enum ADIFRecordQSOFactory {
    /// Build a `QSO` from a parsed ADIF record.
    ///
    /// - Parameters:
    ///   - record: Parsed record from `ADIFParser`.
    ///   - myCallsign: Fallback station callsign when the record has none.
    ///   - importSource: Provenance tag stored on the QSO.
    /// - Throws: `ADIFImportError.missingTimestamp` when the record lacks a date.
    nonisolated static func makeQSO(
        from record: ADIFRecord,
        myCallsign: String,
        importSource: ImportSource
    ) throws -> QSO {
        guard let timestamp = record.timestamp else {
            throw ADIFImportError.missingTimestamp
        }

        let parkReference = record.mySigInfo
            .flatMap { ParkReference.sanitizeMulti($0) }
        let theirParkReference = record.sigInfo
            .flatMap { ParkReference.sanitize($0) }

        return QSO(
            callsign: record.callsign,
            band: record.band,
            mode: record.mode,
            frequency: record.frequency,
            timestamp: timestamp,
            rstSent: record.rstSent,
            rstReceived: record.rstReceived,
            myCallsign: record.myCallsign ?? myCallsign,
            myGrid: record.myGridsquare,
            theirGrid: record.gridsquare,
            parkReference: parkReference,
            theirParkReference: theirParkReference,
            notes: record.comment,
            importSource: importSource,
            rawADIF: record.rawADIF,
            name: record.name,
            qth: record.qth,
            state: record.state,
            wwffRef: record.myWwffRef,
            satName: record.satName,
            propMode: record.propMode
        )
    }

    /// Insert `ServicePresence.needsUpload` rows for every configured upload
    /// service that applies to this QSO (skips metadata pseudo-modes, QSOs
    /// logged under another station callsign, and POTA without a park).
    nonisolated static func attachServicePresence(
        for qso: QSO,
        context: ModelContext,
        myCallsign: String
    ) {
        let qsoCallsign = qso.myCallsign.uppercased()
        let matchesPrimary = qsoCallsign.isEmpty
            || qsoCallsign == myCallsign.uppercased()

        guard !QSOMode.isMetadata(qso.mode), matchesPrimary else {
            return
        }

        let configuredServices = ServiceConfiguration.configuredUploadServices()

        for service in ServiceType.allCases
            where service.supportsUpload && configuredServices.contains(service)
        {
            if service == .pota, qso.parkReference?.isEmpty ?? true {
                continue
            }

            let presence = ServicePresence.needsUpload(
                to: service, qso: qso
            )
            context.insert(presence)
            qso.servicePresence.append(presence)
        }
    }
}
