import CarrierWaveCore
import Foundation

// MARK: - QSOFields ↔ FfiQso (the journal ⇄ Rust-store seam for Phase 1b)

//
// The CloudKit journal wire format is `QSOFields`; the Rust store speaks `FfiQso`.
// These converters let the journal engine read/write QSOs through `FieldStore`
// instead of `ModelContext` WITHOUT changing the journal format or resolver.
//
// Conventions MUST match `SwiftDataStoreImporter.project(_ qso:)` exactly — the
// id string (lowercased uuid), the MHz→kHz frequency scale, and the epoch-second
// timestamps — otherwise an inbound apply would create a *duplicate* store row
// instead of updating the mirror's row. The shared `uuid`/`unix` helpers are
// reused so the two paths can never drift.
//
// `QSOFields` is a strict SUBSET of `FfiQso`: it carries no
// `callsignChangeNote`/`originalCallsign`/`aoaCode`/`contest*` and no `dirty`
// flag. On apply those FfiQso-only columns are PRESERVED from the existing row
// (mirroring SwiftData's `applyQSOFields`, which only writes the wire fields and
// leaves the rest of the `@Model` untouched).

extension QSOFields {
    /// Project these journal fields onto an `FfiQso` ready for `upsertQso`.
    ///
    /// `dirty` is supplied by the caller (inbound applies land clean; the journal
    /// never re-dirties an inbound row). `existing` carries the FfiQso-only
    /// columns forward so an inbound apply doesn't wipe locally-held fields the
    /// wire format can't represent.
    func toFfiQso(dirty: Bool, preserving existing: FfiQso? = nil) -> FfiQso {
        FfiQso(
            id: SwiftDataStoreImporter.uuid(id),
            callsign: callsign,
            band: band, mode: mode,
            // `frequency` is MHz in the wire format; the store column is kHz.
            freqKhz: frequency.map { $0 * 1_000 },
            qsoDate: Int64(timestamp.timeIntervalSince1970),
            myGrid: myGrid,
            theirGrid: theirGrid,
            rstSent: rstSent,
            rstRcvd: rstReceived,
            myCallsign: myCallsign,
            park: parkReference,
            theirPark: theirParkReference,
            notes: notes,
            notesUserAuthored: notesUserAuthored,
            spotCommentsData: spotCommentsData,
            // Not in the wire format — preserve from the existing store row.
            callsignChangeNote: existing?.callsignChangeNote,
            originalCallsign: existing?.originalCallsign,
            importSourceRawValue: importSource.rawValue,
            importedAt: Int64(importedAt.timeIntervalSince1970),
            modifiedAt: modifiedAt.map { Int64($0.timeIntervalSince1970) },
            rawAdif: rawADIF,
            name: name,
            qth: qth, state: state, country: country,
            power: power.map(Int64.init),
            myRig: myRig,
            stationProfileName: stationProfileName,
            sotaRef: sotaRef,
            wwffRef: wwffRef,
            aoaCode: existing?.aoaCode, // not in wire format — preserve
            qrzLogId: qrzLogId,
            qrzConfirmed: qrzConfirmed,
            lotwConfirmedDate: lotwConfirmedDate.map { Int64($0.timeIntervalSince1970) },
            lotwConfirmed: lotwConfirmed,
            dxcc: dxcc.map(Int64.init),
            theirLicenseClass: theirLicenseClass,
            // Contest columns are not in the wire format — preserve.
            contestName: existing?.contestName,
            contestSerialSent: existing?.contestSerialSent,
            contestSerialReceived: existing?.contestSerialReceived,
            contestExchangeSent: existing?.contestExchangeSent,
            contestExchangeReceived: existing?.contestExchangeReceived,
            isHidden: isHidden,
            isActivityLogQso: isActivityLogQSO,
            stationCallsign: stationCallsign,
            loggingSessionId: loggingSessionId.map { SwiftDataStoreImporter.uuid($0) },
            dirty: dirty,
            satName: satName,
            propMode: propMode,
            // Presence is mirrored as separate service_presence rows, never via
            // the QSO upsert (matches the importer projection).
            presence: []
        )
    }
}

extension FfiQso {
    /// Recover the journal wire fields from a stored row, so the conflict
    /// resolver (which speaks `QSOFields`) can merge an inbound change against
    /// the local row. Returns `nil` only if the stored id is not a valid UUID
    /// (which would indicate a corrupt row, never a real one).
    ///
    /// The FfiQso-only columns are dropped here; callers re-attach them via
    /// `toFfiQso(preserving:)`. `importSourceRawValue` falls back to `.icloud`
    /// (the sync-origin source) for the theoretically-impossible unknown value.
    func toQSOFields() -> QSOFields? {
        guard let qsoId = UUID(uuidString: id) else {
            return nil
        }
        return QSOFields(
            id: qsoId,
            callsign: callsign,
            band: band ?? "",
            mode: mode ?? "",
            // Store column is kHz; the wire format is MHz.
            frequency: freqKhz.map { $0 / 1_000 },
            timestamp: Date(timeIntervalSince1970: TimeInterval(qsoDate)),
            rstSent: rstSent,
            rstReceived: rstRcvd,
            myCallsign: myCallsign ?? "",
            myGrid: myGrid,
            theirGrid: theirGrid,
            parkReference: park,
            theirParkReference: theirPark,
            notes: notes,
            importSource: ImportSource(rawValue: importSourceRawValue) ?? .icloud,
            importedAt: Date(timeIntervalSince1970: TimeInterval(importedAt)),
            modifiedAt: modifiedAt.map { Date(timeIntervalSince1970: TimeInterval($0)) },
            rawADIF: rawAdif,
            name: name,
            qth: qth,
            state: state,
            country: country,
            power: power.map(Int.init),
            myRig: myRig,
            stationProfileName: stationProfileName,
            sotaRef: sotaRef,
            wwffRef: wwffRef,
            qrzLogId: qrzLogId,
            qrzConfirmed: qrzConfirmed,
            lotwConfirmedDate: lotwConfirmedDate.map { Date(timeIntervalSince1970: TimeInterval($0)) },
            lotwConfirmed: lotwConfirmed,
            dxcc: dxcc.map(Int.init),
            theirLicenseClass: theirLicenseClass,
            isHidden: isHidden,
            isActivityLogQSO: isActivityLogQso,
            loggingSessionId: loggingSessionId.flatMap { UUID(uuidString: $0) },
            stationCallsign: stationCallsign,
            spotCommentsData: spotCommentsData,
            notesUserAuthored: notesUserAuthored,
            satName: satName,
            propMode: propMode
        )
    }
}
