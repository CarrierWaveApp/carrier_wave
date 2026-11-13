// Video Export Actor
//
// Orchestrator for the video export pipeline.

import CarrierWaveCore
import CarrierWaveData
import CoreLocation
import Foundation
import SwiftData
import UIKit

// MARK: - VideoExportLoadedData

struct VideoExportLoadedData {
    let request: VideoTimelineRequest
}

// MARK: - VideoExportActor

actor VideoExportActor {
    // MARK: Internal

    /// The result of the export (available after the stream completes).
    var result: VideoExportResult?

    /// Compositor reference for cancellation
    var compositor: VideoFrameCompositor?

    // MARK: Internal (accessed from extension files)

    var isCancelled = false

    /// Start the export. Returns an AsyncStream of progress updates.
    func startExport(
        container: ModelContainer,
        config: VideoExportConfig
    ) -> AsyncStream<VideoExportProgress> {
        AsyncStream { continuation in
            exportTask = Task {
                await runExport(container: container, config: config, continuation: continuation)
            }
        }
    }

    /// Cancel an in-progress export.
    func cancel() {
        isCancelled = true
        exportTask?.cancel()
        let comp = compositor
        Task { @MainActor in
            comp?.cancelCurrentSnapshot()
        }
    }

    // MARK: Private

    private var exportTask: Task<Void, Never>?

    private func runExport(
        container: ModelContainer,
        config: VideoExportConfig,
        continuation: AsyncStream<VideoExportProgress>.Continuation
    ) async {
        // Keep screen on during export to prevent iOS from interrupting AVAssetWriter
        await MainActor.run { UIApplication.shared.isIdleTimerDisabled = true }
        defer {
            Task { @MainActor in UIApplication.shared.isIdleTimerDisabled = false }
        }

        let data = loadSessionData(container: container, config: config)
        guard let data else {
            result = .failed("Failed to load session data")
            continuation.finish()
            return
        }

        let qsoCount = data.request.qsos.count
        let spotCount = data.request.spots.count
        await MainActor.run {
            SyncDebugLog.shared.log(
                "VideoExport: \(qsoCount) QSOs, \(spotCount) spots",
                level: .info
            )
        }

        let sequencer = VideoEventSequencer()
        let timeline = sequencer.buildTimeline(from: data.request)

        let momentCount = timeline.moments.count
        let dur = timeline.totalDuration
        let frames = timeline.totalFrames
        await MainActor.run {
            SyncDebugLog.shared.log(
                "VideoExport: \(momentCount) moments, \(dur)s, \(frames) frames",
                level: .info
            )
        }

        guard !timeline.moments.isEmpty else {
            result = .failed("No events to export")
            continuation.finish()
            return
        }

        let pipelineResult = await runPipeline(
            timeline: timeline,
            config: config,
            recording: data.request.recording,
            continuation: continuation
        )

        result = pipelineResult
        continuation.finish()
    }
}

// MARK: - Data Loading

extension VideoExportActor {
    // swiftlint:disable:next function_body_length
    func loadSessionData(container: ModelContainer, config: VideoExportConfig) -> VideoExportLoadedData? {
        let context = ModelContext(container)
        let sessionId = config.sessionId

        // Fetch LoggingSession
        var sessionDescriptor = FetchDescriptor<LoggingSession>(
            predicate: #Predicate { $0.id == sessionId }
        )
        sessionDescriptor.fetchLimit = 1
        guard let session = (try? context.fetch(sessionDescriptor))?.first else {
            return nil
        }

        let sessionEnd = session.endedAt ?? Date()

        // Fetch park name from ActivationMetadata if available
        let parkName: String? = fetchParkName(
            parkReference: session.parkReference,
            context: context
        )

        // Build session snapshot — prefer user's grid square, fall back to park coordinates
        let myCoord: CLLocationCoordinate2D? = operatorCoordinate(
            myGrid: session.myGrid, parkReference: session.parkReference
        )

        let sessionSnapshot = VideoSessionSnapshot(
            callsign: session.myCallsign,
            parkReference: session.parkReference,
            parkName: parkName,
            myGrid: session.myGrid,
            myCoordinate: myCoord,
            startedAt: session.startedAt,
            endedAt: sessionEnd,
            initialFrequency: session.frequency.map { String($0) },
            initialMode: session.mode,
            myRig: session.myRig,
            myAntenna: session.myAntenna,
            power: session.power,
            extraEquipment: session.extraEquipment
        )

        // Fetch QSOs within the session time range
        let startedAt = session.startedAt
        let qsoDescriptor = BoundedDescriptor<QSO>(
            predicate: #Predicate<QSO> {
                $0.loggingSessionId == sessionId &&
                    !$0.isHidden &&
                    $0.timestamp >= startedAt &&
                    $0.timestamp <= sessionEnd
            },
            sortBy: [SortDescriptor(\.timestamp)],
            limit: BoundedDescriptor<QSO>.maxLimit
        )
        let rawQSOs = (try? context.boundedFetch(qsoDescriptor)) ?? []

        let qsoSnapshots: [VideoQSOSnapshot] = rawQSOs
            .filter { !QSOMode.isMetadata($0.mode) }
            .map { qso in
                let coord: CLLocationCoordinate2D? = qso.theirGrid.flatMap { grid in
                    MaidenheadConverter.coordinate(from: grid).map {
                        CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
                    }
                }
                return VideoQSOSnapshot(
                    id: qso.id,
                    callsign: qso.callsign,
                    timestamp: qso.timestamp,
                    band: qso.band,
                    mode: qso.mode,
                    rstSent: qso.rstSent,
                    rstReceived: qso.rstReceived,
                    coordinate: coord,
                    distanceKm: nil,
                    name: nil,
                    clubEmoji: nil,
                    clubName: nil,
                    priorQSOCount: 0,
                    theirParkRef: qso.theirParkReference,
                    sotaRef: qso.sotaRef,
                    wwffRef: qso.wwffRef,
                    country: qso.country
                )
            }

        // Fetch SessionSpots for this session
        var spotDescriptor = FetchDescriptor<SessionSpot>(
            predicate: #Predicate { $0.loggingSessionId == sessionId },
            sortBy: [SortDescriptor(\.timestamp)]
        )
        spotDescriptor.fetchLimit = 1_000
        let rawSpots = (try? context.fetch(spotDescriptor)) ?? []

        let spotSnapshots: [VideoSpotSnapshot] = rawSpots.map { spot in
            let coord: CLLocationCoordinate2D? = spot.spotterGrid.flatMap { grid in
                MaidenheadConverter.coordinate(from: grid).map {
                    CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
                }
            }
            return VideoSpotSnapshot(
                id: spot.id,
                timestamp: spot.timestamp,
                spotter: spot.spotter ?? spot.callsign,
                snr: spot.snr,
                coordinate: coord
            )
        }

        // Fetch WebSDRRecording
        let recording: VideoRecordingSnapshot? = (try? WebSDRRecording.findRecording(
            forSessionId: sessionId,
            in: context
        )).flatMap { rec in
            guard let fileURL = rec.fileURL else {
                return nil
            }
            let paramChanges = rec.parameterChanges.map { event in
                VideoParameterChange(
                    type: mapSDRChangeType(event.type),
                    offsetSeconds: event.offsetSeconds,
                    oldValue: event.oldValue,
                    newValue: event.newValue
                )
            }
            return VideoRecordingSnapshot(
                fileURL: fileURL,
                startedAt: rec.startedAt,
                durationSeconds: rec.durationSeconds,
                frequencyKHz: rec.frequencyKHz,
                mode: rec.mode,
                parameterChanges: paramChanges
            )
        }

        // Read POTA spot comments from session
        let potaComments: [VideoPOTAComment] = session.spotComments.compactMap { comment in
            guard let timestamp = comment.timestamp,
                  let text = comment.comments, !text.isEmpty
            else {
                return nil
            }
            return VideoPOTAComment(
                spotter: comment.spotter,
                comment: text,
                timestamp: timestamp
            )
        }

        // Build parameter events from recording
        let parameterEvents: [VideoParameterChange] = recording?.parameterChanges ?? []

        let request = VideoTimelineRequest(
            session: sessionSnapshot,
            qsos: qsoSnapshots,
            spots: spotSnapshots,
            parameterEvents: parameterEvents,
            potaComments: potaComments,
            recording: recording,
            config: config
        )

        return VideoExportLoadedData(request: request)
    }

    private func fetchParkName(parkReference: String?, context: ModelContext) -> String? {
        guard let parkRef = parkReference else {
            return nil
        }
        var descriptor = FetchDescriptor<ActivationMetadata>(
            predicate: #Predicate { $0.parkReference == parkRef }
        )
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first?.title
    }

    /// Returns operator coordinate from grid square, falling back to park GPS coordinates.
    private func operatorCoordinate(
        myGrid: String?,
        parkReference: String?
    ) -> CLLocationCoordinate2D? {
        // Prefer user's recorded grid square (must be non-empty and valid)
        if let grid = myGrid, !grid.isEmpty,
           let coord = MaidenheadConverter.coordinate(from: grid)
        {
            return CLLocationCoordinate2D(latitude: coord.latitude, longitude: coord.longitude)
        }
        // Fall back to park's GPS coordinates or grid from POTA cache
        if let parkRef = parkReference, !parkRef.isEmpty,
           let park = POTAParksCache.shared.parkSync(for: parkRef)
        {
            if let lat = park.latitude, let lon = park.longitude {
                return CLLocationCoordinate2D(latitude: lat, longitude: lon)
            }
            if let grid = park.grid, let coord = MaidenheadConverter.coordinate(from: grid) {
                return CLLocationCoordinate2D(latitude: coord.latitude, longitude: coord.longitude)
            }
        }
        return nil
    }

    private func mapSDRChangeType(
        _ type: SDRParameterEvent.ChangeType
    ) -> VideoParameterChange.ChangeType {
        switch type {
        case .frequency: .frequency
        case .mode: .mode
        case .pause: .pause
        case .resume: .resume
        case .sdrDisconnected: .sdrDisconnected
        case .sdrConnected: .sdrConnected
        }
    }
}
