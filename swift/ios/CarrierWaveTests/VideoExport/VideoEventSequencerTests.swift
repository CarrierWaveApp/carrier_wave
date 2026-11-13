// Video Event Sequencer Tests
//
// Tests for VideoEventSequencer timeline construction and time compression.

import CoreLocation
import Foundation
import Testing
@testable import CarrierWave

// MARK: - Shared Fixtures

private let kSessionStart = Date(timeIntervalSince1970: 1_000_000)

private func makeSession(endOffset: TimeInterval = 3_600) -> VideoSessionSnapshot {
    VideoSessionSnapshot(
        callsign: "N3VEM",
        parkReference: "US-4557",
        parkName: "Test Park",
        myGrid: "FM19",
        myCoordinate: CLLocationCoordinate2D(latitude: 39.0, longitude: -77.0),
        startedAt: kSessionStart,
        endedAt: kSessionStart.addingTimeInterval(endOffset),
        initialFrequency: "7043.5",
        initialMode: "CW",
        myRig: nil,
        myAntenna: nil,
        power: nil,
        extraEquipment: nil
    )
}

private func makeQSO(offsetSeconds: TimeInterval, callsign: String = "KM4CFT") -> VideoQSOSnapshot {
    VideoQSOSnapshot(
        id: UUID(),
        callsign: callsign,
        timestamp: kSessionStart.addingTimeInterval(offsetSeconds),
        band: "40m",
        mode: "CW",
        rstSent: "599",
        rstReceived: "579",
        coordinate: CLLocationCoordinate2D(latitude: 35.0, longitude: -80.0),
        distanceKm: 500,
        name: nil,
        clubEmoji: nil,
        clubName: nil,
        priorQSOCount: 0,
        theirParkRef: nil,
        sotaRef: nil,
        wwffRef: nil,
        country: nil
    )
}

private func makeRequest(
    session: VideoSessionSnapshot,
    qsos: [VideoQSOSnapshot] = [],
    spots: [VideoSpotSnapshot] = [],
    parameterEvents: [VideoParameterChange] = [],
    potaComments: [VideoPOTAComment] = [],
    recording: VideoRecordingSnapshot? = nil,
    mode: VideoExportConfig.Mode = .fullReplay
) -> VideoTimelineRequest {
    VideoTimelineRequest(
        session: session,
        qsos: qsos,
        spots: spots,
        parameterEvents: parameterEvents,
        potaComments: potaComments,
        recording: recording,
        config: VideoExportConfig(
            sessionId: UUID(),
            mode: mode,
            includeAudio: false,
            mapStyle: .standard,
            layers: .defaults,
            hudDensity: .full,
            theme: .classic
        )
    )
}

// MARK: - VideoEventSequencerRealTimeTests

struct VideoEventSequencerRealTimeTests {
    let sequencer = VideoEventSequencer()

    @Test("Maps videoTime to session offset")
    func realTimeModeMapping() {
        let qsos = [makeQSO(offsetSeconds: 60), makeQSO(offsetSeconds: 120, callsign: "W1AW")]
        let timeline = sequencer.buildTimeline(
            from: makeRequest(session: makeSession(), qsos: qsos, mode: .fullReplay)
        )
        #expect(timeline.moments.count == 2)
        #expect(abs(timeline.moments[0].videoTime - 60) < 0.01)
        #expect(abs(timeline.moments[1].videoTime - 120) < 0.01)
    }

    @Test("Total duration matches session length")
    func realTimeDuration() {
        let qsos = [makeQSO(offsetSeconds: 60)]
        let timeline = sequencer.buildTimeline(
            from: makeRequest(session: makeSession(endOffset: 3_600), qsos: qsos, mode: .fullReplay)
        )
        #expect(abs(timeline.totalDuration - 3_600) < 0.01)
    }

    @Test("Frame count is 30fps of total duration")
    func frameCount() {
        let qsos = [makeQSO(offsetSeconds: 60)]
        let timeline = sequencer.buildTimeline(
            from: makeRequest(session: makeSession(endOffset: 100), qsos: qsos, mode: .fullReplay)
        )
        #expect(timeline.totalFrames == Int(timeline.totalDuration * 30))
    }
}

// MARK: - VideoEventSequencerHighlightTests

struct VideoEventSequencerHighlightTests {
    let sequencer = VideoEventSequencer()

    @Test("Compresses large gaps")
    func highlightCompression() {
        let qsos = [makeQSO(offsetSeconds: 60), makeQSO(offsetSeconds: 600, callsign: "W1AW")]
        let timeline = sequencer.buildTimeline(
            from: makeRequest(session: makeSession(endOffset: 700), qsos: qsos, mode: .highlightReel)
        )
        let gap = timeline.moments[1].videoTime - timeline.moments[0].videoTime
        #expect(gap < 30)
        #expect(timeline.totalDuration < 60)
    }

    @Test("Single QSO produces one moment with minimum screen time")
    func singleQSO() {
        let qsos = [makeQSO(offsetSeconds: 60)]
        let timeline = sequencer.buildTimeline(
            from: makeRequest(session: makeSession(endOffset: 120), qsos: qsos, mode: .highlightReel)
        )
        #expect(timeline.moments.count == 1)
        #expect(timeline.totalDuration >= 4)
    }

    @Test("Gap under 30s kept at real time")
    func highlightSmallGap() {
        let qsos = [makeQSO(offsetSeconds: 10), makeQSO(offsetSeconds: 30, callsign: "W1AW")]
        let timeline = sequencer.buildTimeline(
            from: makeRequest(session: makeSession(endOffset: 60), qsos: qsos, mode: .highlightReel)
        )
        let gap = timeline.moments[1].videoTime - timeline.moments[0].videoTime
        #expect(abs(gap - 20) < 0.01)
    }

    @Test("Gap 30s–5min compressed to 4s")
    func highlightMediumGap() {
        let qsos = [makeQSO(offsetSeconds: 60), makeQSO(offsetSeconds: 180, callsign: "W1AW")]
        let timeline = sequencer.buildTimeline(
            from: makeRequest(session: makeSession(endOffset: 300), qsos: qsos, mode: .highlightReel)
        )
        let gap = timeline.moments[1].videoTime - timeline.moments[0].videoTime
        #expect(abs(gap - 4) < 0.01)
    }

    @Test("Gap over 5min compressed to 6s")
    func highlightLargeGap() {
        let qsos = [makeQSO(offsetSeconds: 60), makeQSO(offsetSeconds: 460, callsign: "W1AW")]
        let timeline = sequencer.buildTimeline(
            from: makeRequest(session: makeSession(endOffset: 600), qsos: qsos, mode: .highlightReel)
        )
        let gap = timeline.moments[1].videoTime - timeline.moments[0].videoTime
        #expect(abs(gap - 6) < 0.01)
    }
}

// MARK: - VideoEventSequencerMergingTests

struct VideoEventSequencerMergingTests {
    let sequencer = VideoEventSequencer()

    @Test("Events within 1s merge into single moment")
    func eventMerging() {
        let qso = makeQSO(offsetSeconds: 60)
        let spot = VideoSpotSnapshot(
            id: UUID(),
            timestamp: kSessionStart.addingTimeInterval(60.5),
            spotter: "TI7W",
            snr: 23,
            coordinate: CLLocationCoordinate2D(latitude: 10, longitude: -84)
        )
        let timeline = sequencer.buildTimeline(
            from: makeRequest(session: makeSession(), qsos: [qso], spots: [spot])
        )
        #expect(timeline.moments.count == 1)
        #expect(timeline.moments[0].events.count == 2)
    }

    @Test("Events more than 1s apart remain separate moments")
    func eventSeparation() {
        let qso = makeQSO(offsetSeconds: 60)
        let spot = VideoSpotSnapshot(
            id: UUID(),
            timestamp: kSessionStart.addingTimeInterval(62),
            spotter: "TI7W",
            snr: 23,
            coordinate: CLLocationCoordinate2D(latitude: 10, longitude: -84)
        )
        let timeline = sequencer.buildTimeline(
            from: makeRequest(session: makeSession(), qsos: [qso], spots: [spot])
        )
        #expect(timeline.moments.count == 2)
    }

    @Test("Zero events produces empty timeline")
    func zeroQSOs() {
        let timeline = sequencer.buildTimeline(
            from: makeRequest(session: makeSession(endOffset: 3_600), mode: .highlightReel)
        )
        #expect(timeline.moments.isEmpty)
        #expect(timeline.totalFrames == 0)
        #expect(timeline.totalDuration == 0)
    }

    @Test("Parameter events appear as QSY moments")
    func parameterEventQSY() {
        let paramEvent = VideoParameterChange(
            type: .frequency,
            offsetSeconds: 120,
            oldValue: "7043.5",
            newValue: "14025.0"
        )
        let qso = makeQSO(offsetSeconds: 60)
        let timeline = sequencer.buildTimeline(
            from: makeRequest(session: makeSession(), qsos: [qso], parameterEvents: [paramEvent])
        )
        #expect(timeline.moments.count == 2)
        let hasQSY = timeline.moments[1].events.contains { event in
            if case .qsy = event {
                return true
            }
            return false
        }
        #expect(hasQSY)
    }

    @Test("POTA comments appear as potaNote events")
    func potaCommentEvents() {
        let comment = VideoPOTAComment(
            spotter: "W1AW",
            comment: "Great signal!",
            timestamp: kSessionStart.addingTimeInterval(90)
        )
        let qso = makeQSO(offsetSeconds: 60)
        let timeline = sequencer.buildTimeline(
            from: makeRequest(session: makeSession(), qsos: [qso], potaComments: [comment])
        )
        #expect(timeline.moments.count == 2)
        let hasNote = timeline.moments[1].events.contains { event in
            if case .potaNote = event {
                return true
            }
            return false
        }
        #expect(hasNote)
    }
}

// MARK: - VideoEventSequencerAudioCameraTests

struct VideoEventSequencerAudioCameraTests {
    let sequencer = VideoEventSequencer()

    @Test("Audio source offset set when recording provided")
    func audioSourceOffset() {
        let recordingStart = kSessionStart.addingTimeInterval(30)
        let recording = VideoRecordingSnapshot(
            fileURL: URL(fileURLWithPath: "/tmp/test.wav"),
            startedAt: recordingStart,
            durationSeconds: 3_600,
            frequencyKHz: 7_043.5,
            mode: "CW",
            parameterChanges: []
        )
        let qso = makeQSO(offsetSeconds: 60)
        let request = VideoTimelineRequest(
            session: makeSession(),
            qsos: [qso],
            spots: [],
            parameterEvents: [],
            potaComments: [],
            recording: recording,
            config: VideoExportConfig(
                sessionId: UUID(),
                mode: .fullReplay,
                includeAudio: true,
                mapStyle: .standard,
                layers: .defaults,
                hudDensity: .full,
                theme: .classic
            )
        )
        let timeline = sequencer.buildTimeline(from: request)
        #expect(timeline.moments.count == 1)
        let offset = timeline.moments[0].audioSourceOffset
        #expect(offset != nil)
        // Moment at realTime = sessionStart + 60, recording started at sessionStart + 30
        // audioSourceOffset = realTime - recordingStart = 30s
        #expect(abs((offset ?? 0) - 30) < 0.01)
    }

    @Test("Audio source offset is nil when no recording")
    func noAudioSourceOffset() {
        let qso = makeQSO(offsetSeconds: 60)
        let timeline = sequencer.buildTimeline(
            from: makeRequest(session: makeSession(), qsos: [qso])
        )
        #expect(timeline.moments[0].audioSourceOffset == nil)
    }

    @Test("Camera target is set for moments with QSOs")
    func cameraTargetSet() {
        let qso = makeQSO(offsetSeconds: 60)
        let timeline = sequencer.buildTimeline(
            from: makeRequest(session: makeSession(), qsos: [qso])
        )
        #expect(timeline.moments[0].cameraTarget != nil)
    }
}
