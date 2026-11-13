import CarrierWaveCore
import Foundation
import SwiftData
import XCTest
@testable import CarrierWaveData

// MARK: - WebSDRFavoriteReadSourceTests

@MainActor
final class WebSDRFavoriteReadSourceTests: XCTestCase {
    func testCountAndFieldParityAfterMirroredUpsert() async throws {
        let container = try ModelContainer(
            for: Schema([WebSDRFavorite.self]),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        let context = container.mainContext

        let first = WebSDRFavorite(
            hostPort: "kiwisdr.example:8073",
            displayName: "Example KiwiSDR",
            location: "Grid FN20",
            antenna: "Loop",
            addedDate: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let second = WebSDRFavorite(
            hostPort: "alpha.example:8074",
            displayName: "Alpha",
            location: "Grid CM87"
        )
        context.insert(first)
        context.insert(second)
        try context.save()

        let store = try FieldStore.openInMemory(key: "websdr-favorite-read")
        try store.upsertWebsdrFavorite(item: SwiftDataStoreImporter.project(first))
        try store.upsertWebsdrFavorite(item: SwiftDataStoreImporter.project(second))

        let swiftData = SwiftDataWebSDRFavoriteReadSource(context: context)
        let rust = RustWebSDRFavoriteReadSource(store: store)

        let sdCount = try await swiftData.count()
        let rustCount = try await rust.count()
        XCTAssertEqual(sdCount, 2)
        XCTAssertEqual(rustCount, 2)
        XCTAssertTrue(
            StoreCountParity().compare(entity: "WebSDRFavorite", swiftData: sdCount, rust: rustCount).matches
        )

        let sdAll = try await swiftData.all()
        let rustAll = try await rust.all()
        XCTAssertEqual(sdAll.count, 2)
        XCTAssertEqual(sdAll, rustAll)
        // Ordered by hostPort: "alpha…" sorts before "kiwisdr…".
        XCTAssertEqual(rustAll.first?.displayName, "Alpha")
    }

    func testParityHoldsAfterRename() async throws {
        let container = try ModelContainer(
            for: Schema([WebSDRFavorite.self]),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        let context = container.mainContext
        let store = try FieldStore.openInMemory(key: "websdr-favorite-update")

        let favorite = WebSDRFavorite(hostPort: "host.example:8073", displayName: "Old", location: "Grid")
        context.insert(favorite)
        try context.save()
        try store.upsertWebsdrFavorite(item: SwiftDataStoreImporter.project(favorite))

        favorite.displayName = "New Name"
        favorite.antenna = "Vertical"
        try context.save()
        try store.upsertWebsdrFavorite(item: SwiftDataStoreImporter.project(favorite))

        let swiftData = SwiftDataWebSDRFavoriteReadSource(context: context)
        let rust = RustWebSDRFavoriteReadSource(store: store)
        let sdAll = try await swiftData.all()
        let rustAll = try await rust.all()
        XCTAssertEqual(sdAll.count, 1)
        XCTAssertEqual(sdAll, rustAll)
        XCTAssertEqual(rustAll.first?.displayName, "New Name")
        XCTAssertEqual(rustAll.first?.antenna, "Vertical")
    }
}
