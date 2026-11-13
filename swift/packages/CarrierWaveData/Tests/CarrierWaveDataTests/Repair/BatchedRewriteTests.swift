import CarrierWaveData
import Foundation
import SwiftData
import Testing

// MARK: - BatchedRewriteTests

@MainActor
struct BatchedRewriteTests {
    // MARK: - Setup

    static func makeContainer() throws -> ModelContainer {
        let schema = Schema(CarrierWaveSchema.models)
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    // MARK: - Tests

    @Test func emptyStoreReturnsZero() async throws {
        let container = try Self.makeContainer()
        let repair = BatchedRewrite<LoggingSession>(
            label: "test.empty",
            container: container
        ) { _, _ in true }

        let result = try await repair.run()
        #expect(result == .init(scanned: 0, mutated: 0))
    }

    @Test func mutatesAllMatchingRows() async throws {
        let container = try Self.makeContainer()
        let context = container.mainContext

        for index in 0 ..< 10 {
            let session = LoggingSession(myCallsign: "N0TEST\(index)", mode: "CW")
            session.solarKIndex = 0
            context.insert(session)
        }
        try context.save()

        let repair = BatchedRewrite<LoggingSession>(
            label: "test.clearKIndex",
            container: container,
            predicate: #Predicate<LoggingSession> { $0.solarKIndex == 0 }
        ) { session, _ in
            session.solarKIndex = nil
            return true
        }

        let result = try await repair.run()
        #expect(result.scanned == 10)
        #expect(result.mutated == 10)

        let fetched = try context.fetch(FetchDescriptor<LoggingSession>())
        #expect(fetched.allSatisfy { $0.solarKIndex == nil })
    }

    @Test func skipsRowsWhenMutateReturnsFalse() async throws {
        let container = try Self.makeContainer()
        let context = container.mainContext

        for index in 0 ..< 10 {
            let session = LoggingSession(myCallsign: "N0TEST\(index)", mode: "CW")
            session.solarKIndex = index.isMultiple(of: 2) ? 0 : 3.0
            context.insert(session)
        }
        try context.save()

        // Mutate only rows where solarKIndex == 0 (predicate match isn't enough —
        // closure decides per row).
        let repair = BatchedRewrite<LoggingSession>(
            label: "test.skipNonZero",
            container: container
        ) { session, _ in
            guard session.solarKIndex == 0 else {
                return false
            }
            session.solarKIndex = nil
            return true
        }

        let result = try await repair.run()
        #expect(result.scanned == 10)
        #expect(result.mutated == 5)

        let fetched = try context.fetch(FetchDescriptor<LoggingSession>())
        let cleared = fetched.filter { $0.solarKIndex == nil }
        let kept = fetched.filter { $0.solarKIndex == 3.0 }
        #expect(cleared.count == 5)
        #expect(kept.count == 5)
    }

    @Test func iteratesMultipleBatches() async throws {
        let container = try Self.makeContainer()
        let context = container.mainContext

        // 250 rows across batches of 100.
        for index in 0 ..< 250 {
            let session = LoggingSession(myCallsign: "N0BATCH\(index)", mode: "CW")
            session.solarKIndex = 0
            context.insert(session)
        }
        try context.save()

        let repair = BatchedRewrite<LoggingSession>(
            label: "test.batches",
            container: container,
            batchSize: 100
        ) { session, _ in
            session.solarKIndex = nil
            return true
        }

        let result = try await repair.run()
        #expect(result.scanned == 250)
        #expect(result.mutated == 250)
    }

    @Test func injectedCommitReceivesMutatedRowsInsteadOfDefaultSave() async throws {
        let container = try Self.makeContainer()
        let context = container.mainContext

        // 250 rows across batches of 100 → commit fires once per non-empty batch.
        for index in 0 ..< 250 {
            let session = LoggingSession(myCallsign: "N0COMMIT\(index)", mode: "CW")
            session.solarKIndex = 0
            context.insert(session)
        }
        try context.save()

        // No predicate (like `iteratesMultipleBatches`): the mutated field must not
        // narrow the paged set, or offset paging skips rows — an inherent
        // BatchedRewrite property unrelated to the commit hook under test.
        let recorder = CommitRecorder()
        let repair = BatchedRewrite<LoggingSession>(
            label: "test.commit",
            container: container,
            batchSize: 100,
            mutate: { session, _ in
                session.solarKIndex = nil
                return true
            },
            commit: { rows, ctx in
                // The seam-aware analogue: would write cw-store here, then save.
                recorder.record(rows.count)
                try ctx.save()
            }
        )

        let result = try await repair.run()
        #expect(result.mutated == 250)
        #expect(recorder.totalRows == 250) // commit saw every mutated row
        #expect(recorder.batchCount == 3) // 100 + 100 + 50
        let fetched = try context.fetch(FetchDescriptor<LoggingSession>())
        #expect(fetched.allSatisfy { $0.solarKIndex == nil }) // commit's save persisted
    }

    @Test func predicateNarrowsScannedSet() async throws {
        let container = try Self.makeContainer()
        let context = container.mainContext

        for index in 0 ..< 10 {
            let session = LoggingSession(myCallsign: "N0TEST\(index)", mode: "CW")
            session.solarKIndex = (index < 3) ? 0 : 3.0
            context.insert(session)
        }
        try context.save()

        let repair = BatchedRewrite<LoggingSession>(
            label: "test.predicate",
            container: container,
            predicate: #Predicate<LoggingSession> { $0.solarKIndex == 0 }
        ) { session, _ in
            session.solarKIndex = nil
            return true
        }

        let result = try await repair.run()
        #expect(result.scanned == 3)
        #expect(result.mutated == 3)
    }
}

// MARK: - CommitRecorder

/// Lock-guarded sink for the `@Sendable` commit closure (runs on the BatchedRewrite
/// actor's executor, off the test's main actor).
private final class CommitRecorder: @unchecked Sendable {
    // MARK: Internal

    var totalRows: Int {
        lock.withLock { rows }
    }

    var batchCount: Int {
        lock.withLock { batches }
    }

    func record(_ count: Int) {
        lock.withLock {
            rows += count
            batches += 1
        }
    }

    // MARK: Private

    private let lock = NSLock()
    private var rows = 0
    private var batches = 0
}
