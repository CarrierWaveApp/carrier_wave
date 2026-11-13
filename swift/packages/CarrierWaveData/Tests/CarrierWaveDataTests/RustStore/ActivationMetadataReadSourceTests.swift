import CarrierWaveCore
import Foundation
import SwiftData
import XCTest
@testable import CarrierWaveData

// MARK: - ActivationMetadataReadSourceTests

@MainActor
final class ActivationMetadataReadSourceTests: XCTestCase {
    func testCountAndFieldParityAfterMirroredUpsert() async throws {
        let container = try ModelContainer(
            for: Schema([ActivationMetadata.self]),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        let context = container.mainContext

        let first = ActivationMetadata(
            parkReference: "US-0001",
            date: Date(timeIntervalSince1970: 1_700_000_000),
            title: "Morning CW",
            watts: 5,
            weather: "Clear",
            solarConditions: "Good",
            averageWPM: 22
        )
        let second = ActivationMetadata(
            parkReference: "US-0002",
            date: Date(timeIntervalSince1970: 1_690_000_000)
        )
        context.insert(first)
        context.insert(second)
        try context.save()

        let store = try FieldStore.openInMemory(key: "activation-metadata-read")
        try store.upsertActivationMetadata(item: SwiftDataStoreImporter.project(first))
        try store.upsertActivationMetadata(item: SwiftDataStoreImporter.project(second))

        let swiftData = SwiftDataActivationMetadataReadSource(context: context)
        let rust = RustActivationMetadataReadSource(store: store)

        let sdCount = try await swiftData.count()
        let rustCount = try await rust.count()
        XCTAssertEqual(sdCount, 2)
        XCTAssertEqual(rustCount, 2)
        XCTAssertTrue(
            StoreCountParity().compare(entity: "ActivationMetadata", swiftData: sdCount, rust: rustCount).matches
        )

        let sdAll = try await swiftData.all()
        let rustAll = try await rust.all()
        XCTAssertEqual(sdAll.count, 2)
        XCTAssertEqual(sdAll, rustAll)
        // Ordered by parkReference: US-0001 before US-0002.
        XCTAssertEqual(rustAll.first?.parkReference, "US-0001")
    }

    func testParityHoldsAfterEnrichment() async throws {
        let container = try ModelContainer(
            for: Schema([ActivationMetadata.self]),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        let context = container.mainContext
        let store = try FieldStore.openInMemory(key: "activation-metadata-update")

        let metadata = ActivationMetadata(
            parkReference: "US-0003",
            date: Date(timeIntervalSince1970: 1_700_000_000)
        )
        context.insert(metadata)
        try context.save()
        try store.upsertActivationMetadata(item: SwiftDataStoreImporter.project(metadata))

        metadata.solarFlux = 142.5
        metadata.weatherTemperatureF = 68.0
        metadata.title = "Updated"
        try context.save()
        try store.upsertActivationMetadata(item: SwiftDataStoreImporter.project(metadata))

        let swiftData = SwiftDataActivationMetadataReadSource(context: context)
        let rust = RustActivationMetadataReadSource(store: store)
        let sdAll = try await swiftData.all()
        let rustAll = try await rust.all()
        XCTAssertEqual(sdAll.count, 1)
        XCTAssertEqual(sdAll, rustAll)
        XCTAssertEqual(rustAll.first?.solarFlux, 142.5)
        XCTAssertEqual(rustAll.first?.weatherTemperatureF, 68.0)
    }
}
