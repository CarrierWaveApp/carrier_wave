import CarrierWaveCore
import Foundation
import SwiftData
import Testing
@testable import CarrierWaveData

@Suite(.serialized)
struct CwStoreImportCoordinatorTests {
    // MARK: Internal

    @Test("runs once into an on-disk store, records completion, idempotent")
    func runsOnceThenSkips() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let storeURL = tempDir.appendingPathComponent("cw-store.db")

        let container = try Self.makeContainer()
        let context = ModelContext(container)
        context.insert(QSO(
            callsign: "W1AW",
            band: "20m",
            mode: "CW",
            timestamp: Date(timeIntervalSince1970: 1_000),
            myCallsign: "W6JY",
            importSource: .logger
        ))
        try context.save()

        let defaults = try #require(UserDefaults(suiteName: "cw-coord-\(UUID().uuidString)"))
        let coordinator = CwStoreImportCoordinator(
            storeURL: storeURL,
            key: { "test-key" },
            defaults: defaults,
            completionVersion: "1.0.0"
        )

        let first = try await coordinator.runIfNeeded(from: container)
        guard case let .completed(report) = first else {
            Issue.record("expected .completed, got \(first)")
            return
        }
        #expect(report.counts["qso"] == 1)
        #expect(FileManager.default.fileExists(atPath: storeURL.path))

        // The on-disk encrypted store really holds the row (reopen with the key).
        let reopened = try FieldStore.open(path: storeURL.path, key: "test-key")
        #expect(try reopened.qsoCount() == 1)

        // Second run is a no-op once the marker is recorded.
        let second = try await coordinator.runIfNeeded(from: container)
        #expect(second == .alreadyComplete)
    }

    // MARK: Private

    private static func makeContainer() throws -> ModelContainer {
        let schema = Schema(CarrierWaveSchema.models)
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }
}
