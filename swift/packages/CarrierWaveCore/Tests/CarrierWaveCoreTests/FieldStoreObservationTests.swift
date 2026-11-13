//
//  FieldStoreObservationTests.swift
//  CarrierWaveCoreTests
//
//  End-to-end gate for the store observation API — the SwiftData `@Query`
//  replacement (see docs/plans/2026-06-13-rust-core-handoff.md, Phase 4).
//
//  Drives `FieldStore.changes(for:)` across the UniFFI boundary: an upsert in
//  Rust must surface as an `FfiStoreChange` on the Swift `AsyncStream`, and the
//  realistic flow (change arrives → re-fetch → see new data) must work without
//  deadlock — the Rust side fires the callback with the DB lock released.
//

import CarrierWaveCwFfi
import Testing

struct FieldStoreObservationTests {
    // MARK: Internal

    @Test("changes(for:) yields a QSO upsert change")
    func qsoUpsertYieldsChange() async throws {
        let store = try FieldStore.openInMemory(key: "test-key")
        // The AsyncStream build closure registers the observer synchronously, so
        // the upsert below is observed.
        var iterator = store.changes(for: .qso).makeAsyncIterator()

        try store.upsertQso(qso: Self.sampleQso(id: "1"))

        let change = await iterator.next()
        #expect(change?.table == .qso)
        #expect(change?.kind == .upsert)
    }

    @Test("re-fetch from the change consumer sees the committed write")
    func reFetchAfterChangeSeesWrite() async throws {
        let store = try FieldStore.openInMemory(key: "test-key")
        var iterator = store.changes(for: .qso).makeAsyncIterator()

        try store.upsertQso(qso: Self.sampleQso(id: "1"))
        _ = await iterator.next()

        // The realistic @Query-replacement path: re-fetch on change. Must not
        // deadlock and must see the just-committed row.
        #expect(try store.qsoCount() == 1)
    }

    // MARK: Private

    private static func sampleQso(id: String) -> FfiQso {
        FfiQso(
            id: id,
            callsign: "W1AW",
            band: "20m",
            mode: "FT8",
            freqKhz: 14_074.0,
            qsoDate: 1_000,
            myGrid: nil,
            theirGrid: nil,
            rstSent: nil,
            rstRcvd: nil,
            myCallsign: nil,
            park: nil,
            theirPark: nil,
            notes: nil,
            notesUserAuthored: false,
            spotCommentsData: nil,
            callsignChangeNote: nil,
            originalCallsign: nil,
            importSourceRawValue: "logger",
            importedAt: 1_000,
            modifiedAt: nil,
            rawAdif: nil,
            name: nil,
            qth: nil,
            state: nil,
            country: nil,
            power: nil,
            myRig: nil,
            stationProfileName: nil,
            sotaRef: nil,
            wwffRef: nil,
            aoaCode: nil,
            qrzLogId: nil,
            qrzConfirmed: false,
            lotwConfirmedDate: nil,
            lotwConfirmed: false,
            dxcc: nil,
            theirLicenseClass: nil,
            contestName: nil,
            contestSerialSent: nil,
            contestSerialReceived: nil,
            contestExchangeSent: nil,
            contestExchangeReceived: nil,
            isHidden: false,
            isActivityLogQso: false,
            stationCallsign: nil,
            loggingSessionId: nil,
            dirty: true,
            satName: nil,
            propMode: nil,
            presence: []
        )
    }
}
