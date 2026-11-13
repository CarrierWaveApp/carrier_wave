import CarrierWaveCore
import SwiftData
import XCTest
@testable import CarrierWaveData

// MARK: - EquipmentItemReadSourceTests

@MainActor
final class EquipmentItemReadSourceTests: XCTestCase {
    func testCountAndFieldParityAfterMirroredUpsert() async throws {
        let container = try ModelContainer(
            for: Schema([EquipmentItem.self]),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        let context = container.mainContext

        let radio = EquipmentItem(
            catalogId: "ic-705",
            catalogName: "IC-705",
            category: .radio,
            nickname: "705",
            notes: "QRP field rig",
            acquiredDate: Date(timeIntervalSince1970: 1_700_000_000),
            bands: ["20m", "40m"],
            modes: ["SSB", "CW", "FT8"],
            maxPowerWatts: 10,
            portability: .backpack,
            manufacturer: "Icom",
            weightOunces: 38
        )
        let antenna = EquipmentItem(
            catalogId: "efhw-10-40",
            catalogName: "EFHW 10-40",
            category: .antenna,
            isRetired: true,
            manufacturer: "Custom"
        )
        context.insert(radio)
        context.insert(antenna)
        try context.save()

        let store = try FieldStore.openInMemory(key: "equipment-item-read")
        try store.upsertEquipmentItem(item: SwiftDataStoreImporter.project(radio))
        try store.upsertEquipmentItem(item: SwiftDataStoreImporter.project(antenna))

        let swiftData = SwiftDataEquipmentItemReadSource(context: context)
        let rust = RustEquipmentItemReadSource(store: store)

        // Count parity.
        let sdCount = try await swiftData.count()
        let rustCount = try await rust.count()
        XCTAssertEqual(sdCount, 2)
        XCTAssertEqual(rustCount, 2)
        XCTAssertTrue(
            StoreCountParity().compare(entity: "EquipmentItem", swiftData: sdCount, rust: rustCount).matches
        )

        // Field + order parity: every column round-trips through cw-store.
        let sdAll = try await swiftData.all()
        let rustAll = try await rust.all()
        XCTAssertEqual(sdAll.count, 2)
        XCTAssertEqual(sdAll, rustAll)
    }

    func testParityHoldsAfterUpdateAndRetire() async throws {
        let container = try ModelContainer(
            for: Schema([EquipmentItem.self]),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        let context = container.mainContext
        let store = try FieldStore.openInMemory(key: "equipment-item-update")

        let item = EquipmentItem(
            catalogId: "kx2",
            catalogName: "KX2",
            category: .radio,
            manufacturer: "Elecraft"
        )
        context.insert(item)
        try context.save()
        try store.upsertEquipmentItem(item: SwiftDataStoreImporter.project(item))

        // Mutate + re-upsert (the standalone write path) and confirm the snapshot
        // still matches on both backends.
        item.nickname = "Pocket rig"
        item.isRetired = true
        try context.save()
        try store.upsertEquipmentItem(item: SwiftDataStoreImporter.project(item))

        let swiftData = SwiftDataEquipmentItemReadSource(context: context)
        let rust = RustEquipmentItemReadSource(store: store)
        let sdAll = try await swiftData.all()
        let rustAll = try await rust.all()
        XCTAssertEqual(sdAll.count, 1)
        XCTAssertEqual(sdAll, rustAll)
        XCTAssertEqual(rustAll.first?.nickname, "Pocket rig")
        XCTAssertEqual(rustAll.first?.isRetired, true)
    }
}
