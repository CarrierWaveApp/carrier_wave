import CarrierWaveCore
import XCTest
@testable import CarrierWave
@testable import CarrierWaveData

final class CwStoreMirrorActorTests: XCTestCase {
    @MainActor
    func testUpsertThenDeleteAppliesToStore() async throws {
        let store = try FieldStore.openInMemory(key: "test")
        let actor = CwStoreMirrorActor(store: store)

        let qso = QSOFactory.generate(count: 1)[0]
        let ffi = SwiftDataStoreImporter.project(qso)
        let id = ffi.id

        await actor.applyUpserts([ffi])
        await actor.drain()
        XCTAssertEqual(try store.qsoCount(), 1)

        await actor.applyDeletes([id])
        await actor.drain()
        XCTAssertEqual(try store.qsoCount(), 0)
    }

    @MainActor
    func testAppliesServicePresenceUpsertsAndDeletes() async throws {
        let store = try FieldStore.openInMemory(key: "test-sp")
        let actor = CwStoreMirrorActor(store: store)

        let sp = FfiServicePresence(
            id: "sp1",
            serviceTypeRawValue: "qrz",
            isPresent: true,
            needsUpload: false,
            uploadRejected: false,
            rejectedAtBuild: nil,
            isSubmitted: false,
            lastConfirmedAt: nil,
            parkReference: nil,
            cloudDirtyFlag: false,
            qsoId: "q1"
        )
        await actor.applyServicePresenceUpserts([sp])
        await actor.drain()
        XCTAssertEqual(try store.servicePresenceCount(), 1)

        await actor.applyServicePresenceDeletes(["sp1"])
        await actor.drain()
        XCTAssertEqual(try store.servicePresenceCount(), 0)
    }
}
