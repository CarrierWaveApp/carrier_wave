import CarrierWaveCore
import Foundation
import SwiftData
import XCTest
@testable import CarrierWaveData

// MARK: - ActivityLogReadSourceTests

@MainActor
final class ActivityLogReadSourceTests: XCTestCase {
    func testCountAndFieldParityAfterMirroredUpsert() async throws {
        let container = try ModelContainer(
            for: Schema([ActivityLog.self]),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        let context = container.mainContext

        let active = ActivityLog(
            name: "POTA Roving",
            myCallsign: "W6JY",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            stationProfileId: UUID(),
            currentGrid: "CM87",
            locationLabel: "Mount Tam",
            isActive: true
        )
        let archived = ActivityLog(
            name: "Summer Field Day",
            myCallsign: "W6JY",
            createdAt: Date(timeIntervalSince1970: 1_690_000_000),
            isActive: false
        )
        context.insert(active)
        context.insert(archived)
        try context.save()

        let store = try FieldStore.openInMemory(key: "activity-log-read")
        try store.upsertActivityLog(item: SwiftDataStoreImporter.project(active))
        try store.upsertActivityLog(item: SwiftDataStoreImporter.project(archived))

        let swiftData = SwiftDataActivityLogReadSource(context: context)
        let rust = RustActivityLogReadSource(store: store)

        let sdCount = try await swiftData.count()
        let rustCount = try await rust.count()
        XCTAssertEqual(sdCount, 2)
        XCTAssertEqual(rustCount, 2)
        XCTAssertTrue(
            StoreCountParity().compare(entity: "ActivityLog", swiftData: sdCount, rust: rustCount).matches
        )

        let sdAll = try await swiftData.all()
        let rustAll = try await rust.all()
        XCTAssertEqual(sdAll.count, 2)
        XCTAssertEqual(sdAll, rustAll)
    }

    func testParityHoldsAfterDeactivate() async throws {
        let container = try ModelContainer(
            for: Schema([ActivityLog.self]),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        let context = container.mainContext
        let store = try FieldStore.openInMemory(key: "activity-log-update")

        let log = ActivityLog(name: "Daily", myCallsign: "W6JY")
        context.insert(log)
        try context.save()
        try store.upsertActivityLog(item: SwiftDataStoreImporter.project(log))

        log.isActive = false
        log.locationLabel = "Home"
        try context.save()
        try store.upsertActivityLog(item: SwiftDataStoreImporter.project(log))

        let swiftData = SwiftDataActivityLogReadSource(context: context)
        let rust = RustActivityLogReadSource(store: store)
        let sdAll = try await swiftData.all()
        let rustAll = try await rust.all()
        XCTAssertEqual(sdAll.count, 1)
        XCTAssertEqual(sdAll, rustAll)
        XCTAssertEqual(rustAll.first?.isActive, false)
        XCTAssertEqual(rustAll.first?.locationLabel, "Home")
    }
}
