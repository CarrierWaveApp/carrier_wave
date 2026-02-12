import CarrierWaveCore
import SwiftData
import XCTest
@testable import CarrierWave

final class DeduplicationServiceTests: XCTestCase {
    var modelContainer: ModelContainer!
    var modelContext: ModelContext!

    @MainActor
    override func setUp() async throws {
        let schema = Schema([QSO.self, ServicePresence.self, UploadDestination.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        modelContainer = try ModelContainer(for: schema, configurations: [config])
        modelContext = modelContainer.mainContext
    }

    @MainActor
    func testNoDuplicates() throws {
        // Create two different QSOs
        let qso1 = QSO(
            callsign: "W1AW", band: "20m", mode: "CW",
            timestamp: Date(), myCallsign: "N0CALL", importSource: .adifFile
        )
        let qso2 = QSO(
            callsign: "K3LR", band: "40m", mode: "SSB",
            timestamp: Date(), myCallsign: "N0CALL", importSource: .adifFile
        )
        modelContext.insert(qso1)
        modelContext.insert(qso2)
        try modelContext.save()

        let service = DeduplicationService(modelContext: modelContext)
        let result = try service.findAndMergeDuplicates(timeWindowMinutes: 5)

        XCTAssertEqual(result.duplicateGroupsFound, 0)
        XCTAssertEqual(result.qsosRemoved, 0)

        let qsos = try modelContext.fetch(FetchDescriptor<QSO>())
        XCTAssertEqual(qsos.count, 2)
    }

    @MainActor
    func testExactDuplicatesWithinWindow() throws {
        let baseTime = Date()

        // Create two identical QSOs 2 minutes apart
        let qso1 = QSO(
            callsign: "W1AW", band: "20m", mode: "CW",
            timestamp: baseTime, myCallsign: "N0CALL", importSource: .adifFile
        )
        let qso2 = QSO(
            callsign: "W1AW", band: "20m", mode: "CW",
            timestamp: baseTime.addingTimeInterval(120), myCallsign: "N0CALL",
            importSource: .adifFile
        )
        modelContext.insert(qso1)
        modelContext.insert(qso2)
        try modelContext.save()

        let service = DeduplicationService(modelContext: modelContext)
        let result = try service.findAndMergeDuplicates(timeWindowMinutes: 5)

        XCTAssertEqual(result.duplicateGroupsFound, 1)
        XCTAssertEqual(result.qsosRemoved, 1)

        let qsos = try modelContext.fetch(FetchDescriptor<QSO>())
        XCTAssertEqual(qsos.count, 1)
    }

    @MainActor
    func testDuplicatesOutsideWindow() throws {
        let baseTime = Date()

        // Create two identical QSOs 10 minutes apart (outside 5-min window)
        let qso1 = QSO(
            callsign: "W1AW", band: "20m", mode: "CW",
            timestamp: baseTime, myCallsign: "N0CALL", importSource: .adifFile
        )
        let qso2 = QSO(
            callsign: "W1AW", band: "20m", mode: "CW",
            timestamp: baseTime.addingTimeInterval(600), myCallsign: "N0CALL",
            importSource: .adifFile
        )
        modelContext.insert(qso1)
        modelContext.insert(qso2)
        try modelContext.save()

        let service = DeduplicationService(modelContext: modelContext)
        let result = try service.findAndMergeDuplicates(timeWindowMinutes: 5)

        XCTAssertEqual(result.duplicateGroupsFound, 0)

        let qsos = try modelContext.fetch(FetchDescriptor<QSO>())
        XCTAssertEqual(qsos.count, 2)
    }

    @MainActor
    func testPrefersSyncedQSO() throws {
        let baseTime = Date()

        // Create two duplicates, one with sync status
        let qso1 = QSO(
            callsign: "W1AW", band: "20m", mode: "CW",
            timestamp: baseTime, myCallsign: "N0CALL", importSource: .adifFile
        )
        let qso2 = QSO(
            callsign: "W1AW", band: "20m", mode: "CW",
            timestamp: baseTime.addingTimeInterval(60), myCallsign: "N0CALL",
            importSource: .adifFile,
            qrzLogId: "12345"
        )

        modelContext.insert(qso1)
        modelContext.insert(qso2)

        // Mark qso2 as present in QRZ
        let presence = ServicePresence.downloaded(from: .qrz, qso: qso2)
        modelContext.insert(presence)
        qso2.servicePresence.append(presence)

        try modelContext.save()

        let service = DeduplicationService(modelContext: modelContext)
        _ = try service.findAndMergeDuplicates(timeWindowMinutes: 5)

        let qsos = try modelContext.fetch(FetchDescriptor<QSO>())
        XCTAssertEqual(qsos.count, 1)
        XCTAssertEqual(qsos[0].qrzLogId, "12345") // The synced one should survive
    }

    @MainActor
    func testPrefersRicherQSO() throws {
        let baseTime = Date()

        // Create two duplicates, one with more fields
        let qso1 = QSO(
            callsign: "W1AW", band: "20m", mode: "CW",
            timestamp: baseTime, myCallsign: "N0CALL", importSource: .adifFile
        )
        let qso2 = QSO(
            callsign: "W1AW", band: "20m", mode: "CW",
            timestamp: baseTime.addingTimeInterval(60),
            rstSent: "599", rstReceived: "599", myCallsign: "N0CALL",
            theirGrid: "FN31", importSource: .adifFile
        )

        modelContext.insert(qso1)
        modelContext.insert(qso2)
        try modelContext.save()

        let service = DeduplicationService(modelContext: modelContext)
        _ = try service.findAndMergeDuplicates(timeWindowMinutes: 5)

        let qsos = try modelContext.fetch(FetchDescriptor<QSO>())
        XCTAssertEqual(qsos.count, 1)
        XCTAssertEqual(qsos[0].rstSent, "599") // The richer one should survive
        XCTAssertEqual(qsos[0].theirGrid, "FN31")
    }

    @MainActor
    func testCaseInsensitiveMatching() throws {
        let baseTime = Date()

        // Create duplicates with different cases
        let qso1 = QSO(
            callsign: "w1aw", band: "20M", mode: "cw",
            timestamp: baseTime, myCallsign: "N0CALL", importSource: .adifFile
        )
        let qso2 = QSO(
            callsign: "W1AW", band: "20m", mode: "CW",
            timestamp: baseTime.addingTimeInterval(60), myCallsign: "N0CALL",
            importSource: .adifFile
        )

        modelContext.insert(qso1)
        modelContext.insert(qso2)
        try modelContext.save()

        let service = DeduplicationService(modelContext: modelContext)
        let result = try service.findAndMergeDuplicates(timeWindowMinutes: 5)

        XCTAssertEqual(result.duplicateGroupsFound, 1)
        XCTAssertEqual(result.qsosRemoved, 1)
    }

    @MainActor
    func testFieldAbsorption() throws {
        let baseTime = Date()

        // Create duplicates with complementary fields
        let qso1 = QSO(
            callsign: "W1AW", band: "20m", mode: "CW",
            timestamp: baseTime, rstSent: "599",
            myCallsign: "N0CALL", importSource: .adifFile
        )
        let qso2 = QSO(
            callsign: "W1AW", band: "20m", mode: "CW",
            timestamp: baseTime.addingTimeInterval(60),
            rstReceived: "579", myCallsign: "N0CALL",
            theirGrid: "FN31", importSource: .adifFile
        )

        modelContext.insert(qso1)
        modelContext.insert(qso2)
        try modelContext.save()

        let service = DeduplicationService(modelContext: modelContext)
        _ = try service.findAndMergeDuplicates(timeWindowMinutes: 5)

        let qsos = try modelContext.fetch(FetchDescriptor<QSO>())
        XCTAssertEqual(qsos.count, 1)
        // Winner should have absorbed fields from loser
        XCTAssertNotNil(qsos[0].rstSent)
        XCTAssertNotNil(qsos[0].rstReceived)
        XCTAssertNotNil(qsos[0].theirGrid)
    }

    @MainActor
    func testPOTADeduplicationWithoutBand() throws {
        // POTA.app QSOs don't include frequency/band info
        let baseTime = Date()

        // QSO from POTA with no band
        let potaQSO = QSO(
            callsign: "W1AW", band: "", mode: "SSB",
            timestamp: baseTime, myCallsign: "N0CALL",
            parkReference: "US-0001", importSource: .pota
        )

        // Same QSO from another source with band info
        let lofiQSO = QSO(
            callsign: "W1AW", band: "20m", mode: "SSB",
            timestamp: baseTime.addingTimeInterval(30),
            myCallsign: "N0CALL", importSource: .lofi
        )

        modelContext.insert(potaQSO)
        modelContext.insert(lofiQSO)
        try modelContext.save()

        let service = DeduplicationService(modelContext: modelContext)
        let result = try service.findAndMergeDuplicates(timeWindowMinutes: 5)

        XCTAssertEqual(result.duplicateGroupsFound, 1)
        XCTAssertEqual(result.qsosRemoved, 1)

        let qsos = try modelContext.fetch(FetchDescriptor<QSO>())
        XCTAssertEqual(qsos.count, 1)
        // Should absorb band from the QSO that has it
        XCTAssertEqual(qsos[0].band, "20m")
        // Should keep park reference
        XCTAssertEqual(qsos[0].parkReference, "US-0001")
    }

    @MainActor
    func testPOTADeduplicationBothWithoutBand() throws {
        // Two POTA QSOs, both without band
        let baseTime = Date()

        let qso1 = QSO(
            callsign: "K3LR", band: "", mode: "CW",
            timestamp: baseTime, myCallsign: "N0CALL",
            parkReference: "US-0001", importSource: .pota
        )
        let qso2 = QSO(
            callsign: "K3LR", band: "", mode: "CW",
            timestamp: baseTime.addingTimeInterval(60),
            myCallsign: "N0CALL", importSource: .pota
        )

        modelContext.insert(qso1)
        modelContext.insert(qso2)
        try modelContext.save()

        let service = DeduplicationService(modelContext: modelContext)
        let result = try service.findAndMergeDuplicates(timeWindowMinutes: 5)

        XCTAssertEqual(result.duplicateGroupsFound, 1)
        XCTAssertEqual(result.qsosRemoved, 1)

        let qsos = try modelContext.fetch(FetchDescriptor<QSO>())
        XCTAssertEqual(qsos.count, 1)
    }

    @MainActor
    func testDifferentModesNotDuplicateWithoutBand() throws {
        // Same call, no band, but different modes - should NOT be duplicates
        let baseTime = Date()

        let qso1 = QSO(
            callsign: "W1AW", band: "", mode: "SSB",
            timestamp: baseTime, myCallsign: "N0CALL", importSource: .pota
        )
        let qso2 = QSO(
            callsign: "W1AW", band: "", mode: "CW",
            timestamp: baseTime.addingTimeInterval(60),
            myCallsign: "N0CALL", importSource: .pota
        )

        modelContext.insert(qso1)
        modelContext.insert(qso2)
        try modelContext.save()

        let service = DeduplicationService(modelContext: modelContext)
        let result = try service.findAndMergeDuplicates(timeWindowMinutes: 5)

        XCTAssertEqual(result.duplicateGroupsFound, 0)

        let qsos = try modelContext.fetch(FetchDescriptor<QSO>())
        XCTAssertEqual(qsos.count, 2)
    }
}
