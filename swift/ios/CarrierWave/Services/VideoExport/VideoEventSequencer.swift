// Video Event Sequencer
//
// Builds a VideoTimeline from session data snapshots with optional time compression.

import CoreLocation
import Foundation

// MARK: - VideoEventSequencer

/// Nonisolated: pure computation called from VideoExportActor.
nonisolated struct VideoEventSequencer {
    static let framesPerSecond: Double = 30

    // MARK: - Public API

    func buildTimeline(from request: VideoTimelineRequest) -> VideoTimeline {
        let rawEvents = collectRawEvents(from: request)

        guard !rawEvents.isEmpty else {
            return VideoTimeline(
                moments: [],
                totalDuration: 0,
                totalFrames: 0,
                metadata: request.session
            )
        }

        let grouped = groupIntoMoments(rawEvents: rawEvents)
        let moments = buildMoments(groups: grouped, request: request)
        let duration = computeTotalDuration(moments: moments, request: request)
        let frames = Int(duration * Self.framesPerSecond)

        return VideoTimeline(moments: moments, totalDuration: duration, totalFrames: frames, metadata: request.session)
    }
}

// MARK: - Raw Event Collection

nonisolated private extension VideoEventSequencer {
    func collectRawEvents(from request: VideoTimelineRequest) -> [(Date, VideoEvent)] {
        var events: [(Date, VideoEvent)] = []

        for qso in request.qsos {
            events.append((qso.timestamp, .qsoAppeared(qso)))
        }
        for spot in request.spots {
            events.append((spot.timestamp, .spotPulse(spot)))
        }
        for param in request.parameterEvents where param.type == .frequency {
            let timestamp = request.session.startedAt.addingTimeInterval(param.offsetSeconds)
            events.append((timestamp, .qsy(frequency: param.newValue, mode: "")))
        }
        for comment in request.potaComments {
            events.append((comment.timestamp, .potaNote(spotter: comment.spotter, comment: comment.comment)))
        }

        return events.sorted { $0.0 < $1.0 }
    }
}

// MARK: - Moment Grouping

nonisolated private extension VideoEventSequencer {
    static let mergingTolerance: TimeInterval = 1.0

    func groupIntoMoments(rawEvents: [(Date, VideoEvent)]) -> [(Date, [VideoEvent])] {
        var groups: [(Date, [VideoEvent])] = []
        var currentGroup: (Date, [VideoEvent])?

        for (timestamp, event) in rawEvents {
            if var group = currentGroup,
               timestamp.timeIntervalSince(group.0) <= Self.mergingTolerance
            {
                group.1.append(event)
                currentGroup = group
            } else {
                if let finished = currentGroup {
                    groups.append(finished)
                }
                currentGroup = (timestamp, [event])
            }
        }

        if let finished = currentGroup {
            groups.append(finished)
        }

        return groups
    }
}

// MARK: - Moment Construction

nonisolated private extension VideoEventSequencer {
    func buildMoments(
        groups: [(Date, [VideoEvent])],
        request: VideoTimelineRequest
    ) -> [VideoMoment] {
        let videoTimes = computeVideoTimes(groups: groups, request: request)
        var cumulativeQSOs: [VideoQSOSnapshot] = []

        return groups.enumerated().map { index, group in
            let (realTime, events) = group
            for event in events {
                if case let .qsoAppeared(qso) = event {
                    cumulativeQSOs.append(qso)
                }
            }
            let cameraTarget = computeCameraTarget(session: request.session, visibleQSOs: cumulativeQSOs)
            let audioOffset = request.recording.map { rec in realTime.timeIntervalSince(rec.startedAt) }

            return VideoMoment(
                realTime: realTime,
                videoTime: videoTimes[index],
                events: events,
                cameraTarget: cameraTarget,
                cameraZoom: nil,
                audioSourceOffset: audioOffset
            )
        }
    }
}

// MARK: - Time Computation

nonisolated private extension VideoEventSequencer {
    static let smallGapThreshold: TimeInterval = 30
    static let largeGapThreshold: TimeInterval = 300
    static let mediumGapCompressed: TimeInterval = 4
    static let largeGapCompressed: TimeInterval = 6

    func computeVideoTimes(
        groups: [(Date, [VideoEvent])],
        request: VideoTimelineRequest
    ) -> [TimeInterval] {
        switch request.config.mode {
        case .fullReplay:
            groups.map { $0.0.timeIntervalSince(request.session.startedAt) }
        case .highlightReel:
            computeHighlightTimes(groups: groups)
        }
    }

    func computeHighlightTimes(groups: [(Date, [VideoEvent])]) -> [TimeInterval] {
        guard !groups.isEmpty else {
            return []
        }

        var times: [TimeInterval] = [0]
        var cursor: TimeInterval = 0

        for idx in 1 ..< groups.count {
            let realGap = groups[idx].0.timeIntervalSince(groups[idx - 1].0)
            cursor += compressedGap(realGap)
            times.append(cursor)
        }

        return times
    }

    func compressedGap(_ realGap: TimeInterval) -> TimeInterval {
        if realGap < Self.smallGapThreshold {
            realGap
        } else if realGap <= Self.largeGapThreshold {
            Self.mediumGapCompressed
        } else {
            Self.largeGapCompressed
        }
    }

    func computeTotalDuration(moments: [VideoMoment], request: VideoTimelineRequest) -> TimeInterval {
        switch request.config.mode {
        case .fullReplay:
            return request.session.endedAt.timeIntervalSince(request.session.startedAt)
        case .highlightReel:
            guard let last = moments.last else {
                return 0
            }
            // Trailing buffer gives the last event at least 4s of screen time.
            return last.videoTime + Self.mediumGapCompressed
        }
    }
}

// MARK: - Camera Target

nonisolated private extension VideoEventSequencer {
    func computeCameraTarget(
        session: VideoSessionSnapshot,
        visibleQSOs: [VideoQSOSnapshot]
    ) -> CLLocationCoordinate2D? {
        var coordinates: [CLLocationCoordinate2D] = []

        if let myCoord = session.myCoordinate {
            coordinates.append(myCoord)
        }
        for qso in visibleQSOs {
            if let coord = qso.coordinate {
                coordinates.append(coord)
            }
        }

        guard !coordinates.isEmpty else {
            return nil
        }

        let latitudes = coordinates.map(\.latitude)
        let longitudes = coordinates.map(\.longitude)

        let centerLat = ((latitudes.min() ?? 0) + (latitudes.max() ?? 0)) / 2
        let centerLon = ((longitudes.min() ?? 0) + (longitudes.max() ?? 0)) / 2

        return CLLocationCoordinate2D(latitude: centerLat, longitude: centerLon)
    }
}
