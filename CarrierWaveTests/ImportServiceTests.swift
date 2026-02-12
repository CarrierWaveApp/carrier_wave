import CarrierWaveCore
import SwiftData
import XCTest
@testable import CarrierWave

final class ImportServiceTests: XCTestCase {
    var modelContainer: ModelContainer!
    var modelContext: ModelContext!
    var importService: ImportService!

    @MainActor
    override func setUp() async throws {
        let schema = Schema([QSO.self, ServicePresence.self, UploadDestination.self])
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
}
