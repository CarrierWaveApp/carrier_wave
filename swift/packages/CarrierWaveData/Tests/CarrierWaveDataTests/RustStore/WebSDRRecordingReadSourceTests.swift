import CarrierWaveCore
import Foundation
import SwiftData
import XCTest
@testable import CarrierWaveData

// MARK: - WebSDRRecordingReadSourceTests

@MainActor
final class WebSDRRecordingReadSourceTests: XCTestCase {
    func testCountAndFieldParityAfterMirroredUpsert() async throws {
        let container = try ModelContainer(
            for: Schema([WebSDRRecording.self]),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        let context = container.mainContext

        let session = WebSDRRecording(
            loggingSessionId: UUID(),
            kiwisdrHost: "kiwisdr.example:8073",
            kiwisdrName: "Example",
            frequencyKHz: 14_074,
            mode: "USB"
        )
        session.relativeFilePath = "WebSDRRecordings/a.caf"
        session.fileSizeBytes = 4_096
        session.durationSeconds = 65.0
        session.isComplete = true

        let tuneIn = WebSDRRecording(
            loggingSessionId: UUID(),
            kiwisdrHost: "alpha.example:8074",
            kiwisdrName: "Alpha",
            frequencyKHz: 7_074,
            mode: "USB"
        )
        tuneIn.isTuneInRecording = true
        tuneIn.spotCallsign = "K1ABC"
        tuneIn.spotParkRef = "US-0001"

        context.insert(session)
        context.insert(tuneIn)
        try context.save()

        let store = try FieldStore.openInMemory(key: "websdr-recording-read")
        try store.upsertWebsdrRecording(item: SwiftDataStoreImporter.project(session))
        try store.upsertWebsdrRecording(item: SwiftDataStoreImporter.project(tuneIn))

        let swiftData = SwiftDataWebSDRRecordingReadSource(context: context)
        let rust = RustWebSDRRecordingReadSource(store: store)

        let sdCount = try await swiftData.count()
        let rustCount = try await rust.count()
        XCTAssertEqual(sdCount, 2)
        XCTAssertEqual(rustCount, 2)
        XCTAssertTrue(
            StoreCountParity().compare(entity: "WebSDRRecording", swiftData: sdCount, rust: rustCount).matches
        )

        let sdAll = try await swiftData.all()
        let rustAll = try await rust.all()
        XCTAssertEqual(sdAll.count, 2)
        XCTAssertEqual(sdAll, rustAll)
    }

    func testParityHoldsAfterFinish() async throws {
        let container = try ModelContainer(
            for: Schema([WebSDRRecording.self]),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        let context = container.mainContext
        let store = try FieldStore.openInMemory(key: "websdr-recording-update")

        let recording = WebSDRRecording(
            loggingSessionId: UUID(),
            kiwisdrHost: "host.example:8073",
            kiwisdrName: "Host",
            frequencyKHz: 10_136,
            mode: "USB"
        )
        context.insert(recording)
        try context.save()
        try store.upsertWebsdrRecording(item: SwiftDataStoreImporter.project(recording))

        recording.endedAt = Date(timeIntervalSince1970: 1_710_000_000)
        recording.durationSeconds = 120.0
        recording.isComplete = true
        recording.fileSizeBytes = 8_192
        try context.save()
        try store.upsertWebsdrRecording(item: SwiftDataStoreImporter.project(recording))

        let swiftData = SwiftDataWebSDRRecordingReadSource(context: context)
        let rust = RustWebSDRRecordingReadSource(store: store)
        let sdAll = try await swiftData.all()
        let rustAll = try await rust.all()
        XCTAssertEqual(sdAll.count, 1)
        XCTAssertEqual(sdAll, rustAll)
        XCTAssertEqual(rustAll.first?.isComplete, true)
        XCTAssertEqual(rustAll.first?.fileSizeBytes, 8_192)
    }
}
