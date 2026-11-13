// Video Export Actor — Frame State Builder
//
// Builds a FrameRenderState for each video frame from the timeline.

import CoreGraphics
import CoreLocation
import Foundation
import MapKit
import UIKit

// MARK: - FrameRenderState Builder

extension VideoExportActor {
    // MARK: - Constants

    static let qsoFadeInDuration: TimeInterval = 0.5
    static let spotPulseDuration: TimeInterval = 2.0
    static let toastSlideInDuration: TimeInterval = 0.3
    static let toastHoldDuration: TimeInterval = 3.5
    static let toastSlideOutDuration: TimeInterval = 0.3
    static let toastTotalDuration: TimeInterval = toastSlideInDuration + toastHoldDuration + toastSlideOutDuration
    static let defaultMapSpan = MKCoordinateSpan(latitudeDelta: 5.0, longitudeDelta: 5.0)

    // MARK: - Main Builder

    struct FrameRenderInputs {
        let videoTime: TimeInterval
        let timeline: VideoTimeline
        let cachedMapImage: UIImage?
        let previousCameraCenter: CLLocationCoordinate2D?
        let previousCameraSpan: MKCoordinateSpan?
        let previousLoggerRegion: Int?
        let loggerOverlayEnabled: Bool
    }

    private struct FramePieces {
        let visibleQSOs: [(qso: VideoQSOSnapshot, opacity: CGFloat)]
        let activeSpots: [(spot: VideoSpotSnapshot, pulseProgress: CGFloat)]
        let toastCard: ToastCardState?
        let hudCallsign: String
        let hudParkReference: String?
        let hudFrequency: String
        let hudMode: String
        let center: CLLocationCoordinate2D
        let span: MKCoordinateSpan
        let mapImage: UIImage?
        let region: MKCoordinateRegion
        let myScreenPoint: CGPoint?
        let realElapsed: TimeInterval
        let qsoRate: String?
        let equipmentLine: String?
        let loggerOverlay: VideoLoggerOverlayState?
    }

    func buildFrameRenderState(_ input: FrameRenderInputs) -> FrameRenderState {
        let moments = input.timeline.moments.filter { $0.videoTime <= input.videoTime }
        let pieces = computeFramePieces(input: input, moments: moments)
        return assembleFrameRenderState(timeline: input.timeline, pieces: pieces)
    }

    private func computeFramePieces(
        input: FrameRenderInputs, moments: [VideoMoment]
    ) -> FramePieces {
        let timeline = input.timeline
        let videoTime = input.videoTime
        // Camera looks ahead by the panel-hold so the destination is already
        // in frame by the time the hero animation starts to fly.
        let lookahead = input.loggerOverlayEnabled ? VideoLoggerOverlayTiming.panelHoldDuration : 0
        let cameraMoments = timeline.moments.filter { $0.videoTime <= videoTime + lookahead }

        let visibleQSOs = buildVisibleQSOs(
            moments: moments, videoTime: videoTime, deferMarkerSpawn: input.loggerOverlayEnabled
        )
        let activeSpots = buildSpots(moments: moments, videoTime: videoTime)
        let toastCard = buildToastCard(moments: moments, videoTime: videoTime)
        let hud = buildHUD(moments: moments, timeline: timeline)
        let (center, span) = buildCamera(moments: cameraMoments, timeline: timeline)
        let mapImage = isCameraChanged(
            center: center, span: span,
            previousCenter: input.previousCameraCenter, previousSpan: input.previousCameraSpan
        ) ? nil : input.cachedMapImage
        let region = MKCoordinateRegion(center: center, span: span)
        let myScreenPoint = timeline.metadata.myCoordinate.flatMap {
            projectCoordinate($0, in: region)
        }
        let realElapsed = realElapsedTime(videoTime: videoTime, timeline: timeline)
        let qsoRate = formatQSORate(elapsed: realElapsed, count: visibleQSOs.count)
        let overlay = input.loggerOverlayEnabled
            ? buildLoggerOverlay(
                moments: moments, videoTime: videoTime,
                visibleQSOs: visibleQSOs, region: region,
                previousRegion: input.previousLoggerRegion
            )
            : nil
        return FramePieces(
            visibleQSOs: visibleQSOs, activeSpots: activeSpots, toastCard: toastCard,
            hudCallsign: hud.callsign, hudParkReference: hud.parkReference,
            hudFrequency: hud.frequency, hudMode: hud.mode,
            center: center, span: span, mapImage: mapImage, region: region,
            myScreenPoint: myScreenPoint, realElapsed: realElapsed, qsoRate: qsoRate,
            equipmentLine: buildEquipmentLine(metadata: timeline.metadata),
            loggerOverlay: overlay
        )
    }

    private func assembleFrameRenderState(
        timeline: VideoTimeline, pieces: FramePieces
    ) -> FrameRenderState {
        FrameRenderState(
            visibleQSOs: pieces.visibleQSOs,
            visibleSpots: pieces.activeSpots,
            toastCard: pieces.toastCard,
            hudCallsign: pieces.hudCallsign,
            hudParkReference: pieces.hudParkReference,
            hudFrequency: pieces.hudFrequency,
            hudMode: pieces.hudMode,
            hudElapsedTime: pieces.realElapsed,
            hudParkName: timeline.metadata.parkName,
            hudEquipmentLine: pieces.equipmentLine,
            hudQSOCount: pieces.visibleQSOs.count,
            hudQSORate: pieces.qsoRate,
            cameraCenter: pieces.center,
            cameraSpan: pieces.span,
            cachedMapImage: pieces.mapImage,
            mapRegion: pieces.region,
            myScreenPoint: pieces.myScreenPoint,
            myCoordinate: timeline.metadata.myCoordinate,
            loggerOverlay: pieces.loggerOverlay
        )
    }

    private func formatQSORate(elapsed: TimeInterval, count: Int) -> String? {
        guard elapsed > 0 else {
            return nil
        }
        return String(format: "%.1f/hr", Double(count) / (elapsed / 3_600))
    }

    private func buildLoggerOverlay(
        moments: [VideoMoment],
        videoTime: TimeInterval,
        visibleQSOs: [(qso: VideoQSOSnapshot, opacity: CGFloat)],
        region: MKCoordinateRegion,
        previousRegion: Int?
    ) -> VideoLoggerOverlayState? {
        var markerPoints: [UUID: CGPoint] = [:]
        for entry in visibleQSOs {
            if let coord = entry.qso.coordinate,
               let pt = projectCoordinate(coord, in: region)
            {
                markerPoints[entry.qso.id] = pt
            }
        }
        return VideoLoggerOverlayBuilder.build(VideoLoggerOverlayBuildRequest(
            moments: moments,
            videoTime: videoTime,
            markerScreenPoints: markerPoints,
            previousRegionIndex: previousRegion,
            reservedTop: 0,
            reservedBottom: 0
        ))
    }

    // MARK: - QSOs

    private func buildVisibleQSOs(
        moments: [VideoMoment],
        videoTime: TimeInterval,
        deferMarkerSpawn: Bool
    ) -> [(qso: VideoQSOSnapshot, opacity: CGFloat)] {
        var result: [(qso: VideoQSOSnapshot, opacity: CGFloat)] = []
        let spawnDelay = deferMarkerSpawn ? VideoLoggerOverlayTiming.panelHoldDuration : 0
        for moment in moments {
            for event in moment.events {
                if case let .qsoAppeared(qso) = event {
                    let age = videoTime - moment.videoTime - spawnDelay
                    if age < 0 {
                        continue
                    }
                    let opacity = min(1.0, age / Self.qsoFadeInDuration)
                    result.append((qso: qso, opacity: CGFloat(opacity)))
                }
            }
        }
        return result
    }

    // MARK: - Spots

    private func buildSpots(
        moments: [VideoMoment],
        videoTime: TimeInterval
    ) -> [(spot: VideoSpotSnapshot, pulseProgress: CGFloat)] {
        var active: [(spot: VideoSpotSnapshot, pulseProgress: CGFloat)] = []

        for moment in moments {
            for event in moment.events {
                if case let .spotPulse(spot) = event {
                    let age = videoTime - moment.videoTime
                    if age <= Self.spotPulseDuration {
                        let progress = CGFloat(age / Self.spotPulseDuration)
                        active.append((spot: spot, pulseProgress: progress))
                    }
                }
            }
        }
        return active
    }

    // MARK: - Toast

    private struct ToastEvent {
        let videoTime: TimeInterval
        let text: String
        let iconName: String
        let name: String?
        let rstSent: String?
        let rstReceived: String?
        let parkRef: String?
    }

    private func buildToastCard(
        moments: [VideoMoment],
        videoTime: TimeInterval
    ) -> ToastCardState? {
        var toastEvents: [ToastEvent] = []
        for moment in moments {
            for event in moment.events {
                switch event {
                case let .qsoAppeared(qso):
                    toastEvents.append(ToastEvent(
                        videoTime: moment.videoTime,
                        text: qso.callsign,
                        iconName: "antenna.radiowaves.left.and.right",
                        name: qso.name,
                        rstSent: qso.rstSent,
                        rstReceived: qso.rstReceived,
                        parkRef: qso.theirParkRef
                    ))
                case let .qsy(freq, _):
                    toastEvents.append(ToastEvent(
                        videoTime: moment.videoTime, text: freq,
                        iconName: "waveform",
                        name: nil, rstSent: nil, rstReceived: nil, parkRef: nil
                    ))
                case .potaNote,
                     .spotPulse:
                    break
                }
            }
        }

        for toast in toastEvents.reversed() {
            let age = videoTime - toast.videoTime
            guard age >= 0, age < Self.toastTotalDuration else {
                continue
            }
            let slideProgress = computeSlideProgress(age: age)
            return ToastCardState(
                text: toast.text, iconName: toast.iconName,
                slideProgress: slideProgress,
                name: toast.name,
                rstSent: toast.rstSent,
                rstReceived: toast.rstReceived,
                parkRef: toast.parkRef
            )
        }
        return nil
    }

    private func computeSlideProgress(age: TimeInterval) -> CGFloat {
        let slideIn = Self.toastSlideInDuration
        let hold = Self.toastHoldDuration
        if age < slideIn {
            return CGFloat(age / slideIn)
        } else if age < slideIn + hold {
            return 1.0
        } else {
            let outAge = age - slideIn - hold
            return CGFloat(1.0 - (outAge / Self.toastSlideOutDuration))
        }
    }

    // MARK: - HUD

    private struct HUDState {
        let callsign: String
        let parkReference: String?
        let frequency: String
        let mode: String
    }

    private func buildHUD(
        moments: [VideoMoment],
        timeline: VideoTimeline
    ) -> HUDState {
        var frequency = timeline.metadata.initialFrequency ?? "—"
        var mode = timeline.metadata.initialMode ?? "—"

        for moment in moments {
            for event in moment.events {
                if case let .qsy(freq, newMode) = event {
                    frequency = freq
                    if !newMode.isEmpty {
                        mode = newMode
                    }
                }
            }
        }

        return HUDState(
            callsign: timeline.metadata.callsign,
            parkReference: timeline.metadata.parkReference,
            frequency: frequency,
            mode: mode
        )
    }

    // MARK: - Camera

    private func buildCamera(
        moments: [VideoMoment],
        timeline: VideoTimeline
    ) -> (center: CLLocationCoordinate2D, span: MKCoordinateSpan) {
        let target = moments.last(where: { $0.cameraTarget != nil })?.cameraTarget
        let center = target ?? timeline.metadata.myCoordinate ?? CLLocationCoordinate2D(
            latitude: 37.3318,
            longitude: -122.0312
        )

        var coords: [CLLocationCoordinate2D] = []
        if let myCoord = timeline.metadata.myCoordinate {
            coords.append(myCoord)
        }
        for moment in moments {
            for event in moment.events {
                if case let .qsoAppeared(qso) = event, let coord = qso.coordinate {
                    coords.append(coord)
                }
            }
        }

        let span = spanForCoordinates(coords) ?? Self.defaultMapSpan
        return (center, span)
    }

    private func spanForCoordinates(_ coords: [CLLocationCoordinate2D]) -> MKCoordinateSpan? {
        guard coords.count > 1 else {
            return nil
        }
        let lats = coords.map(\.latitude)
        let lons = coords.map(\.longitude)
        guard let minLat = lats.min(), let maxLat = lats.max(),
              let minLon = lons.min(), let maxLon = lons.max()
        else {
            return nil
        }
        let padding = 1.5
        return MKCoordinateSpan(
            latitudeDelta: max(0.5, (maxLat - minLat) * padding),
            longitudeDelta: max(0.5, (maxLon - minLon) * padding)
        )
    }

    // MARK: - Camera Change Detection

    private func isCameraChanged(
        center: CLLocationCoordinate2D,
        span: MKCoordinateSpan,
        previousCenter: CLLocationCoordinate2D?,
        previousSpan: MKCoordinateSpan?
    ) -> Bool {
        guard let prev = previousCenter, let prevSpan = previousSpan else {
            return true
        }
        // Widen thresholds to reduce expensive MKMapSnapshotter re-fetches.
        // 0.01° ≈ 1.1km position change, 0.1° span change.
        let latChanged = abs(center.latitude - prev.latitude) > 0.01
        let lonChanged = abs(center.longitude - prev.longitude) > 0.01
        let spanChanged = abs(span.latitudeDelta - prevSpan.latitudeDelta) > 0.1
        return latChanged || lonChanged || spanChanged
    }

    // MARK: - Coordinate Projection

    private func projectCoordinate(
        _ coordinate: CLLocationCoordinate2D,
        in region: MKCoordinateRegion
    ) -> CGPoint? {
        guard CLLocationCoordinate2DIsValid(coordinate) else {
            return nil
        }
        let mapPoint = MKMapPoint(coordinate)
        let topLeft = CLLocationCoordinate2D(
            latitude: region.center.latitude + region.span.latitudeDelta / 2,
            longitude: region.center.longitude - region.span.longitudeDelta / 2
        )
        let bottomRight = CLLocationCoordinate2D(
            latitude: region.center.latitude - region.span.latitudeDelta / 2,
            longitude: region.center.longitude + region.span.longitudeDelta / 2
        )
        let tl = MKMapPoint(topLeft)
        let br = MKMapPoint(bottomRight)
        let width = br.x - tl.x
        let height = br.y - tl.y
        guard width > 0, height > 0 else {
            return nil
        }
        let xFraction = (mapPoint.x - tl.x) / width
        let yFraction = (mapPoint.y - tl.y) / height
        return CGPoint(x: xFraction * 1_920, y: yFraction * 1_080)
    }

    // MARK: - Real Elapsed Time

    /// Maps compressed video time back to real session elapsed time by interpolating
    /// between moments. During compressed gaps, the timestamp accelerates to show
    /// real time passing.
    private func realElapsedTime(videoTime: TimeInterval, timeline: VideoTimeline) -> TimeInterval {
        let moments = timeline.moments
        guard !moments.isEmpty else {
            return videoTime
        }
        let sessionStart = timeline.metadata.startedAt

        // Before first moment: interpolate from 0 to first moment's real time
        guard let first = moments.first, videoTime >= first.videoTime else {
            if let first = moments.first, first.videoTime > 0 {
                let fraction = videoTime / first.videoTime
                return first.realTime.timeIntervalSince(sessionStart) * fraction
            }
            return videoTime
        }

        // Find the two moments bracketing videoTime
        var prev = first
        for moment in moments.dropFirst() {
            if moment.videoTime > videoTime {
                return interpolateRealTime(
                    videoTime: videoTime, prev: prev, next: moment, sessionStart: sessionStart
                )
            }
            prev = moment
        }

        // After last moment: extrapolate linearly (1:1 with video time)
        let overshoot = videoTime - prev.videoTime
        return prev.realTime.timeIntervalSince(sessionStart) + overshoot
    }

    private func interpolateRealTime(
        videoTime: TimeInterval, prev: VideoMoment,
        next: VideoMoment, sessionStart: Date
    ) -> TimeInterval {
        let videoSpan = next.videoTime - prev.videoTime
        let fraction = videoSpan > 0 ? (videoTime - prev.videoTime) / videoSpan : 0
        let prevReal = prev.realTime.timeIntervalSince(sessionStart)
        let nextReal = next.realTime.timeIntervalSince(sessionStart)
        return prevReal + (nextReal - prevReal) * fraction
    }

    // MARK: - Equipment

    private func buildEquipmentLine(metadata: VideoSessionSnapshot) -> String? {
        var parts: [String] = []
        if let rig = metadata.myRig, !rig.isEmpty {
            parts.append(rig)
        }
        if let ant = metadata.myAntenna, !ant.isEmpty {
            parts.append(ant)
        }
        if let pw = metadata.power {
            parts.append("\(pw)W")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
