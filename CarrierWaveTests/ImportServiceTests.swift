import CarrierWaveCore
import CarrierWaveData
import SwiftData
import XCTest
@testable import CarrierWave

final class ImportServiceTests: XCTestCase {
    var modelContainer: ModelContainer!
    var modelContext: ModelContext!
    var importService: ImportService!

    @MainActor
    override func setUp() async throws {
        let schema = Schema(CarrierWaveSchema.models)
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        modelContainer = try ModelContainer(for: schema, configurations: [config])
        modelContext = modelContainer.mainContext
        importService = ImportService(modelContext: modelContext)
    }

    @MainActor
    func testImportSingleQSO() async throws {
        let adif = "<call:4>W1AW <band:3>20m <mode:2>CW <qso_date:8>20240115 <time_on:4>1430 <eor>"

        let result = try await importService.importADIF(
            content: adif,
            source: .adifFile,
            myCallsign: "N0CALL"
        )

        XCTAssertEqual(result.imported, 1)
        XCTAssertEqual(result.duplicates, 0)

        let qsos = try modelContext.fetch(FetchDescriptor<QSO>())
        XCTAssertEqual(qsos.count, 1)
        XCTAssertEqual(qsos[0].callsign, "W1AW")
    }

    @MainActor
    func testDeduplication() async throws {
        let adif = "<call:4>W1AW <band:3>20m <mode:2>CW <qso_date:8>20240115 <time_on:4>1430 <eor>"

        // Import twice
        _ = try await importService.importADIF(content: adif, source: .adifFile, myCallsign: "N0CALL")
        let result = try await importService.importADIF(content: adif, source: .adifFile, myCallsign: "N0CALL")

        XCTAssertEqual(result.imported, 0)
        XCTAssertEqual(result.duplicates, 1)

        let qsos = try modelContext.fetch(FetchDescriptor<QSO>())
        XCTAssertEqual(qsos.count, 1)
    }

    @MainActor
    func testServicePresenceCreated() async throws {
        let adif = "<call:4>W1AW <band:3>20m <mode:2>CW <qso_date:8>20240115 <time_on:4>1430 <eor>"

        _ = try await importService.importADIF(content: adif, source: .adifFile, myCallsign: "N0CALL")

        let qsos = try modelContext.fetch(FetchDescriptor<QSO>())
        // Should have 2 ServicePresence records: QRZ (needsUpload) and POTA (needsUpload)
        XCTAssertEqual(qsos[0].servicePresence.count, 2)
        XCTAssertTrue(qsos[0].servicePresence.allSatisfy(\.needsUpload))
    }

    @MainActor
    func testImportMultipleQSOs() async throws {
        let adif = """
        <call:4>W1AW <band:3>20m <mode:2>CW <qso_date:8>20240115 <time_on:4>1430 <eor>
        <call:4>K3LR <band:3>40m <mode:3>SSB <qso_date:8>20240115 <time_on:4>1445 <eor>
        <call:5>N3LLO <band:3>15m <mode:3>FT8 <qso_date:8>20240115 <time_on:4>1500 <eor>
        """

        let result = try await importService.importADIF(
            content: adif,
            source: .adifFile,
            myCallsign: "N0CALL"
        )

        XCTAssertEqual(result.imported, 3)
        XCTAssertEqual(result.totalRecords, 3)

        let qsos = try modelContext.fetch(FetchDescriptor<QSO>())
        XCTAssertEqual(qsos.count, 3)
    }

    // MARK: - Park Reference from Comment Tests

    @MainActor
    func testImportExtractsParkRefFromComment() async throws {
        // ADIF with no MY_SIG_INFO but park reference in the comment field
        let adif = """
        <call:4>W1AW <band:3>20m <mode:2>CW <qso_date:8>20240115 <time_on:4>1430 \
        <comment:11>POTA K-1234 <eor>
        """

        _ = try await importService.importADIF(
            content: adif, source: .adifFile, myCallsign: "N0CALL"
        )

        let qsos = try modelContext.fetch(FetchDescriptor<QSO>())
        XCTAssertEqual(qsos.count, 1)
        XCTAssertEqual(qsos[0].parkReference, "K-1234")
        XCTAssertEqual(qsos[0].notes, "POTA K-1234")
    }

    @MainActor
    func testImportPrefersExplicitMySigInfoOverComment() async throws {
        // ADIF with both MY_SIG_INFO and a park reference in the comment
        let adif = """
        <call:4>W1AW <band:3>20m <mode:2>CW <qso_date:8>20240115 <time_on:4>1430 \
        <my_sig_info:7>US-0189 <comment:11>POTA K-1234 <eor>
        """

        _ = try await importService.importADIF(
            content: adif, source: .adifFile, myCallsign: "N0CALL"
        )

        let qsos = try modelContext.fetch(FetchDescriptor<QSO>())
        XCTAssertEqual(qsos.count, 1)
        // Explicit MY_SIG_INFO should win over comment extraction
        XCTAssertEqual(qsos[0].parkReference, "US-0189")
    }

    @MainActor
    func testImportNoParkRefWhenCommentHasNone() async throws {
        // ADIF with a comment that doesn't contain a park reference
        let adif = """
        <call:4>W1AW <band:3>20m <mode:2>CW <qso_date:8>20240115 <time_on:4>1430 \
        <comment:14>nice QSO on 20m <eor>
        """

        _ = try await importService.importADIF(
            content: adif, source: .adifFile, myCallsign: "N0CALL"
        )

        let qsos = try modelContext.fetch(FetchDescriptor<QSO>())
        XCTAssertEqual(qsos.count, 1)
        XCTAssertNil(qsos[0].parkReference)
    }

    @MainActor
    func testQRZImportExtractsParkRefFromComment() {
        let qrzQso = QRZFetchedQSO(
            callsign: "W1AW", band: "20M", mode: "CW",
            frequency: 14.060, timestamp: Date(),
            rstSent: "599", rstReceived: "599",
            myCallsign: "N0CALL", myGrid: nil, theirGrid: nil,
            parkReference: nil, theirParkReference: nil,
            notes: "POTA US-3984", qrzLogId: "123",
            qrzConfirmed: false, lotwConfirmedDate: nil,
            dxcc: nil, rawADIF: ""
        )

        let qso = importService.createQSOFromQRZ(qrzQso, myCallsign: "N0CALL")
        XCTAssertEqual(qso.parkReference, "US-3984")
    }

    @MainActor
    func testQRZImportPrefersExplicitParkRef() {
        let qrzQso = QRZFetchedQSO(
            callsign: "W1AW", band: "20M", mode: "CW",
            frequency: 14.060, timestamp: Date(),
            rstSent: "599", rstReceived: "599",
            myCallsign: "N0CALL", myGrid: nil, theirGrid: nil,
            parkReference: "K-5678", theirParkReference: nil,
            notes: "POTA US-3984", qrzLogId: "123",
            qrzConfirmed: false, lotwConfirmedDate: nil,
            dxcc: nil, rawADIF: ""
        )

        let qso = importService.createQSOFromQRZ(qrzQso, myCallsign: "N0CALL")
        // Explicit park reference should win
        XCTAssertEqual(qso.parkReference, "K-5678")
    }
}
