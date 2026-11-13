import CarrierWaveCore
import SwiftData
import Testing
import XCTest
@testable import CarrierWaveData

// MARK: - ServicePresenceReadSourceTests

@MainActor
final class ServicePresenceReadSourceTests: XCTestCase {
    func testRustCountMatchesSwiftDataAfterMirroredUpsert() async throws {
        let container = try ModelContainer(
            for: Schema([QSO.self, ServicePresence.self]),
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
        let presence = ServicePresence(serviceType: .pota, isPresent: true, needsUpload: true, qso: qso)
        context.insert(presence)
        try context.save()

        let store = try FieldStore.openInMemory(key: "service-presence-test")
        try store.upsertQso(qso: SwiftDataStoreImporter.project(qso))
        try store.upsertServicePresence(item: SwiftDataStoreImporter.project(presence))

        let swiftData = SwiftDataServicePresenceReadSource(context: context)
        let rust = RustServicePresenceReadSource(store: store)
        let sdCount = try await swiftData.count()
        let rustCount = try await rust.count()
        XCTAssertEqual(sdCount, 1)
        XCTAssertEqual(rustCount, 1)

        let result = StoreCountParity().compare(entity: "ServicePresence", swiftData: sdCount, rust: rustCount)
        XCTAssertTrue(result.matches)
    }

    func testCountParityHoldsAfterStandaloneNeedsUploadFlip() async throws {
        let container = try ModelContainer(
            for: Schema([QSO.self, ServicePresence.self]),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        let context = container.mainContext
        let store = try FieldStore.openInMemory(key: "service-presence-flip")
        let qso = QSO(
            callsign: "K2XX",
            band: "40m",
            mode: "CW",
            timestamp: Date(timeIntervalSince1970: 2_000),
            myCallsign: "W6JY",
            importSource: .logger
        )
        context.insert(qso)
        let presence = ServicePresence(serviceType: .pota, isPresent: true, needsUpload: true, qso: qso)
        context.insert(presence)
        try context.save()
        try store.upsertQso(qso: SwiftDataStoreImporter.project(qso))
        try store.upsertServicePresence(item: SwiftDataStoreImporter.project(presence))

        // Simulate the standalone sync-upload marking: flip needsUpload on both backends.
        presence.needsUpload = false
        try context.save()
        try store.upsertServicePresence(item: SwiftDataStoreImporter.project(presence))

        let swiftData = SwiftDataServicePresenceReadSource(context: context)
        let rust = RustServicePresenceReadSource(store: store)
        let sdCount = try await swiftData.count()
        let rustCount = try await rust.count()
        let result = StoreCountParity().compare(entity: "ServicePresence", swiftData: sdCount, rust: rustCount)
        XCTAssertEqual(result.swiftData, 1)
        XCTAssertTrue(result.matches)
    }
}
