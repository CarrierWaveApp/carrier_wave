#if os(macOS)
    import XCTest
    @testable import CarrierWaveData

    // MARK: - MacGroupContainerMigrationTests

    final class MacGroupContainerMigrationTests: XCTestCase {
        // MARK: Internal

        override func setUpWithError() throws {
            root = FileManager.default.temporaryDirectory
                .appendingPathComponent("MacGroupContainerMigrationTests-\(UUID().uuidString)")
            legacy = root.appendingPathComponent("group.legacy", isDirectory: true)
            destination = root.appendingPathComponent("TEAM.new", isDirectory: true)
            try FileManager.default.createDirectory(at: legacy, withIntermediateDirectories: true)
        }

        override func tearDownWithError() throws {
            try? FileManager.default.removeItem(at: root)
        }

        func testMissingLegacyMovesNothing() throws {
            try FileManager.default.removeItem(at: legacy)
            XCTAssertEqual(try MacGroupContainerMigration.migrate(from: legacy, to: destination), [])
        }

        func testMovesStoreFilesAndLibraryChildrenButNotSystemEntries() throws {
            try write("cw-store.db")
            try write("cw-store.db-wal")
            try write("cw-store.recovery.json")
            try write(".com.apple.containermanagerd.metadata.plist")
            try write("Library/Application Support/CWSweep.store")
            try write("Library/Application Support/CWSweep.store-wal")
            try write("Library/Application Support/CWSweep_ckAssets/asset.bin")
            try write("Library/Preferences/com.example.plist")
            try write("Library/Application Scripts/group.legacy/.keep")
            // The new container already has the system skeleton.
            try FileManager.default.createDirectory(
                at: destination.appendingPathComponent("Library/Application Support"), withIntermediateDirectories: true
            )

            let moved = try MacGroupContainerMigration.migrate(from: legacy, to: destination)

            XCTAssertEqual(moved, [
                "cw-store.db",
                "cw-store.db-wal",
                "cw-store.recovery.json",
                "Library/Application Support/CWSweep.store",
                "Library/Application Support/CWSweep.store-wal",
                "Library/Application Support/CWSweep_ckAssets",
                "Library/Preferences/com.example.plist",
            ])
            for relative in moved {
                XCTAssertTrue(exists(destination, relative), relative)
                XCTAssertFalse(exists(legacy, relative), relative)
            }
            XCTAssertTrue(exists(destination, "Library/Application Support/CWSweep_ckAssets/asset.bin"))
            XCTAssertTrue(exists(legacy, ".com.apple.containermanagerd.metadata.plist"))
            XCTAssertTrue(exists(legacy, "Library/Application Scripts/group.legacy/.keep"))
        }

        func testConflictMovesNothing() throws {
            try write("cw-store.db")
            try write("Library/Application Support/CWSweep.store")
            try write("Library/Application Support/CWSweep.store", under: destination)

            XCTAssertThrowsError(try MacGroupContainerMigration.migrate(from: legacy, to: destination)) { error in
                XCTAssertEqual(
                    error as? MacGroupContainerMigration.MigrationError,
                    .conflict("Library/Application Support/CWSweep.store")
                )
            }
            XCTAssertTrue(exists(legacy, "cw-store.db"))
            XCTAssertFalse(exists(destination, "cw-store.db"))
        }

        func testRetryAfterPartialMoveFinishesTheRest() throws {
            // Simulate an interrupted first pass: the store already moved, the
            // sidecar didn't.
            try write("Library/Application Support/CWSweep.store", under: destination)
            try write("Library/Application Support/CWSweep.store-wal")
            try write("cw-store.db")

            let moved = try MacGroupContainerMigration.migrate(from: legacy, to: destination)

            XCTAssertEqual(moved, ["cw-store.db", "Library/Application Support/CWSweep.store-wal"])
        }

        func testRunIfNeededHonorsMarker() throws {
            let suite = "MacGroupContainerMigrationTests-\(UUID().uuidString)"
            let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            defaults.set(true, forKey: MacGroupContainerMigration.markerKey)

            XCTAssertEqual(MacGroupContainerMigration.runIfNeeded(defaults: defaults), .alreadyDone)
            XCTAssertNil(defaults.string(forKey: MacGroupContainerMigration.lastOutcomeKey))
        }

        // MARK: Private

        private var root: URL!
        private var legacy: URL!
        private var destination: URL!

        private func write(_ relative: String, under base: URL? = nil) throws {
            let url = (base ?? legacy).appendingPathComponent(relative)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try Data(relative.utf8).write(to: url)
        }

        private func exists(_ base: URL, _ relative: String) -> Bool {
            FileManager.default.fileExists(atPath: base.appendingPathComponent(relative).path)
        }
    }
#endif
