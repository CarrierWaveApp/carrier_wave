import CarrierWaveCore
import SwiftData
import XCTest
@testable import CarrierWaveData

// MARK: - UploadDestinationReadSourceTests

@MainActor
final class UploadDestinationReadSourceTests: XCTestCase {
    func testCountAndFieldParityAfterMirroredUpsert() async throws {
        let container = try ModelContainer(
            for: Schema([UploadDestination.self]),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        let context = container.mainContext

        let qrz = UploadDestination(
            type: .qrz,
            isEnabled: true,
            lastSyncAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let pota = UploadDestination(type: .pota, isEnabled: false)
        context.insert(qrz)
        context.insert(pota)
        try context.save()

        let store = try FieldStore.openInMemory(key: "upload-destination-read")
        try store.upsertUploadDestination(item: SwiftDataStoreImporter.project(qrz))
        try store.upsertUploadDestination(item: SwiftDataStoreImporter.project(pota))

        let swiftData = SwiftDataUploadDestinationReadSource(context: context)
        let rust = RustUploadDestinationReadSource(store: store)

        // Count parity.
        let sdCount = try await swiftData.count()
        let rustCount = try await rust.count()
        XCTAssertEqual(sdCount, 2)
        XCTAssertEqual(rustCount, 2)
        XCTAssertTrue(
            StoreCountParity().compare(entity: "UploadDestination", swiftData: sdCount, rust: rustCount).matches
        )

        // Field + order parity: every column round-trips through cw-store.
        let sdAll = try await swiftData.all()
        let rustAll = try await rust.all()
        XCTAssertEqual(sdAll.count, 2)
        XCTAssertEqual(sdAll, rustAll)
    }

    func testParityHoldsAfterToggleAndSync() async throws {
        let container = try ModelContainer(
            for: Schema([UploadDestination.self]),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        let context = container.mainContext
        let store = try FieldStore.openInMemory(key: "upload-destination-update")

        let destination = UploadDestination(type: .lofi)
        context.insert(destination)
        try context.save()
        try store.upsertUploadDestination(item: SwiftDataStoreImporter.project(destination))

        // Mutate + re-upsert (the standalone write path) and confirm the snapshot
        // still matches on both backends.
        destination.isEnabled = true
        destination.lastSyncAt = Date(timeIntervalSince1970: 1_710_000_000)
        try context.save()
        try store.upsertUploadDestination(item: SwiftDataStoreImporter.project(destination))

        let swiftData = SwiftDataUploadDestinationReadSource(context: context)
        let rust = RustUploadDestinationReadSource(store: store)
        let sdAll = try await swiftData.all()
        let rustAll = try await rust.all()
        XCTAssertEqual(sdAll.count, 1)
        XCTAssertEqual(sdAll, rustAll)
        XCTAssertEqual(rustAll.first?.isEnabled, true)
        XCTAssertEqual(rustAll.first?.lastSyncAt, 1_710_000_000)
    }
}
