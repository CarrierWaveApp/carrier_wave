import CarrierWaveCore
import Foundation
import SwiftData
import Testing
@testable import CarrierWaveData

// `.serialized`: each test builds its own in-memory SwiftData container.
@Suite(.serialized)
@MainActor
struct CwStoreReconcilerTests {
    // MARK: Internal

    @Test("prunes cw-store QSO rows absent from SwiftData, keeps the valid ones")
    func prunesOrphans() async throws {
        let container = try Self.makeContainer()
        let context = ModelContext(container)

        // Three QSOs live in SwiftData and cw-store.
        var liveIds: [String] = []
        for index in 0 ..< 3 {
            let qso = Self.makeQSO(index: index)
            context.insert(qso)
            liveIds.append(SwiftDataStoreImporter.uuid(qso.id))
        }
        try context.save()

        let store = try FieldStore.openInMemory(key: "reconcile-test")
        try await SwiftDataStoreImporter(container: container).importAll(into: store)
        #expect(try store.qsoCount() == 3)

        // Simulate two mirror-blind deletes: rows linger in cw-store after SwiftData
        // dropped them (bulk delete / CloudKit merge the mirror never saw).
        let orphanA = Self.makeQSO(index: 97)
        let orphanB = Self.makeQSO(index: 98)
        try store.upsertQso(qso: SwiftDataStoreImporter.project(orphanA))
        try store.upsertQso(qso: SwiftDataStoreImporter.project(orphanB))
        #expect(try store.qsoCount() == 5) // diverged: Rust 5 > SwiftData 3

        let removed = try CwStoreReconciler(store: store).reconcileQSOs(in: context, pageSize: 2)
        #expect(removed == 2)
        #expect(try store.qsoCount() == 3) // converged back to SwiftData

        // The survivors are exactly the live ids — orphans gone, valid kept.
        let remaining = try store.fetchQsos(
            filter: FfiQsoFilter(callsignPrefix: nil, band: nil, mode: nil, since: nil, dirtyOnly: false),
            limit: 100, offset: 0
        ).map(\.id)
        #expect(Set(remaining) == Set(liveIds))
    }

    @Test("under Rust authority (.on) nothing is pruned: cw-store-only rows are real data")
    func noPruneUnderRustAuthority() throws {
        let defaults = UserDefaults.standard
        let previous = defaults.string(forKey: CwStoreQSOMode.appStorageKey)
        defaults.set(CwStoreQSOMode.on.rawValue, forKey: CwStoreQSOMode.appStorageKey)
        defer {
            if let previous {
                defaults.set(previous, forKey: CwStoreQSOMode.appStorageKey)
            } else {
                defaults.removeObject(forKey: CwStoreQSOMode.appStorageKey)
            }
        }
        let container = try Self.makeContainer()
        let context = ModelContext(container)
        let store = try FieldStore.openInMemory(key: "reconcile-on")
        // A server-pulled QSO lives only in cw-store (the SwiftData follower
        // hasn't replicated it yet).
        try store.upsertQso(qso: SwiftDataStoreImporter.project(Self.makeQSO(index: 7)))

        let report = try CwStoreReconciler(store: store).reconcileAll(in: context)
        #expect(report.total == 0)
        #expect(try store.qsoCount() == 1)
    }

    @Test("no-op when cw-store already matches SwiftData")
    func noOpWhenInSync() async throws {
        let container = try Self.makeContainer()
        let context = ModelContext(container)
        for index in 0 ..< 4 {
            context.insert(Self.makeQSO(index: index))
        }
        try context.save()

        let store = try FieldStore.openInMemory(key: "reconcile-noop")
        try await SwiftDataStoreImporter(container: container).importAll(into: store)

        let removed = try CwStoreReconciler(store: store).reconcileQSOs(in: context, pageSize: 1_000)
        #expect(removed == 0)
        #expect(try store.qsoCount() == 4)
    }

    @Test("prunes every cw-store QSO when SwiftData was cleared (bulk delete-all)")
    func prunesAllAfterClear() async throws {
        let container = try Self.makeContainer()
        let context = ModelContext(container)
        for index in 0 ..< 5 {
            context.insert(Self.makeQSO(index: index))
        }
        try context.save()

        let store = try FieldStore.openInMemory(key: "reconcile-clear")
        try await SwiftDataStoreImporter(container: container).importAll(into: store)
        #expect(try store.qsoCount() == 5)

        // Bulk delete-all: SwiftData emptied without the mirror seeing it.
        try context.delete(model: QSO.self)
        try context.save()

        let removed = try CwStoreReconciler(store: store).reconcileQSOs(in: context, pageSize: 2)
        #expect(removed == 5)
        #expect(try store.qsoCount() == 0)
    }

    // MARK: Private

    private static func makeContainer() throws -> ModelContainer {
        let schema = Schema(CarrierWaveSchema.models)
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    private static func makeQSO(index: Int) -> QSO {
        QSO(
            callsign: "W\(index)AW",
            band: "20m",
            mode: "CW",
            timestamp: Date(timeIntervalSince1970: Double(1_700_000_000 + index)),
            myCallsign: "W6JY",
            importSource: .logger
        )
    }
}
