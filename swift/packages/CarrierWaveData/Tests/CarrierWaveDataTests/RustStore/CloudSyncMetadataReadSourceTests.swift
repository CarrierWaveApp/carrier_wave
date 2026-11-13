import CarrierWaveCore
import Foundation
import SwiftData
import XCTest
@testable import CarrierWaveData

// MARK: - CloudSyncMetadataReadSourceTests

@MainActor
final class CloudSyncMetadataReadSourceTests: XCTestCase {
    func testCountAndFieldParityAfterMirroredUpsert() async throws {
        let container = try ModelContainer(
            for: Schema([CloudSyncMetadata.self]),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        let context = container.mainContext

        let first = CloudSyncMetadata(
            entityType: "QSO",
            localId: UUID(),
            recordName: "rec-aaa",
            encodedSystemFields: Data([0x01, 0x02, 0x03]),
            lastSyncedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let second = CloudSyncMetadata(
            entityType: "LoggingSession",
            localId: UUID(),
            recordName: "rec-bbb"
        )
        context.insert(first)
        context.insert(second)
        try context.save()

        let store = try FieldStore.openInMemory(key: "cloud-sync-metadata-read")
        try store.upsertCloudSyncMetadata(item: SwiftDataStoreImporter.project(first))
        try store.upsertCloudSyncMetadata(item: SwiftDataStoreImporter.project(second))

        let swiftData = SwiftDataCloudSyncMetadataReadSource(context: context)
        let rust = RustCloudSyncMetadataReadSource(store: store)

        let sdCount = try await swiftData.count()
        let rustCount = try await rust.count()
        XCTAssertEqual(sdCount, 2)
        XCTAssertEqual(rustCount, 2)
        XCTAssertTrue(
            StoreCountParity().compare(entity: "CloudSyncMetadata", swiftData: sdCount, rust: rustCount).matches
        )

        let sdAll = try await swiftData.all()
        let rustAll = try await rust.all()
        XCTAssertEqual(sdAll.count, 2)
        XCTAssertEqual(sdAll, rustAll)
    }

    func testParityHoldsAfterReSync() async throws {
        let container = try ModelContainer(
            for: Schema([CloudSyncMetadata.self]),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        let context = container.mainContext
        let store = try FieldStore.openInMemory(key: "cloud-sync-metadata-update")

        let metadata = CloudSyncMetadata(entityType: "QSO", localId: UUID(), recordName: "rec-1")
        context.insert(metadata)
        try context.save()
        try store.upsertCloudSyncMetadata(item: SwiftDataStoreImporter.project(metadata))

        metadata.encodedSystemFields = Data([0xAA, 0xBB])
        metadata.lastSyncedAt = Date(timeIntervalSince1970: 1_710_000_000)
        try context.save()
        try store.upsertCloudSyncMetadata(item: SwiftDataStoreImporter.project(metadata))

        let swiftData = SwiftDataCloudSyncMetadataReadSource(context: context)
        let rust = RustCloudSyncMetadataReadSource(store: store)
        let sdAll = try await swiftData.all()
        let rustAll = try await rust.all()
        XCTAssertEqual(sdAll.count, 1)
        XCTAssertEqual(sdAll, rustAll)
        XCTAssertEqual(rustAll.first?.lastSyncedAt, 1_710_000_000)
    }
}
