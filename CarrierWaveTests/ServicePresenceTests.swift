import CarrierWaveCore
import SwiftData
import XCTest
@testable import CarrierWave

/// Tests for ServicePresence and QSO service presence helpers
///
/// These tests cover:
/// - Service presence creation and factory methods
/// - QSO markPresent/markNeedsUpload helpers
/// - Upload rejection tracking
/// - Metadata mode filtering (WEATHER, SOLAR, NOTE should not be uploaded)
/// - POTA presence tracking for two-fer activations
final class ServicePresenceTests: XCTestCase {
    var modelContainer: ModelContainer!
    var modelContext: ModelContext!

    @MainActor
    override func setUp() async throws {
        let (container, context) = try TestModelContainer.createWithContext()
        modelContainer = container
        modelContext = context
    }

    // MARK: - Factory Method Tests

    @MainActor
    func testDownloaded_CreatesPresenceWithCorrectFlags() {
        // Given
        let qso = QSO.testQSO()
        modelContext.insert(qso)

        // When
        let presence = ServicePresence.downloaded(from: .qrz, qso: qso)
        modelContext.insert(presence)

        // Then
        XCTAssertEqual(presence.serviceType, .qrz)
        XCTAssertTrue(presence.isPresent)
        XCTAssertFalse(presence.needsUpload)
        XCTAssertNotNil(presence.lastConfirmedAt)
        XCTAssertEqual(presence.qso?.id, qso.id)
    }

    @MainActor
    func testNeedsUpload_CreatesPresenceWithCorrectFlags() {
        // Given
        let qso = QSO.testQSO()
        modelContext.insert(qso)

        // When
        let presence = ServicePresence.needsUpload(to: .qrz, qso: qso)
        modelContext.insert(presence)

        // Then
        XCTAssertEqual(presence.serviceType, .qrz)
        XCTAssertFalse(presence.isPresent)
        XCTAssertTrue(presence.needsUpload)
        XCTAssertNil(presence.lastConfirmedAt)
    }

    @MainActor
    func testNeedsUpload_ServiceWithoutUploadSupport_SetsNeedsUploadFalse() {
        // Given
        let qso = QSO.testQSO()
        modelContext.insert(qso)

        // When - LoTW is download-only
        let presence = ServicePresence.needsUpload(to: .lotw, qso: qso)
        modelContext.insert(presence)

        // Then
        XCTAssertFalse(presence.needsUpload) // LoTW doesn't support upload
    }

    // MARK: - QSO Helper Method Tests

    @MainActor
    func testMarkPresent_CreatesNewPresence() {
        // Given
        let qso = QSO.testQSO()
        modelContext.insert(qso)
        XCTAssertTrue(qso.servicePresence.isEmpty)

        // When
        qso.markPresent(in: .qrz, context: modelContext)

        // Then
        XCTAssertEqual(qso.servicePresence.count, 1)
        XCTAssertTrue(qso.isPresent(in: .qrz))
        XCTAssertFalse(qso.needsUpload(to: .qrz))
    }

    @MainActor
    func testMarkPresent_UpdatesExistingPresence() {
        // Given - QSO with needsUpload presence
        let qso = QSO.testQSO()
        modelContext.insert(qso)
        qso.markNeedsUpload(to: .qrz, context: modelContext)
        XCTAssertTrue(qso.needsUpload(to: .qrz))

        // When - mark as present (upload succeeded)
        qso.markPresent(in: .qrz, context: modelContext)

        // Then
        XCTAssertEqual(qso.servicePresence.count, 1)
        XCTAssertTrue(qso.isPresent(in: .qrz))
        XCTAssertFalse(qso.needsUpload(to: .qrz))
    }

    @MainActor
    func testMarkNeedsUpload_CreatesNewPresence() {
        // Given
        let qso = QSO.testQSO()
        modelContext.insert(qso)

        // When
        qso.markNeedsUpload(to: .pota, context: modelContext)

        // Then
        XCTAssertEqual(qso.servicePresence.count, 1)
        XCTAssertTrue(qso.needsUpload(to: .pota))
        XCTAssertFalse(qso.isPresent(in: .pota))
    }

    @MainActor
    func testMarkNeedsUpload_DoesNotOverwritePresent() {
        // Given - QSO already present in service
        let qso = QSO.testQSO()
        modelContext.insert(qso)
        qso.markPresent(in: .qrz, context: modelContext)

        // When - try to mark needs upload
        qso.markNeedsUpload(to: .qrz, context: modelContext)

        // Then - should not need upload (already present)
        XCTAssertTrue(qso.isPresent(in: .qrz))
        XCTAssertFalse(qso.needsUpload(to: .qrz))
    }

    @MainActor
    func testMarkNeedsUpload_ServiceWithoutUploadSupport_NoEffect() {
        // Given
        let qso = QSO.testQSO()
        modelContext.insert(qso)

        // When - LoTW doesn't support upload
        qso.markNeedsUpload(to: .lotw, context: modelContext)

        // Then - should not be marked for upload
        XCTAssertFalse(qso.needsUpload(to: .lotw))
    }

    // MARK: - Upload Rejection Tests

    @MainActor
    func testMarkUploadRejected_NewPresence() {
        // Given
        let qso = QSO.testQSO()
        modelContext.insert(qso)

        // When
        qso.markUploadRejected(for: .qrz, context: modelContext)

        // Then
        XCTAssertTrue(qso.isUploadRejected(for: .qrz))
        XCTAssertFalse(qso.needsUpload(to: .qrz))
        XCTAssertFalse(qso.isPresent(in: .qrz))
    }

    @MainActor
    func testMarkUploadRejected_ExistingPresence() {
        // Given - QSO marked for upload
        let qso = QSO.testQSO()
        modelContext.insert(qso)
        qso.markNeedsUpload(to: .qrz, context: modelContext)

        // When - user rejects upload
        qso.markUploadRejected(for: .qrz, context: modelContext)

        // Then
        XCTAssertTrue(qso.isUploadRejected(for: .qrz))
        XCTAssertFalse(qso.needsUpload(to: .qrz))
    }

    // MARK: - Multiple Service Tests

    @MainActor
    func testMultipleServices_IndependentTracking() {
        // Given
        let qso = QSO.testQSO()
        modelContext.insert(qso)

        // When - mark for different services
        qso.markNeedsUpload(to: .qrz, context: modelContext)
        qso.markNeedsUpload(to: .pota, context: modelContext)
        qso.markNeedsUpload(to: .lofi, context: modelContext)

        // Then
        XCTAssertEqual(qso.servicePresence.count, 3)
        XCTAssertTrue(qso.needsUpload(to: .qrz))
        XCTAssertTrue(qso.needsUpload(to: .pota))
        XCTAssertTrue(qso.needsUpload(to: .lofi))

        // When - mark QRZ as present
        qso.markPresent(in: .qrz, context: modelContext)

        // Then - only QRZ should change
        XCTAssertTrue(qso.isPresent(in: .qrz))
        XCTAssertFalse(qso.needsUpload(to: .qrz))
        XCTAssertTrue(qso.needsUpload(to: .pota))
        XCTAssertTrue(qso.needsUpload(to: .lofi))
    }

    @MainActor
    func testSyncedServicesCount() {
        // Given
        let qso = QSO.testQSO()
        modelContext.insert(qso)

        XCTAssertEqual(qso.syncedServicesCount, 0)

        // When
        qso.markPresent(in: .qrz, context: modelContext)
        XCTAssertEqual(qso.syncedServicesCount, 1)

        qso.markPresent(in: .pota, context: modelContext)
        XCTAssertEqual(qso.syncedServicesCount, 2)

        // needsUpload doesn't count as synced
        qso.markNeedsUpload(to: .lofi, context: modelContext)
        XCTAssertEqual(qso.syncedServicesCount, 2)
    }

    // MARK: - POTA Presence Tests

    @MainActor
    func testIsPresentInPOTA_FromPOTAImport() {
        // Given - QSO imported from POTA
        let qso = QSO.testQSO(importSource: .pota)
        modelContext.insert(qso)

        // Then - should be considered present in POTA
        XCTAssertTrue(qso.isPresentInPOTA())
    }

    @MainActor
    func testIsPresentInPOTA_WithServicePresence() {
        // Given - QSO with POTA presence
        let qso = QSO.testQSO()
        modelContext.insert(qso)
        qso.markPresent(in: .pota, context: modelContext)

        // Then
        XCTAssertTrue(qso.isPresentInPOTA())
    }

    @MainActor
    func testIsPresentInPOTA_WithNeedsUpload_ReturnsFalse() {
        // Given - QSO that needs POTA upload
        let qso = QSO.testQSO()
        modelContext.insert(qso)
        qso.markNeedsUpload(to: .pota, context: modelContext)

        // Then - not yet present
        XCTAssertFalse(qso.isPresentInPOTA())
    }

    @MainActor
    func testPotaPresenceRecords() {
        // Given - QSO with POTA presence for two parks (two-fer)
        let qso = QSO.testQSO(parkReference: "US-0001,US-0002")
        modelContext.insert(qso)

        let presence1 = ServicePresence.downloaded(from: .pota, qso: qso, parkReference: "US-0001")
        let presence2 = ServicePresence.downloaded(from: .pota, qso: qso, parkReference: "US-0002")
        modelContext.insert(presence1)
        modelContext.insert(presence2)
        qso.servicePresence.append(presence1)
        qso.servicePresence.append(presence2)

        // When
        let potaRecords = qso.potaPresenceRecords()

        // Then
        XCTAssertEqual(potaRecords.count, 2)
        let parks = Set(potaRecords.compactMap(\.parkReference))
        XCTAssertEqual(parks, ["US-0001", "US-0002"])
    }

    // MARK: - Service Presence with Park Reference Tests

    @MainActor
    func testServicePresence_WithParkReference() {
        // Given
        let qso = QSO.testQSO()
        modelContext.insert(qso)

        // When
        let presence = ServicePresence.downloaded(
            from: .pota,
            qso: qso,
            parkReference: "US-0001"
        )
        modelContext.insert(presence)

        // Then
        XCTAssertEqual(presence.parkReference, "US-0001")
    }

    // MARK: - QSO hasRequiredFieldsForUpload Tests

    @MainActor
    func testHasRequiredFieldsForUpload_ValidBand() {
        let qso = QSO.testQSO(band: "20m")
        XCTAssertTrue(qso.hasRequiredFieldsForUpload)
    }

    @MainActor
    func testHasRequiredFieldsForUpload_EmptyBandWithFrequency() {
        let qso = QSO.testQSO(band: "", frequency: 14.060)
        XCTAssertTrue(qso.hasRequiredFieldsForUpload)
    }

    @MainActor
    func testHasRequiredFieldsForUpload_UnknownBandWithFrequency() {
        let qso = QSO.testQSO(band: "Unknown", frequency: 14.060)
        XCTAssertTrue(qso.hasRequiredFieldsForUpload)
    }

    @MainActor
    func testHasRequiredFieldsForUpload_EmptyBandNoFrequency() {
        let qso = QSO.testQSO(band: "", frequency: nil)
        XCTAssertFalse(qso.hasRequiredFieldsForUpload)
    }

    @MainActor
    func testHasRequiredFieldsForUpload_UnknownBandNoFrequency() {
        let qso = QSO.testQSO(band: "Unknown", frequency: nil)
        XCTAssertFalse(qso.hasRequiredFieldsForUpload)
    }

    // MARK: - Field Richness Score Tests

    @MainActor
    func testFieldRichnessScore_MinimalQSO() {
        let qso = QSO(
            callsign: "W1AW",
            band: "20m",
            mode: "CW",
            timestamp: Date(),
            myCallsign: "N0TEST",
            importSource: .adifFile
        )
        XCTAssertEqual(qso.fieldRichnessScore, 0)
    }

    @MainActor
    func testFieldRichnessScore_RichQSO() {
        let qso = QSO(
            callsign: "W1AW",
            band: "20m",
            mode: "CW",
            frequency: 14.060,
            timestamp: Date(),
            rstSent: "599",
            rstReceived: "579",
            myCallsign: "N0TEST",
            myGrid: "FN31",
            theirGrid: "FN42",
            parkReference: "US-0001",
            notes: "Great signal",
            importSource: .adifFile,
            name: "John"
        )

        // frequency, rstSent, rstReceived, myGrid, theirGrid, parkReference, notes, name = 8
        XCTAssertEqual(qso.fieldRichnessScore, 8)
    }
}
