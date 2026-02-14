import SwiftData
import XCTest
@testable import CarrierWave

final class SDRParameterTrackingTests: XCTestCase {
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

    // MARK: - SDRParameterEvent Tests

    func testParameterEventCodable() throws {
        let event = SDRParameterEvent(
            type: .frequency,
            timestamp: Date(),
            offsetSeconds: 120.5,
            oldValue: "14060.000",
            newValue: "7030.000"
        )

        let data = try JSONEncoder().encode(event)
        let decoded = try JSONDecoder().decode(SDRParameterEvent.self, from: data)

        XCTAssertEqual(decoded.type, .frequency)
        XCTAssertEqual(decoded.offsetSeconds, 120.5)
        XCTAssertEqual(decoded.oldValue, "14060.000")
        XCTAssertEqual(decoded.newValue, "7030.000")
    }

    func testParameterEventArrayCodable() throws {
        let events: [SDRParameterEvent] = [
            SDRParameterEvent(
                type: .frequency,
                timestamp: Date(),
                offsetSeconds: 60,
                oldValue: "14060.000",
                newValue: "7030.000"
            ),
            SDRParameterEvent(
                type: .mode,
                timestamp: Date(),
                offsetSeconds: 120,
                oldValue: "CW",
                newValue: "SSB"
            ),
        ]

        let data = try JSONEncoder().encode(events)
        let decoded = try JSONDecoder().decode([SDRParameterEvent].self, from: data)

        XCTAssertEqual(decoded.count, 2)
        XCTAssertEqual(decoded[0].type, .frequency)
        XCTAssertEqual(decoded[1].type, .mode)
    }

    // MARK: - WebSDRRecording Parameter Storage Tests

    @MainActor
    func testRecordingParameterChangesRoundTrip() throws {
        let sessionId = UUID()
        let recording = WebSDRRecording(
            loggingSessionId: sessionId,
            kiwisdrHost: "test.kiwisdr.com",
            kiwisdrName: "Test SDR",
            frequencyKHz: 14_060,
            mode: "CW"
        )

        let events: [SDRParameterEvent] = [
            SDRParameterEvent(
                type: .frequency,
                timestamp: Date(),
                offsetSeconds: 300,
                oldValue: "14060.000",
                newValue: "7030.000"
            ),
            SDRParameterEvent(
                type: .mode,
                timestamp: Date(),
                offsetSeconds: 600,
                oldValue: "CW",
                newValue: "SSB"
            ),
        ]

        recording.parameterChanges = events
        modelContext.insert(recording)
        try modelContext.save()

        // Fetch back
        let found = try WebSDRRecording.findRecording(
            forSessionId: sessionId, in: modelContext
        )
        // Recording isn't complete yet, so findRecording won't return it
        // Fetch directly instead
        var descriptor = FetchDescriptor<WebSDRRecording>(
            predicate: #Predicate { $0.loggingSessionId == sessionId }
        )
        descriptor.fetchLimit = 1
        let fetched = try modelContext.fetch(descriptor).first

        XCTAssertNotNil(fetched)
        XCTAssertEqual(fetched?.parameterChanges.count, 2)
        XCTAssertEqual(fetched?.parameterChanges[0].type, .frequency)
        XCTAssertEqual(fetched?.parameterChanges[1].type, .mode)
    }

    @MainActor
    func testRecordingEmptyParameterChanges() {
        let recording = WebSDRRecording(
            loggingSessionId: UUID(),
            kiwisdrHost: "test.kiwisdr.com",
            kiwisdrName: "Test SDR",
            frequencyKHz: 14_060,
            mode: "CW"
        )

        XCTAssertTrue(recording.parameterChanges.isEmpty)
        XCTAssertNil(recording.parameterChangesData)
    }

    // MARK: - Segment Computation Tests

    @MainActor
    func testSegmentsNoChanges() {
        let recording = WebSDRRecording(
            loggingSessionId: UUID(),
            kiwisdrHost: "test.kiwisdr.com",
            kiwisdrName: "Test SDR",
            frequencyKHz: 14_060,
            mode: "CW"
        )

        let segments = recording.segments
        XCTAssertEqual(segments.count, 1)
        XCTAssertEqual(segments[0].startOffset, 0)
        XCTAssertNil(segments[0].endOffset)
        XCTAssertEqual(segments[0].frequencyKHz, 14_060)
        XCTAssertEqual(segments[0].mode, "CW")
    }

    @MainActor
    func testSegmentsWithFrequencyChange() {
        let recording = WebSDRRecording(
            loggingSessionId: UUID(),
            kiwisdrHost: "test.kiwisdr.com",
            kiwisdrName: "Test SDR",
            frequencyKHz: 14_060,
            mode: "CW"
        )

        recording.parameterChanges = [
            SDRParameterEvent(
                type: .frequency,
                timestamp: Date(),
                offsetSeconds: 300,
                oldValue: "14060.000",
                newValue: "7030.000"
            ),
        ]

        let segments = recording.segments
        XCTAssertEqual(segments.count, 2)

        // First segment: 0-300s at 14060 CW
        XCTAssertEqual(segments[0].startOffset, 0)
        XCTAssertEqual(segments[0].endOffset, 300)
        XCTAssertEqual(segments[0].frequencyKHz, 14_060)
        XCTAssertEqual(segments[0].mode, "CW")

        // Second segment: 300s+ at 7030 CW
        XCTAssertEqual(segments[1].startOffset, 300)
        XCTAssertNil(segments[1].endOffset)
        XCTAssertEqual(segments[1].frequencyKHz, 7_030)
        XCTAssertEqual(segments[1].mode, "CW")
    }

    @MainActor
    func testSegmentsWithModeChange() {
        let recording = WebSDRRecording(
            loggingSessionId: UUID(),
            kiwisdrHost: "test.kiwisdr.com",
            kiwisdrName: "Test SDR",
            frequencyKHz: 14_060,
            mode: "CW"
        )

        recording.parameterChanges = [
            SDRParameterEvent(
                type: .mode,
                timestamp: Date(),
                offsetSeconds: 600,
                oldValue: "CW",
                newValue: "SSB"
            ),
        ]

        let segments = recording.segments
        XCTAssertEqual(segments.count, 2)

        XCTAssertEqual(segments[0].mode, "CW")
        XCTAssertEqual(segments[0].frequencyKHz, 14_060)
        XCTAssertEqual(segments[1].mode, "SSB")
        XCTAssertEqual(segments[1].frequencyKHz, 14_060)
    }

    @MainActor
    func testSegmentsMultipleChanges() {
        let recording = WebSDRRecording(
            loggingSessionId: UUID(),
            kiwisdrHost: "test.kiwisdr.com",
            kiwisdrName: "Test SDR",
            frequencyKHz: 14_060,
            mode: "CW"
        )

        recording.parameterChanges = [
            SDRParameterEvent(
                type: .frequency,
                timestamp: Date(),
                offsetSeconds: 300,
                oldValue: "14060.000",
                newValue: "7030.000"
            ),
            SDRParameterEvent(
                type: .mode,
                timestamp: Date(),
                offsetSeconds: 600,
                oldValue: "CW",
                newValue: "SSB"
            ),
            SDRParameterEvent(
                type: .frequency,
                timestamp: Date(),
                offsetSeconds: 900,
                oldValue: "7030.000",
                newValue: "21060.000"
            ),
        ]

        let segments = recording.segments
        XCTAssertEqual(segments.count, 4)

        // Segment 1: 0-300 at 14060/CW
        XCTAssertEqual(segments[0].frequencyKHz, 14_060)
        XCTAssertEqual(segments[0].mode, "CW")

        // Segment 2: 300-600 at 7030/CW
        XCTAssertEqual(segments[1].frequencyKHz, 7_030)
        XCTAssertEqual(segments[1].mode, "CW")

        // Segment 3: 600-900 at 7030/SSB
        XCTAssertEqual(segments[2].frequencyKHz, 7_030)
        XCTAssertEqual(segments[2].mode, "SSB")

        // Segment 4: 900+ at 21060/SSB
        XCTAssertEqual(segments[3].frequencyKHz, 21_060)
        XCTAssertEqual(segments[3].mode, "SSB")
        XCTAssertNil(segments[3].endOffset)
    }

    @MainActor
    func testSegmentDuration() {
        let segment = SDRRecordingSegment(
            startOffset: 100,
            endOffset: 400,
            frequencyKHz: 14_060,
            mode: "CW"
        )
        XCTAssertEqual(segment.duration(recordingDuration: 1_000), 300)
    }

    @MainActor
    func testSegmentDurationOpenEnded() {
        let segment = SDRRecordingSegment(
            startOffset: 100,
            endOffset: nil,
            frequencyKHz: 14_060,
            mode: "CW"
        )
        XCTAssertEqual(segment.duration(recordingDuration: 1_000), 900)
    }
}
