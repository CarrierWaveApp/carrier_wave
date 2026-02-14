import SwiftData
import XCTest
@testable import CarrierWave

// MARK: - SDRParameterTrackingTests

final class SDRParameterTrackingTests: XCTestCase {
    // MARK: Internal

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

    // MARK: - SDRParameterEvent Codable Tests

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

    func testLifecycleEventsCodable() throws {
        let events: [SDRParameterEvent] = [
            SDRParameterEvent(
                type: .pause,
                timestamp: Date(),
                offsetSeconds: 300,
                oldValue: "",
                newValue: ""
            ),
            SDRParameterEvent(
                type: .resume,
                timestamp: Date(),
                offsetSeconds: 900,
                oldValue: "",
                newValue: ""
            ),
            SDRParameterEvent(
                type: .sdrDisconnected,
                timestamp: Date(),
                offsetSeconds: 1_200,
                oldValue: "test.kiwisdr.com",
                newValue: ""
            ),
            SDRParameterEvent(
                type: .sdrConnected,
                timestamp: Date(),
                offsetSeconds: 1_800,
                oldValue: "",
                newValue: "other.kiwisdr.com"
            ),
        ]

        let data = try JSONEncoder().encode(events)
        let decoded = try JSONDecoder().decode([SDRParameterEvent].self, from: data)

        XCTAssertEqual(decoded.count, 4)
        XCTAssertEqual(decoded[0].type, .pause)
        XCTAssertEqual(decoded[1].type, .resume)
        XCTAssertEqual(decoded[2].type, .sdrDisconnected)
        XCTAssertEqual(decoded[3].type, .sdrConnected)
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

    // MARK: - Segment Computation: Tuning Changes

    @MainActor
    func testSegmentsNoChanges() {
        let recording = makeRecording()
        let segments = recording.segments

        XCTAssertEqual(segments.count, 1)
        XCTAssertEqual(segments[0].startOffset, 0)
        XCTAssertNil(segments[0].endOffset)
        XCTAssertEqual(segments[0].frequencyKHz, 14_060)
        XCTAssertEqual(segments[0].mode, "CW")
        XCTAssertFalse(segments[0].isSilence)
    }

    @MainActor
    func testSegmentsWithFrequencyChange() {
        let recording = makeRecording()
        recording.parameterChanges = [
            makeEvent(.frequency, offset: 300, old: "14060.000", new: "7030.000"),
        ]

        let segments = recording.segments
        XCTAssertEqual(segments.count, 2)

        XCTAssertEqual(segments[0].startOffset, 0)
        XCTAssertEqual(segments[0].endOffset, 300)
        XCTAssertEqual(segments[0].frequencyKHz, 14_060)
        XCTAssertFalse(segments[0].isSilence)

        XCTAssertEqual(segments[1].startOffset, 300)
        XCTAssertNil(segments[1].endOffset)
        XCTAssertEqual(segments[1].frequencyKHz, 7_030)
        XCTAssertFalse(segments[1].isSilence)
    }

    @MainActor
    func testSegmentsWithModeChange() {
        let recording = makeRecording()
        recording.parameterChanges = [
            makeEvent(.mode, offset: 600, old: "CW", new: "SSB"),
        ]

        let segments = recording.segments
        XCTAssertEqual(segments.count, 2)

        XCTAssertEqual(segments[0].mode, "CW")
        XCTAssertEqual(segments[1].mode, "SSB")
        XCTAssertEqual(segments[1].frequencyKHz, 14_060)
    }

    @MainActor
    func testSegmentsMultipleChanges() {
        let recording = makeRecording()
        recording.parameterChanges = [
            makeEvent(.frequency, offset: 300, old: "14060.000", new: "7030.000"),
            makeEvent(.mode, offset: 600, old: "CW", new: "SSB"),
            makeEvent(.frequency, offset: 900, old: "7030.000", new: "21060.000"),
        ]

        let segments = recording.segments
        XCTAssertEqual(segments.count, 4)

        XCTAssertEqual(segments[0].frequencyKHz, 14_060)
        XCTAssertEqual(segments[0].mode, "CW")
        XCTAssertEqual(segments[1].frequencyKHz, 7_030)
        XCTAssertEqual(segments[1].mode, "CW")
        XCTAssertEqual(segments[2].frequencyKHz, 7_030)
        XCTAssertEqual(segments[2].mode, "SSB")
        XCTAssertEqual(segments[3].frequencyKHz, 21_060)
        XCTAssertEqual(segments[3].mode, "SSB")
        XCTAssertNil(segments[3].endOffset)
    }

    // MARK: Private

    // MARK: - Helpers

    private func makeRecording() -> WebSDRRecording {
        WebSDRRecording(
            loggingSessionId: UUID(),
            kiwisdrHost: "test.kiwisdr.com",
            kiwisdrName: "Test SDR",
            frequencyKHz: 14_060,
            mode: "CW"
        )
    }

    private func makeEvent(
        _ type: SDRParameterEvent.ChangeType,
        offset: Double,
        old: String = "",
        new: String = ""
    ) -> SDRParameterEvent {
        SDRParameterEvent(
            type: type,
            timestamp: Date(),
            offsetSeconds: offset,
            oldValue: old,
            newValue: new
        )
    }
}

// MARK: - Silence Gap & Duration Tests

extension SDRParameterTrackingTests {
    @MainActor
    func testSegmentsWithPauseResume() {
        let recording = makeRecording()
        recording.parameterChanges = [
            makeEvent(.pause, offset: 300),
            makeEvent(.resume, offset: 900),
        ]

        let segments = recording.segments
        XCTAssertEqual(segments.count, 3)

        XCTAssertFalse(segments[0].isSilence)
        XCTAssertEqual(segments[0].startOffset, 0)
        XCTAssertEqual(segments[0].endOffset, 300)

        XCTAssertTrue(segments[1].isSilence)
        XCTAssertEqual(segments[1].startOffset, 300)
        XCTAssertEqual(segments[1].endOffset, 900)
        XCTAssertEqual(segments[1].duration(recordingDuration: 3_600), 600)

        XCTAssertFalse(segments[2].isSilence)
        XCTAssertEqual(segments[2].startOffset, 900)
    }

    @MainActor
    func testSegmentsWithDisconnectReconnect() {
        let recording = makeRecording()
        recording.parameterChanges = [
            makeEvent(.sdrDisconnected, offset: 600, old: "sdr1.com"),
            makeEvent(.sdrConnected, offset: 1_200, new: "sdr2.com"),
        ]

        let segments = recording.segments
        XCTAssertEqual(segments.count, 3)

        XCTAssertFalse(segments[0].isSilence)
        XCTAssertEqual(segments[0].endOffset, 600)

        XCTAssertTrue(segments[1].isSilence)
        XCTAssertEqual(segments[1].startOffset, 600)
        XCTAssertEqual(segments[1].endOffset, 1_200)
        XCTAssertEqual(segments[1].duration(recordingDuration: 3_600), 600)

        XCTAssertFalse(segments[2].isSilence)
        XCTAssertEqual(segments[2].startOffset, 1_200)
    }

    @MainActor
    func testSegmentsMixedTuningAndSilence() {
        let recording = makeRecording()
        recording.parameterChanges = [
            makeEvent(.frequency, offset: 300, old: "14060.000", new: "7030.000"),
            makeEvent(.pause, offset: 600),
            makeEvent(.resume, offset: 1_200),
            makeEvent(.mode, offset: 1_500, old: "CW", new: "SSB"),
            makeEvent(.sdrDisconnected, offset: 1_800, old: "sdr.com"),
            makeEvent(.sdrConnected, offset: 2_400, new: "sdr.com"),
        ]

        let segments = recording.segments
        XCTAssertEqual(segments.count, 7)

        XCTAssertEqual(segments[0].frequencyKHz, 14_060)
        XCTAssertFalse(segments[0].isSilence)
        XCTAssertEqual(segments[1].frequencyKHz, 7_030)
        XCTAssertFalse(segments[1].isSilence)
        XCTAssertTrue(segments[2].isSilence)
        XCTAssertEqual(segments[2].frequencyKHz, 7_030)
        XCTAssertFalse(segments[3].isSilence)
        XCTAssertEqual(segments[4].mode, "SSB")
        XCTAssertFalse(segments[4].isSilence)
        XCTAssertTrue(segments[5].isSilence)
        XCTAssertFalse(segments[6].isSilence)
        XCTAssertNil(segments[6].endOffset)
    }

    @MainActor
    func testSegmentPreservesTuningAcrossSilence() {
        let recording = makeRecording()
        recording.parameterChanges = [
            makeEvent(.frequency, offset: 100, old: "14060.000", new: "7030.000"),
            makeEvent(.pause, offset: 200),
            makeEvent(.resume, offset: 500),
        ]

        let segments = recording.segments
        XCTAssertEqual(segments.count, 4)

        XCTAssertTrue(segments[2].isSilence)
        XCTAssertEqual(segments[2].frequencyKHz, 7_030)
        XCTAssertFalse(segments[3].isSilence)
        XCTAssertEqual(segments[3].frequencyKHz, 7_030)
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

    @MainActor
    func testSilenceSegmentDuration() {
        let segment = SDRRecordingSegment(
            startOffset: 300,
            endOffset: 900,
            frequencyKHz: 14_060,
            mode: "CW",
            isSilence: true
        )
        XCTAssertEqual(segment.duration(recordingDuration: 3_600), 600)
        XCTAssertTrue(segment.isSilence)
    }

    @MainActor
    func testDormantStateIsActive() {
        let state = WebSDRSession.State.dormant
        XCTAssertTrue(state.isActive)
        XCTAssertFalse(state.isStreaming)
    }

    @MainActor
    func testRecordingStateIsStreaming() {
        let state = WebSDRSession.State.recording
        XCTAssertTrue(state.isActive)
        XCTAssertTrue(state.isStreaming)
    }

    @MainActor
    func testIdleStateNotActive() {
        let state = WebSDRSession.State.idle
        XCTAssertFalse(state.isActive)
        XCTAssertFalse(state.isStreaming)
    }
}
