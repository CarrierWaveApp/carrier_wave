import CarrierWaveData
import SwiftData
import XCTest
@testable import CarrierWave

final class WebSDRRecordingTests: XCTestCase {
    var modelContainer: ModelContainer!
    var modelContext: ModelContext!

    @MainActor
    override func setUp() async throws {
        let (container, context) = try TestModelContainer.createWithContext()
        modelContainer = container
        modelContext = context
    }

    @MainActor
    override func tearDown() async throws {
        modelContext = nil
        modelContainer = nil
    }

    @MainActor
    func testFindRecordingForSession() throws {
        let sessionId = UUID()
        let recording = WebSDRRecording(
            loggingSessionId: sessionId,
            kiwisdrHost: "test.kiwisdr.com",
            kiwisdrName: "Test SDR",
            frequencyKHz: 14_060,
            mode: "CW"
        )
        recording.isComplete = true
        modelContext.insert(recording)
        try modelContext.save()

        let found = try WebSDRRecording.findRecording(
            forSessionId: sessionId, in: modelContext
        )
        XCTAssertNotNil(found)
        XCTAssertEqual(found?.kiwisdrHost, "test.kiwisdr.com")
    }

    @MainActor
    func testFindRecordingForSession_NoMatch() throws {
        let found = try WebSDRRecording.findRecording(
            forSessionId: UUID(), in: modelContext
        )
        XCTAssertNil(found)
    }

    @MainActor
    func testFindRecordingsForSessionIds() throws {
        let id1 = UUID()
        let id2 = UUID()
        let id3 = UUID()

        let rec1 = WebSDRRecording(
            loggingSessionId: id1, kiwisdrHost: "a.com",
            kiwisdrName: "A", frequencyKHz: 7_030, mode: "CW"
        )
        rec1.isComplete = true

        let rec2 = WebSDRRecording(
            loggingSessionId: id2, kiwisdrHost: "b.com",
            kiwisdrName: "B", frequencyKHz: 14_060, mode: "CW"
        )
        rec2.isComplete = true

        modelContext.insert(rec1)
        modelContext.insert(rec2)
        try modelContext.save()

        let found = try WebSDRRecording.findRecordings(
            forSessionIds: [id1, id2, id3], in: modelContext
        )
        XCTAssertEqual(found.count, 2)
    }
}
