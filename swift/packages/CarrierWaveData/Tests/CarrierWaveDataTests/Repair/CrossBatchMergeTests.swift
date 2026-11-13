import CarrierWaveData
import Foundation
import SwiftData
import Testing

@MainActor
struct CrossBatchMergeTests {
    // MARK: - Snapshot

    /// A minimal snapshot: identifier + a duplicate-grouping key.
    struct TestSnapshot {
        let id: PersistentIdentifier
        let groupKey: String
        let priority: Int // higher = winner
    }

    /// Group snapshots by groupKey; pair the two highest-priority members.
    static let pairByGroupKey: @Sendable ([TestSnapshot])
        -> [CrossBatchMerge<LoggingSession, TestSnapshot>.MergeAction] = { snapshots in
            let groups = Dictionary(grouping: snapshots, by: \.groupKey)
            return groups.values.flatMap { group -> [CrossBatchMerge<LoggingSession, TestSnapshot>.MergeAction] in
                guard group.count >= 2 else {
                    return []
                }
                let sorted = group.sorted { $0.priority > $1.priority }
                return [.init(winnerId: sorted[0].id, loserId: sorted[1].id)]
            }
        }

    // MARK: - Setup

    static func makeContainer() throws -> ModelContainer {
        let schema = Schema(CarrierWaveSchema.models)
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    static func makeMerge(
        container: ModelContainer,
        label: String = "test",
        priority: @Sendable @escaping (LoggingSession) -> Int = { _ in 0 },
        merge: @Sendable @escaping (LoggingSession, LoggingSession, ModelContext) -> Void = { _, _, _ in }
    ) -> CrossBatchMerge<LoggingSession, TestSnapshot> {
        CrossBatchMerge<LoggingSession, TestSnapshot>(
            label: label,
            container: container,
            snapshot: { session in
                TestSnapshot(
                    id: session.persistentModelID,
                    groupKey: session.myCallsign,
                    priority: priority(session)
                )
            },
            match: pairByGroupKey,
            merge: merge
        )
    }

    // MARK: - Tests

    @Test func emptyStoreReturnsZero() async throws {
        let container = try Self.makeContainer()

        let merge = CrossBatchMerge<LoggingSession, TestSnapshot>(
            label: "test.emptyMerge",
            container: container,
            snapshot: { _ in nil },
            match: { _ in [] },
            merge: { _, _, _ in }
        )

        let result = try await merge.run()
        #expect(result == .init(snapshotsCollected: 0, pairsFound: 0, merged: 0))
    }

    @Test func planIsReadOnly() async throws {
        let container = try Self.makeContainer()
        let context = container.mainContext

        context.insert(LoggingSession(myCallsign: "ALICE", mode: "CW"))
        context.insert(LoggingSession(myCallsign: "ALICE", mode: "CW"))
        try context.save()

        let merge = Self.makeMerge(container: container)
        let plan = try await merge.plan()
        #expect(plan.snapshotsCollected == 2)
        #expect(plan.actions.count == 1)

        let fetched = try context.fetch(FetchDescriptor<LoggingSession>())
        #expect(fetched.count == 2)
    }

    @Test func runMergesDuplicates() async throws {
        let container = try Self.makeContainer()
        let context = container.mainContext

        let dup1a = LoggingSession(myCallsign: "ALICE", mode: "CW")
        dup1a.notes = "first"
        let dup1b = LoggingSession(myCallsign: "ALICE", mode: "SSB")
        let dup2a = LoggingSession(myCallsign: "BOB", mode: "CW")
        dup2a.notes = "kept"
        let dup2b = LoggingSession(myCallsign: "BOB", mode: "USB")
        let single = LoggingSession(myCallsign: "CHARLIE", mode: "FT8")
        for session in [dup1a, dup1b, dup2a, dup2b, single] {
            context.insert(session)
        }
        try context.save()

        let merge = Self.makeMerge(
            container: container,
            priority: { $0.notes == nil ? 0 : 1 },
            merge: { winner, loser, _ in winner.notes = winner.notes ?? loser.notes }
        )

        let result = try await merge.run()
        #expect(result == .init(snapshotsCollected: 5, pairsFound: 2, merged: 2))

        let fetched = try context.fetch(FetchDescriptor<LoggingSession>())
        #expect(fetched.count == 3)
        let alice = try #require(fetched.first { $0.myCallsign == "ALICE" })
        let bob = try #require(fetched.first { $0.myCallsign == "BOB" })
        #expect(alice.notes == "first")
        #expect(bob.notes == "kept")
    }

    @Test func planActionsCanBeAppliedSeparately() async throws {
        let container = try Self.makeContainer()
        let context = container.mainContext

        context.insert(LoggingSession(myCallsign: "DELTA", mode: "CW"))
        context.insert(LoggingSession(myCallsign: "DELTA", mode: "SSB"))
        try context.save()

        let merge = Self.makeMerge(container: container)

        let plan = try await merge.plan()
        #expect(plan.actions.count == 1)

        var fetched = try context.fetch(FetchDescriptor<LoggingSession>())
        #expect(fetched.count == 2)

        let result = try await merge.apply(plan)
        #expect(result.merged == 1)

        fetched = try context.fetch(FetchDescriptor<LoggingSession>())
        #expect(fetched.count == 1)
    }
}
