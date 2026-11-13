import CarrierWaveCore
import Foundation
import SwiftData
import XCTest
@testable import CarrierWaveData

// MARK: - SessionSpotReadSourceTests

@MainActor
final class SessionSpotReadSourceTests: XCTestCase {
    func testCountAndFieldParityAfterMirroredUpsert() async throws {
        let container = try ModelContainer(
            for: Schema([SessionSpot.self]),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        let context = container.mainContext
        let sessionId = UUID()

        let pota = SessionSpot(
            loggingSessionId: sessionId,
            callsign: "K1ABC",
            frequencyKHz: 14_285,
            mode: "SSB",
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            source: "pota",
            snr: 12,
            spotter: "W6JY",
            spotterGrid: "CM87",
            parkRef: "US-0001",
            parkName: "Acadia",
            region: "NA"
        )
        let rbn = SessionSpot(
            loggingSessionId: sessionId,
            callsign: "K1ABC",
            frequencyKHz: 14_030,
            mode: "CW",
            timestamp: Date(timeIntervalSince1970: 1_700_000_100),
            source: "rbn",
            wpm: 24
        )
        context.insert(pota)
        context.insert(rbn)
        try context.save()

        let store = try FieldStore.openInMemory(key: "session-spot-read")
        try store.upsertSessionSpot(item: SwiftDataStoreImporter.project(pota))
        try store.upsertSessionSpot(item: SwiftDataStoreImporter.project(rbn))

        let swiftData = SwiftDataSessionSpotReadSource(context: context)
        let rust = RustSessionSpotReadSource(store: store)

        let sdCount = try await swiftData.count()
        let rustCount = try await rust.count()
        XCTAssertEqual(sdCount, 2)
        XCTAssertEqual(rustCount, 2)
        XCTAssertTrue(
            StoreCountParity().compare(entity: "SessionSpot", swiftData: sdCount, rust: rustCount).matches
        )

        let sdAll = try await swiftData.all()
        let rustAll = try await rust.all()
        XCTAssertEqual(sdAll.count, 2)
        XCTAssertEqual(sdAll, rustAll)
    }

    func testParityHoldsAfterUpdate() async throws {
        let container = try ModelContainer(
            for: Schema([SessionSpot.self]),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        let context = container.mainContext
        let store = try FieldStore.openInMemory(key: "session-spot-update")

        let spot = SessionSpot(
            loggingSessionId: UUID(),
            callsign: "N0CALL",
            frequencyKHz: 7_035,
            mode: "CW",
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            source: "pota"
        )
        context.insert(spot)
        try context.save()
        try store.upsertSessionSpot(item: SwiftDataStoreImporter.project(spot))

        spot.comments = "RBN relay"
        spot.distanceMeters = 1_234.5
        try context.save()
        try store.upsertSessionSpot(item: SwiftDataStoreImporter.project(spot))

        let swiftData = SwiftDataSessionSpotReadSource(context: context)
        let rust = RustSessionSpotReadSource(store: store)
        let sdAll = try await swiftData.all()
        let rustAll = try await rust.all()
        XCTAssertEqual(sdAll.count, 1)
        XCTAssertEqual(sdAll, rustAll)
        XCTAssertEqual(rustAll.first?.comments, "RBN relay")
        XCTAssertEqual(rustAll.first?.distanceMeters, 1_234.5)
    }
}
