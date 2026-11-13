import CarrierWaveCore
import CarrierWaveData
import SwiftData
import XCTest
@testable import CarrierWave

/// Tests for `MetadataUploadFlagRepairService` (CAR-278).
///
/// PoLo marker rows (every `QSOMode.metadataModes` entry) that were imported with
/// `needsUpload=true` must have every such flag cleared, for every service, while
/// real QSOs' pending flags are left alone. The repair must be idempotent.
@MainActor
final class MetadataUploadFlagRepairServiceTests: XCTestCase {
    // MARK: Internal

    override func setUp() async throws {
        try await super.setUp()
        let schema = Schema(AppSchema.models)
        // Mirror the app (`CarrierWaveApp`): SwiftData must never drive CloudKit.
        // `.automatic` picks up the host's iCloud entitlement and rejects the schema.
        let config = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        container = try ModelContainer(for: schema, configurations: [config])
        context = container.mainContext
    }

    override func tearDown() async throws {
        container = nil
        context = nil
        try await super.tearDown()
    }

    // MARK: - Clearing

    /// Every PoLo marker mode with a pending QRZ presence gets cleared.
    func testClearsPendingFlagsForEveryMarkerMode() async throws {
        let modes = ["WEATHER", "SOLAR", "NOTE", "TODO", "START", "BREAK"]
        for mode in modes {
            let qso = QSOFactory.metadataRecord(mode: mode)
            context.insert(qso)
            attachPresence(to: qso, service: .qrz, needsUpload: true)
        }
        try context.save()

        let result = try await MetadataUploadFlagRepairService(container: container).repair()

        XCTAssertEqual(result.clearedCount, modes.count)
        XCTAssertEqual(result.byService[.qrz], modes.count)
        XCTAssertEqual(try pendingPresenceCount(), 0)
    }

    /// Flags are cleared for every service, not just QRZ (POTA two-fer rows included).
    func testClearsAcrossAllServices() async throws {
        let qso = QSOFactory.metadataRecord(mode: "SOLAR", parkReference: "US-0001")
        context.insert(qso)
        attachPresence(to: qso, service: .qrz, needsUpload: true)
        attachPresence(to: qso, service: .eqsl, needsUpload: true)
        attachPresence(to: qso, service: .pota, needsUpload: true, parkReference: "US-0001")
        // A stuck isSubmitted row should be reset too.
        let submitted = attachPresence(to: qso, service: .pota, needsUpload: true)
        submitted.isSubmitted = true
        try context.save()

        let result = try await MetadataUploadFlagRepairService(container: container).repair()

        XCTAssertEqual(result.clearedCount, 4)
        XCTAssertEqual(result.byService[.qrz], 1)
        XCTAssertEqual(result.byService[.eqsl], 1)
        XCTAssertEqual(result.byService[.pota], 2)

        let all = try context.fetch(FetchDescriptor<ServicePresence>())
        XCTAssertEqual(all.count, 4)
        for presence in all {
            XCTAssertFalse(presence.needsUpload, "\(presence.serviceType) should be cleared")
            XCTAssertFalse(presence.isSubmitted, "\(presence.serviceType) should not stay submitted")
            XCTAssertTrue(presence.cloudDirtyFlag, "cleared rows must be dirtied for CloudKit")
        }
    }

    /// Classification is case-insensitive (PoLo/LoFi may deliver mixed case).
    func testClearsMixedCaseModes() async throws {
        for mode in ["weather", "Break", "sTaRt"] {
            let qso = QSO.testQSO(callsign: "METADATA", band: "", mode: mode, importSource: .lofi)
            context.insert(qso)
            attachPresence(to: qso, service: .qrz, needsUpload: true)
        }
        try context.save()

        let result = try await MetadataUploadFlagRepairService(container: container).repair()

        XCTAssertEqual(result.clearedCount, 3)
        XCTAssertEqual(try pendingPresenceCount(), 0)
    }

    // MARK: - Preservation

    /// Real QSOs' pending flags are untouched.
    func testLeavesRealQSOsPending() async throws {
        let real = QSO.testQSO(callsign: "W1AW", mode: "CW", importSource: .lofi)
        context.insert(real)
        attachPresence(to: real, service: .qrz, needsUpload: true)
        attachPresence(to: real, service: .eqsl, needsUpload: true)

        let meta = QSOFactory.metadataRecord(mode: "WEATHER")
        context.insert(meta)
        attachPresence(to: meta, service: .qrz, needsUpload: true)
        try context.save()

        let result = try await MetadataUploadFlagRepairService(container: container).repair()

        XCTAssertEqual(result.clearedCount, 1)
        let remaining = try pendingPresences()
        XCTAssertEqual(remaining.count, 2)
        XCTAssertTrue(remaining.allSatisfy { $0.qso?.callsign == "W1AW" })
    }

    /// Metadata rows that are already clear (or present) are not counted or modified.
    func testIgnoresAlreadyClearedMetadata() async throws {
        let meta = QSOFactory.metadataRecord(mode: "NOTE")
        context.insert(meta)
        attachPresence(to: meta, service: .qrz, needsUpload: false)
        let downloaded = attachPresence(to: meta, service: .lofi, needsUpload: false)
        downloaded.isPresent = true
        try context.save()

        let result = try await MetadataUploadFlagRepairService(container: container).repair()

        XCTAssertEqual(result.clearedCount, 0)
        XCTAssertTrue(result.byService.isEmpty)
        let lofi = try context.fetch(FetchDescriptor<ServicePresence>())
            .first { $0.serviceType == .lofi }
        XCTAssertEqual(lofi?.isPresent, true, "downloaded-from-LoFi presence must survive")
    }

    // MARK: - Idempotence / batching

    /// A second run is a no-op.
    func testSecondRunIsNoOp() async throws {
        for mode in ["SOLAR", "BREAK"] {
            let qso = QSOFactory.metadataRecord(mode: mode)
            context.insert(qso)
            attachPresence(to: qso, service: .qrz, needsUpload: true)
        }
        try context.save()

        let service = MetadataUploadFlagRepairService(container: container)
        let first = try await service.repair()
        let second = try await service.repair()

        XCTAssertEqual(first.clearedCount, 2)
        XCTAssertEqual(second.clearedCount, 0)
    }

    /// Cleared rows leave the `needsUpload` predicate, so the offset must not skip
    /// rows when the batch size is smaller than the pending set. Interleave real
    /// and metadata rows so a naive `offset += batch.count` would miss some.
    func testSmallBatchesClearEverything() async throws {
        for index in 0 ..< 9 {
            let qso: QSO =
                if index.isMultiple(of: 2) {
                    QSOFactory.metadataRecord(mode: "START")
                } else {
                    QSO.testQSO(callsign: "K\(index)ABC", importSource: .lofi)
                }
            context.insert(qso)
            attachPresence(to: qso, service: .qrz, needsUpload: true)
        }
        try context.save()

        let result = try await MetadataUploadFlagRepairService(
            container: container, batchSize: 2
        ).repair()

        XCTAssertEqual(result.clearedCount, 5)
        let remaining = try pendingPresences()
        XCTAssertEqual(remaining.count, 4)
        XCTAssertTrue(remaining.allSatisfy { !QSOMode.isMetadata($0.qso?.mode ?? "") })
    }

    /// Empty store produces zero repairs.
    func testEmptyStoreReturnsZero() async throws {
        let result = try await MetadataUploadFlagRepairService(container: container).repair()
        XCTAssertEqual(result.clearedCount, 0)
        XCTAssertTrue(result.byService.isEmpty)
    }

    // MARK: Private

    private var container: ModelContainer!
    private var context: ModelContext!

    @discardableResult
    private func attachPresence(
        to qso: QSO,
        service: ServiceType,
        needsUpload: Bool,
        parkReference: String? = nil
    ) -> ServicePresence {
        let presence = ServicePresence(
            serviceType: service,
            isPresent: false,
            needsUpload: needsUpload,
            qso: qso,
            parkReference: parkReference
        )
        context.insert(presence)
        qso.servicePresence.append(presence)
        return presence
    }

    private func pendingPresences() throws -> [ServicePresence] {
        try context.fetch(
            FetchDescriptor<ServicePresence>(predicate: #Predicate { $0.needsUpload })
        )
    }

    private func pendingPresenceCount() throws -> Int {
        try pendingPresences().count
    }
}
