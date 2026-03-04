import CarrierWaveData
import SwiftData
import XCTest
@testable import CarrierWave

/// Tests for HuntingParkRefRepairService.
///
/// Validates that the repair correctly identifies QSOs where comment-extracted
/// park references were incorrectly assigned to parkReference (activator field)
/// and moves them to theirParkReference (hunter field).
@MainActor
final class HuntingParkRefRepairServiceTests: XCTestCase {
    // MARK: Internal

    override func setUp() async throws {
        try await super.setUp()
        let result = try TestModelContainer.createWithContext()
        container = result.container
        context = result.context
    }

    override func tearDown() async throws {
        container = nil
        context = nil
        try await super.tearDown()
    }

    // MARK: - Empty store

    func testRepairOnEmptyStore() async throws {
        let service = HuntingParkRefRepairService(container: container)
        let result = try await service.repair()

        XCTAssertEqual(result.scanned, 0)
        XCTAssertEqual(result.repaired, 0)
    }

    // MARK: - Repair logic: rawADIF-based detection

    /// QSO with rawADIF lacking MY_SIG_INFO/MY_POTA_REF → parkReference came from comment.
    func testRepairsQSOWithoutMySigInfoInRawADIF() async throws {
        let rawADIF = "<CALL:4>W1AW<BAND:3>20m<MODE:2>CW<COMMENT:15>POTA US-0001 qso<eor>"
        let qso = QSO(
            callsign: "W1AW", band: "20m", mode: "CW",
            timestamp: Date(), myCallsign: "N0TEST",
            parkReference: "US-0001",
            notes: "POTA US-0001 qso",
            importSource: .adifFile, rawADIF: rawADIF
        )
        context.insert(qso)
        try context.save()

        let service = HuntingParkRefRepairService(container: container)
        let result = try await service.repair()

        XCTAssertEqual(result.repaired, 1)

        let descriptor = FetchDescriptor<QSO>()
        let fetched = try XCTUnwrap(try context.fetch(descriptor).first)
        XCTAssertNil(fetched.parkReference, "parkReference should be cleared")
        XCTAssertEqual(fetched.theirParkReference, "US-0001", "Should move to theirParkReference")
    }

    /// QSO with rawADIF containing MY_SIG_INFO → legitimate activation, should NOT repair.
    func testSkipsQSOWithMySigInfoInRawADIF() async throws {
        let rawADIF = "<CALL:4>W1AW<MY_SIG_INFO:7>US-0001<eor>"
        let qso = QSO(
            callsign: "W1AW", band: "20m", mode: "CW",
            timestamp: Date(), myCallsign: "N0TEST",
            parkReference: "US-0001",
            notes: "POTA US-0001",
            importSource: .adifFile, rawADIF: rawADIF
        )
        context.insert(qso)
        try context.save()

        let service = HuntingParkRefRepairService(container: container)
        let result = try await service.repair()

        XCTAssertEqual(result.repaired, 0)
    }

    /// QSO with rawADIF containing MY_POTA_REF → legitimate activation, should NOT repair.
    func testSkipsQSOWithMyPotaRefInRawADIF() async throws {
        let rawADIF = "<CALL:4>W1AW<MY_POTA_REF:7>US-0001<eor>"
        let qso = QSO(
            callsign: "W1AW", band: "20m", mode: "CW",
            timestamp: Date(), myCallsign: "N0TEST",
            parkReference: "US-0001",
            notes: "POTA US-0001",
            importSource: .adifFile, rawADIF: rawADIF
        )
        context.insert(qso)
        try context.save()

        let service = HuntingParkRefRepairService(container: container)
        let result = try await service.repair()

        XCTAssertEqual(result.repaired, 0)
    }

    // MARK: - Repair logic: no rawADIF (fallback to notes matching)

    /// QSO without rawADIF where parkReference matches extractFromFreeText(notes) → repair.
    func testRepairsQSOWithoutRawADIFWhenNotesMatch() async throws {
        let qso = QSO(
            callsign: "W1AW", band: "20m", mode: "CW",
            timestamp: Date(), myCallsign: "N0TEST",
            parkReference: "US-0001",
            notes: "POTA US-0001 activation",
            importSource: .adifFile
        )
        context.insert(qso)
        try context.save()

        let service = HuntingParkRefRepairService(container: container)
        let result = try await service.repair()

        XCTAssertEqual(result.repaired, 1)

        let fetched = try XCTUnwrap(try context.fetch(FetchDescriptor<QSO>()).first)
        XCTAssertNil(fetched.parkReference)
        XCTAssertEqual(fetched.theirParkReference, "US-0001")
    }

    // MARK: - Preserves existing theirParkReference

    /// When theirParkReference already has a value, don't overwrite it.
    func testDoesNotOverwriteExistingTheirParkReference() async throws {
        let rawADIF = "<CALL:4>W1AW<COMMENT:15>POTA US-0001 qso<eor>"
        let qso = QSO(
            callsign: "W1AW", band: "20m", mode: "CW",
            timestamp: Date(), myCallsign: "N0TEST",
            parkReference: "US-0001", theirParkReference: "US-0099",
            notes: "POTA US-0001 qso",
            importSource: .adifFile, rawADIF: rawADIF
        )
        context.insert(qso)
        try context.save()

        let service = HuntingParkRefRepairService(container: container)
        let result = try await service.repair()

        XCTAssertEqual(result.repaired, 1)

        let fetched = try XCTUnwrap(try context.fetch(FetchDescriptor<QSO>()).first)
        XCTAssertNil(fetched.parkReference, "parkReference should be cleared")
        XCTAssertEqual(fetched.theirParkReference, "US-0099", "Existing theirParkReference preserved")
    }

    // MARK: - Skips hidden QSOs

    func testSkipsHiddenQSOs() async throws {
        let qso = QSO(
            callsign: "W1AW", band: "20m", mode: "CW",
            timestamp: Date(), myCallsign: "N0TEST",
            parkReference: "US-0001",
            notes: "POTA US-0001",
            importSource: .adifFile
        )
        qso.isHidden = true
        context.insert(qso)
        try context.save()

        let service = HuntingParkRefRepairService(container: container)
        let result = try await service.repair()

        XCTAssertEqual(result.scanned, 0)
    }

    // MARK: Private

    private var container: ModelContainer!
    private var context: ModelContext!
}
