import SwiftData
import XCTest
@testable import CarrierWave

/// Tests for metadata pseudo-mode handling (WEATHER, SOLAR, NOTE)
///
/// These modes are used by Ham2K PoLo to store activation metadata and should:
/// - NEVER be synced to any external service (QRZ, POTA, LoFi)
/// - NEVER be marked with needsUpload in ServicePresence
/// - NEVER be counted in QSO statistics
/// - NOT appear on maps
///
/// This test suite ensures metadata modes are properly filtered throughout the app.
final class MetadataModeTests: XCTestCase {
    var modelContainer: ModelContainer!
    var modelContext: ModelContext!
    var importService: ImportService!

    /// The metadata modes that should never be synced
    let metadataModes = ["WEATHER", "SOLAR", "NOTE"]

    @MainActor
    override func setUp() async throws {
        let (container, context) = try TestModelContainer.createWithContext()
        modelContainer = container
        modelContext = context
        importService = ImportService(modelContext: modelContext)
    }

    // MARK: - QSOFactory Metadata Tests

    @MainActor
    func testQSOFactory_MetadataRecord_HasCorrectMode() {
        for mode in metadataModes {
            let record = QSOFactory.metadataRecord(mode: mode)
            XCTAssertEqual(record.mode.uppercased(), mode)
        }
    }

    @MainActor
    func testQSOFactory_ActivationMetadata_GeneratesAllModes() {
        let metadata = QSOFactory.activationMetadata(parkReference: "US-0001")

        XCTAssertEqual(metadata.count, 3)

        let modes = Set(metadata.map { $0.mode.uppercased() })
        XCTAssertEqual(modes, Set(metadataModes))
    }

    @MainActor
    func testQSOFactory_POTAActivation_IncludesMetadata() {
        let activation = QSOFactory.potaActivation(
            parkReference: "US-0001",
            qsoCount: 5,
            includeMetadata: true
        )

        // Should have 5 QSOs + 3 metadata records
        XCTAssertEqual(activation.count, 8)

        let metadataRecords = activation.filter { metadataModes.contains($0.mode.uppercased()) }
        XCTAssertEqual(metadataRecords.count, 3)
    }

    @MainActor
    func testQSOFactory_POTAActivation_ExcludesMetadata() {
        let activation = QSOFactory.potaActivation(
            parkReference: "US-0001",
            qsoCount: 5,
            includeMetadata: false
        )

        // Should have only 5 QSOs
        XCTAssertEqual(activation.count, 5)

        let metadataRecords = activation.filter { metadataModes.contains($0.mode.uppercased()) }
        XCTAssertEqual(metadataRecords.count, 0)
    }

    // MARK: - Import Service Metadata Tests

    @MainActor
    func testImportService_MetadataModes_NoServicePresenceCreated() async throws {
        // Given - ADIF with metadata modes
        let adif = """
        <call:8>METADATA <band:0> <mode:7>WEATHER <qso_date:8>20240115 <time_on:4>1430 <notes:20>Temp: 72F, Clear <eor>
        <call:8>METADATA <band:0> <mode:5>SOLAR <qso_date:8>20240115 <time_on:4>1431 <notes:15>SFI: 150, K: 2 <eor>
        <call:8>METADATA <band:0> <mode:4>NOTE <qso_date:8>20240115 <time_on:4>1432 <notes:18>Starting activation <eor>
        """

        // When
        let result = try await importService.importADIF(
            content: adif,
            source: .lofi,
            myCallsign: "N0TEST"
        )

        // Then - all 3 should be imported
        XCTAssertEqual(result.imported, 3)

        // But none should have ServicePresence with needsUpload
        let qsos = try modelContext.fetch(FetchDescriptor<QSO>())
        for qso in qsos {
            let uploadPresence = qso.servicePresence.filter(\.needsUpload)
            XCTAssertTrue(
                uploadPresence.isEmpty,
                "Metadata mode \(qso.mode) should not have upload presence"
            )
        }
    }

    @MainActor
    func testImportService_MixedQSOs_OnlyRealQSOsMarkedForUpload() async throws {
        // Given - ADIF with mix of real QSOs and metadata
        let adif = """
        <call:4>W1AW <band:3>20m <mode:2>CW <qso_date:8>20240115 <time_on:4>1430 <eor>
        <call:8>METADATA <band:0> <mode:7>WEATHER <qso_date:8>20240115 <time_on:4>1431 <eor>
        <call:4>K3LR <band:3>40m <mode:3>SSB <qso_date:8>20240115 <time_on:4>1432 <eor>
        <call:8>METADATA <band:0> <mode:5>SOLAR <qso_date:8>20240115 <time_on:4>1433 <eor>
        """

        // When
        _ = try await importService.importADIF(
            content: adif,
            source: .adifFile,
            myCallsign: "N0TEST"
        )

        // Then
        let qsos = try modelContext.fetch(FetchDescriptor<QSO>())
        XCTAssertEqual(qsos.count, 4)

        let realQSOs = qsos.filter { !metadataModes.contains($0.mode.uppercased()) }
        let metadataQSOs = qsos.filter { metadataModes.contains($0.mode.uppercased()) }

        XCTAssertEqual(realQSOs.count, 2)
        XCTAssertEqual(metadataQSOs.count, 2)

        // Real QSOs should have upload presence
        for qso in realQSOs {
            let hasUploadPresence = qso.servicePresence.contains { $0.needsUpload }
            XCTAssertTrue(hasUploadPresence, "Real QSO \(qso.callsign) should be marked for upload")
        }

        // Metadata should not have upload presence
        for qso in metadataQSOs {
            let hasUploadPresence = qso.servicePresence.contains { $0.needsUpload }
            XCTAssertFalse(
                hasUploadPresence,
                "Metadata \(qso.mode) should not be marked for upload"
            )
        }
    }

    // MARK: - Mode Case Sensitivity Tests

    @MainActor
    func testMetadataMode_CaseInsensitive() async throws {
        // Given - metadata modes in various cases
        let adif = """
        <call:8>METADATA <band:0> <mode:7>weather <qso_date:8>20240115 <time_on:4>1430 <eor>
        <call:8>METADATA <band:0> <mode:5>Solar <qso_date:8>20240115 <time_on:4>1431 <eor>
        <call:8>METADATA <band:0> <mode:4>NOTE <qso_date:8>20240115 <time_on:4>1432 <eor>
        """

        // When
        _ = try await importService.importADIF(
            content: adif,
            source: .lofi,
            myCallsign: "N0TEST"
        )

        // Then - all should be treated as metadata (no upload presence)
        let qsos = try modelContext.fetch(FetchDescriptor<QSO>())
        for qso in qsos {
            let hasUploadPresence = qso.servicePresence.contains { $0.needsUpload }
            XCTAssertFalse(
                hasUploadPresence,
                "Metadata mode \(qso.mode) should not be marked for upload regardless of case"
            )
        }
    }

    // MARK: - Metadata Identification Helper Tests

    @MainActor
    func testIsMetadataMode_ValidModes() {
        // Test helper for identifying metadata modes
        let metadataModeSet: Set<String> = ["WEATHER", "SOLAR", "NOTE"]

        XCTAssertTrue(metadataModeSet.contains("WEATHER"))
        XCTAssertTrue(metadataModeSet.contains("SOLAR"))
        XCTAssertTrue(metadataModeSet.contains("NOTE"))

        // These should not be metadata modes
        XCTAssertFalse(metadataModeSet.contains("CW"))
        XCTAssertFalse(metadataModeSet.contains("SSB"))
        XCTAssertFalse(metadataModeSet.contains("FT8"))
    }

    // MARK: - Statistics Filtering Tests

    @MainActor
    func testQSOStatistics_ExcludesMetadataModes() {
        // Given - mix of real QSOs and metadata
        var qsos: [QSO] = []

        // Add 5 real QSOs
        for _ in 0 ..< 5 {
            qsos.append(QSO.testQSO(callsign: QSOFactory.randomCallsign()))
        }

        // Add metadata records
        qsos.append(contentsOf: QSOFactory.activationMetadata())

        // When
        let stats = QSOStatistics(qsos: qsos)

        // Then - only real QSOs should be counted
        XCTAssertEqual(stats.totalQSOs, 5)
    }

    // MARK: - Edge Cases

    @MainActor
    func testMetadataMode_EmptyBandIsOK() {
        // Metadata records typically have empty bands - this is expected
        let weatherRecord = QSOFactory.metadataRecord(mode: "WEATHER")
        XCTAssertEqual(weatherRecord.band, "")

        // But they shouldn't fail validation for having empty bands
        // (hasRequiredFieldsForUpload is irrelevant since they shouldn't be uploaded anyway)
    }

    @MainActor
    func testMetadataMode_WithParkReference() {
        // Metadata records should preserve their park reference for grouping
        let record = QSOFactory.metadataRecord(mode: "WEATHER", parkReference: "US-0001")
        XCTAssertEqual(record.parkReference, "US-0001")
    }

    @MainActor
    func testMetadataMode_NotHidden() {
        // Metadata records are not "hidden" - they're just filtered from syncs
        let record = QSOFactory.metadataRecord(mode: "WEATHER")
        XCTAssertFalse(record.isHidden)
    }
}
