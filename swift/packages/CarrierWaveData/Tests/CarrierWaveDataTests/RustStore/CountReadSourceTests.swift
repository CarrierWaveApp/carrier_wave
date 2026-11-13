import CarrierWaveCore
import SwiftData
import XCTest
@testable import CarrierWaveData

// MARK: - CountReadSourceTests

/// Proves the generic count-read-source backbone (SwiftData impl over
/// `PersistentModel` + Rust factory over a `FieldStore` count method) on the
/// trivially-constructible id-keyed peripheral entities. End-to-end fixtures for
/// the relationship/natural-key entities (SessionSpot, WebSDRRecording,
/// ActivationMetadata, CloudSyncMetadata, …) are deferred to their cutovers; the
/// factories for those are compile-checked here.
@MainActor
final class CountReadSourceTests: XCTestCase {
    // MARK: Internal

    func testActivityLogCountParity() async throws {
        let container = try ModelContainer(
            for: Schema([ActivityLog.self]),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        let context = container.mainContext
        let store = try FieldStore.openInMemory(key: "count-activity-log")
        for index in 0 ..< 3 {
            let model = ActivityLog(name: "Log \(index)", myCallsign: "W6JY")
            context.insert(model)
            try store.upsertActivityLog(item: SwiftDataStoreImporter.project(model))
        }
        try context.save()

        try await assertParity(
            entity: "ActivityLog",
            swiftData: SwiftDataCountReadSource(ActivityLog.self, context: context),
            rust: .activityLog(store: store),
            expected: 3
        )
    }

    func testEquipmentItemCountParity() async throws {
        let container = try ModelContainer(
            for: Schema([EquipmentItem.self]),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        let context = container.mainContext
        let store = try FieldStore.openInMemory(key: "count-equipment-item")
        for index in 0 ..< 2 {
            let model = EquipmentItem(catalogId: "rig-\(index)", catalogName: "Rig \(index)", category: .radio)
            context.insert(model)
            try store.upsertEquipmentItem(item: SwiftDataStoreImporter.project(model))
        }
        try context.save()

        try await assertParity(
            entity: "EquipmentItem",
            swiftData: SwiftDataCountReadSource(EquipmentItem.self, context: context),
            rust: .equipmentItem(store: store),
            expected: 2
        )
    }

    func testRadioMacroCountParity() async throws {
        let container = try ModelContainer(
            for: Schema([RadioMacro.self]),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        let context = container.mainContext
        let store = try FieldStore.openInMemory(key: "count-radio-macro")
        for index in 0 ..< 4 {
            let model = RadioMacro(name: "Macro \(index)")
            context.insert(model)
            try store.upsertRadioMacro(item: SwiftDataStoreImporter.project(model))
        }
        try context.save()

        try await assertParity(
            entity: "RadioMacro",
            swiftData: SwiftDataCountReadSource(RadioMacro.self, context: context),
            rust: .radioMacro(store: store),
            expected: 4
        )
    }

    // MARK: Private

    private func assertParity(
        entity: String,
        swiftData: some CountReadSource,
        rust: RustCountReadSource,
        expected: Int
    ) async throws {
        let sdCount = try await swiftData.count()
        let rustCount = try await rust.count()
        let result = StoreCountParity().compare(entity: entity, swiftData: sdCount, rust: rustCount)
        XCTAssertEqual(result.swiftData, expected)
        XCTAssertTrue(result.matches, "\(entity) count parity: SwiftData=\(sdCount) Rust=\(rustCount)")
    }
}
