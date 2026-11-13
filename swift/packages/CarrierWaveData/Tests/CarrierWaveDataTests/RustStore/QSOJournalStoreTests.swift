import CarrierWaveCore
import Foundation
import XCTest
@testable import CarrierWaveData

// MARK: - QSOJournalStoreTests

/// Covers the Phase 1b QSO journal seam: the `QSOFields ↔ FfiQso` mapping and the
/// `QSOJournalStore` store-access ops against an in-memory `FieldStore`.
@MainActor
final class QSOJournalStoreTests: XCTestCase {
    // MARK: Internal

    // MARK: - Mapping round-trip

    func testQSOFieldsRoundTripsThroughFfiQso() throws {
        let id = UUID()
        let fields = Self.sampleFields(
            id: id, frequencyMHz: 14.074, modifiedAt: Date(timeIntervalSince1970: 2_000)
        )
        let ffi = fields.toFfiQso(dirty: true)

        // Store conventions match the importer projection.
        XCTAssertEqual(ffi.id, id.uuidString.lowercased())
        XCTAssertEqual(ffi.freqKhz ?? 0, 14_074, accuracy: 0.001)
        XCTAssertEqual(ffi.qsoDate, 1_000)
        XCTAssertTrue(ffi.dirty)

        let back = try XCTUnwrap(ffi.toQSOFields())
        XCTAssertEqual(back.id, id)
        XCTAssertEqual(back.callsign, "W1AW")
        XCTAssertEqual(back.band, "20m")
        XCTAssertEqual(back.frequency ?? 0, 14.074, accuracy: 1e-9)
        XCTAssertEqual(back.importSource, .logger)
        XCTAssertEqual(back.power, 5)
        XCTAssertEqual(back.modifiedAt, fields.modifiedAt)
    }

    func testToFfiQsoPreservesNonWireColumnsFromExisting() {
        let fields = Self.sampleFields()
        var existing = fields.toFfiQso(dirty: false)
        existing.contestName = "CQWW"
        existing.contestExchangeSent = "599 03"
        existing.aoaCode = "SOTA/W6-001"
        existing.callsignChangeNote = "ex-KK6XXX"

        // Applying wire fields must carry the FfiQso-only columns forward.
        let applied = fields.toFfiQso(dirty: false, preserving: existing)
        XCTAssertEqual(applied.contestName, "CQWW")
        XCTAssertEqual(applied.contestExchangeSent, "599 03")
        XCTAssertEqual(applied.aoaCode, "SOTA/W6-001")
        XCTAssertEqual(applied.callsignChangeNote, "ex-KK6XXX")
    }

    // MARK: - Outbound: dirty page

    func testDirtyQSOPageSplitsMetadataFromReal() throws {
        let store = try FieldStore.openInMemory(key: "dirty-page")
        let seam = QSOJournalStore(store: store)
        try store.upsertQso(qso: Self.sampleFields(mode: "CW").toFfiQso(dirty: true))
        try store.upsertQso(qso: Self.sampleFields(mode: "WEATHER").toFfiQso(dirty: true))
        try store.upsertQso(qso: Self.sampleFields(mode: "SSB").toFfiQso(dirty: false))

        let page = try seam.dirtyQSOPage()
        XCTAssertEqual(page.emittable.count, 1, "only the dirty, non-metadata QSO emits")
        XCTAssertEqual(page.emittable.first?.mode, "CW")
        XCTAssertEqual(page.metadataModeIds.count, 1, "dirty metadata-mode QSO is clear-only")
    }

    // MARK: - clearDirty (CAR-245)

    func testClearDirtyKeepsRowsModifiedAfterSnapshot() throws {
        let store = try FieldStore.openInMemory(key: "clear-dirty")
        let seam = QSOJournalStore(store: store)
        let staleId = UUID()
        let editedId = UUID()
        try store.upsertQso(qso: Self.sampleFields(
            id: staleId, modifiedAt: Date(timeIntervalSince1970: 50)
        ).toFfiQso(dirty: true))
        try store.upsertQso(qso: Self.sampleFields(
            id: editedId, modifiedAt: Date(timeIntervalSince1970: 200)
        ).toFfiQso(dirty: true))

        let cleared = try seam.clearDirty(
            ids: [staleId, editedId], notIfModifiedAfter: Date(timeIntervalSince1970: 100)
        )
        XCTAssertEqual(cleared, 1, "only the stale row clears; the post-snapshot edit stays dirty")

        let stillDirty = try seam.dirtyQSOPage()
        XCTAssertEqual(stillDirty.emittable.map(\.id), [editedId])
    }

    func testMarkAllDirtyMarksRealQSOs() throws {
        let store = try FieldStore.openInMemory(key: "mark-all")
        let seam = QSOJournalStore(store: store)
        try store.upsertQso(qso: Self.sampleFields(mode: "CW").toFfiQso(dirty: false))
        try store.upsertQso(qso: Self.sampleFields(mode: "NOTE").toFfiQso(dirty: false))

        let marked = try seam.markAllDirty()
        XCTAssertEqual(marked, 1, "metadata-mode QSO is not marked")
    }

    // MARK: - Inbound apply

    func testApplyInboundInsertsNewRowClean() throws {
        let store = try FieldStore.openInMemory(key: "inbound-new")
        let seam = QSOJournalStore(store: store)
        let fields = Self.sampleFields()

        try seam.applyInbound(fields, remoteTimestamp: Date(timeIntervalSince1970: 5_000))

        let stored = try XCTUnwrap(store.fetchQso(id: fields.id.uuidString.lowercased()))
        XCTAssertEqual(stored.callsign, "W1AW")
        XCTAssertFalse(stored.dirty, "inbound applies land clean — no sync ping-pong")
    }

    func testApplyInboundMergesAndPreservesDirtyAndNonWireColumns() throws {
        let store = try FieldStore.openInMemory(key: "inbound-merge")
        let seam = QSOJournalStore(store: store)
        let id = UUID()

        // Seed a local row: dirty, with an FfiQso-only contest column set, and an
        // older modifiedAt than the incoming remote (so remote wins the name).
        var local = Self.sampleFields(
            id: id, modifiedAt: Date(timeIntervalSince1970: 1_000)
        ).toFfiQso(dirty: true)
        local.contestName = "CQWW"
        local.name = "OldName"
        try store.upsertQso(qso: local)

        var remote = Self.sampleFields(id: id, modifiedAt: Date(timeIntervalSince1970: 9_000))
        remote = Self.withName(remote, "NewName")
        try seam.applyInbound(remote, remoteTimestamp: Date(timeIntervalSince1970: 9_000))

        let merged = try XCTUnwrap(store.fetchQso(id: id.uuidString.lowercased()))
        XCTAssertEqual(merged.name, "NewName", "remote (newer) wins the merged field")
        XCTAssertEqual(merged.contestName, "CQWW", "FfiQso-only column preserved through merge")
        XCTAssertTrue(merged.dirty, "existing dirty flag preserved (no ping-pong reset)")
    }

    // MARK: - softDelete + bootstrap gate

    func testSoftDeleteHidesRow() throws {
        let store = try FieldStore.openInMemory(key: "soft-delete")
        let seam = QSOJournalStore(store: store)
        let fields = Self.sampleFields()
        try store.upsertQso(qso: fields.toFfiQso(dirty: false))

        try seam.softDelete(id: fields.id)

        let stored = try XCTUnwrap(store.fetchQso(id: fields.id.uuidString.lowercased()))
        XCTAssertTrue(stored.isHidden)
        XCTAssertFalse(try seam.hasVisibleQSO(), "hidden row does not count as visible")
    }

    func testHasVisibleQSOReflectsVisibleRows() throws {
        let store = try FieldStore.openInMemory(key: "has-visible")
        let seam = QSOJournalStore(store: store)
        XCTAssertFalse(try seam.hasVisibleQSO())
        try store.upsertQso(qso: Self.sampleFields().toFfiQso(dirty: false))
        XCTAssertTrue(try seam.hasVisibleQSO())
    }

    // MARK: Private

    // MARK: - Fixtures

    private static func sampleFields(
        id: UUID = UUID(),
        callsign: String = "W1AW",
        mode: String = "CW",
        frequencyMHz: Double? = 14.074,
        modifiedAt: Date? = nil,
        isHidden: Bool = false
    ) -> QSOFields {
        QSOFields(
            id: id, callsign: callsign, band: "20m", mode: mode, frequency: frequencyMHz,
            timestamp: Date(timeIntervalSince1970: 1_000), rstSent: "599", rstReceived: "599",
            myCallsign: "W6JY", myGrid: "CM87", theirGrid: "FN31", parkReference: nil,
            theirParkReference: nil, notes: nil, importSource: .logger,
            importedAt: Date(timeIntervalSince1970: 1_000), modifiedAt: modifiedAt, rawADIF: nil,
            name: nil, qth: nil, state: nil, country: nil, power: 5, myRig: nil,
            stationProfileName: nil, sotaRef: nil, wwffRef: nil, qrzLogId: nil, qrzConfirmed: false,
            lotwConfirmedDate: nil, lotwConfirmed: false, dxcc: nil, theirLicenseClass: nil,
            isHidden: isHidden, isActivityLogQSO: false, loggingSessionId: nil
        )
    }

    /// Rebuild `fields` with a new `name` (QSOFields is immutable).
    private static func withName(_ fields: QSOFields, _ name: String) -> QSOFields {
        QSOFields(
            id: fields.id, callsign: fields.callsign, band: fields.band, mode: fields.mode,
            frequency: fields.frequency, timestamp: fields.timestamp, rstSent: fields.rstSent,
            rstReceived: fields.rstReceived, myCallsign: fields.myCallsign, myGrid: fields.myGrid,
            theirGrid: fields.theirGrid, parkReference: fields.parkReference,
            theirParkReference: fields.theirParkReference, notes: fields.notes,
            importSource: fields.importSource, importedAt: fields.importedAt,
            modifiedAt: fields.modifiedAt, rawADIF: fields.rawADIF, name: name, qth: fields.qth,
            state: fields.state, country: fields.country, power: fields.power, myRig: fields.myRig,
            stationProfileName: fields.stationProfileName, sotaRef: fields.sotaRef,
            wwffRef: fields.wwffRef, qrzLogId: fields.qrzLogId, qrzConfirmed: fields.qrzConfirmed,
            lotwConfirmedDate: fields.lotwConfirmedDate, lotwConfirmed: fields.lotwConfirmed,
            dxcc: fields.dxcc, theirLicenseClass: fields.theirLicenseClass, isHidden: fields.isHidden,
            isActivityLogQSO: fields.isActivityLogQSO, loggingSessionId: fields.loggingSessionId
        )
    }
}
