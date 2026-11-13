import CarrierWaveCore
import SwiftData
import Testing
import XCTest
@testable import CarrierWaveData

// MARK: - QSOReadSourceTests

@MainActor
final class QSOReadSourceTests: XCTestCase {
    func testRustCountMatchesSwiftDataAfterMirroredUpsert() async throws {
        let container = try ModelContainer(
            for: Schema([QSO.self]),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        let context = container.mainContext
        let qso = QSO(
            callsign: "W1AW",
            band: "20m",
            mode: "FT8",
            timestamp: Date(timeIntervalSince1970: 1_000),
            myCallsign: "W6JY",
            importSource: .logger
        )
        context.insert(qso)
        try context.save()

        let store = try FieldStore.openInMemory(key: "test")
        try store.upsertQso(qso: SwiftDataStoreImporter.project(qso))

        let swiftData = SwiftDataQSOReadSource(context: context)
        let rust = RustQSOReadSource(store: store)
        let sdCount = try await swiftData.count()
        let rustCount = try await rust.count()
        XCTAssertEqual(sdCount, 1)
        XCTAssertEqual(rustCount, 1)

        let result = QSOParityProbe().compareCounts(swiftData: sdCount, rust: rustCount)
        XCTAssertTrue(result.matches)
    }
}

// MARK: - RustQSOReadSourceQueryTests

@Suite(.serialized)
struct RustQSOReadSourceQueryTests {
    @Test func rustReadSourcePagesByQuery() async throws {
        let store = try FieldStore.openInMemory(key: "query-test")
        let qsoA = QSO(
            callsign: "W1AW",
            band: "20m",
            mode: "FT8",
            timestamp: Date(timeIntervalSince1970: 1_000),
            myCallsign: "W6JY",
            importSource: .logger
        )
        let qsoB = QSO(
            callsign: "K2XX",
            band: "40m",
            mode: "CW",
            timestamp: Date(timeIntervalSince1970: 2_000),
            myCallsign: "W6JY",
            importSource: .logger
        )
        try store.upsertQso(qso: SwiftDataStoreImporter.project(qsoA))
        try store.upsertQso(qso: SwiftDataStoreImporter.project(qsoB))
        let source = RustQSOReadSource(store: store)

        let page = try await source.page(query: "band:20m", limit: 100, offset: 0)
        #expect(page.count == 1)
        #expect(page.first?.callsign == "W1AW")
        #expect(try await source.count(query: "band:20m") == 1)
        #expect(try await source.count(query: "band:40m") == 1)

        let allPage = try await source.page(query: "", limit: 100, offset: 0)
        #expect(allPage.count == 2)
    }
}
