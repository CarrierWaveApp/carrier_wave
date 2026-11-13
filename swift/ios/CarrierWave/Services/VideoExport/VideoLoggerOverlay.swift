// Video Logger Overlay
//
// State + placement for the in-replay "logger" panel that flies a freshly-logged
// QSO from a screen-corner card into its map marker. Pure value types and
// nonisolated helpers — no actors, no UIKit state.

import CoreGraphics
import Foundation

// MARK: - VideoLoggerOverlayState

nonisolated struct VideoLoggerOverlayState {
    nonisolated enum Phase: Equatable {
        case panel
        case flying(progress: CGFloat)
    }

    let qso: VideoQSOSnapshot
    let phase: Phase
    let panelRect: CGRect
    let panelRegionIndex: Int
    let landingPoint: CGPoint?
}

// MARK: - VideoLoggerOverlayTiming

nonisolated enum VideoLoggerOverlayTiming {
    static let panelHoldDuration: TimeInterval = 1.2
    static let flyDuration: TimeInterval = 0.8
    static let totalDuration: TimeInterval = panelHoldDuration + flyDuration

    static func phase(for age: TimeInterval) -> VideoLoggerOverlayState.Phase? {
        if age < 0 || age >= totalDuration {
            return nil
        }
        if age < panelHoldDuration {
            return .panel
        }
        let raw = (age - panelHoldDuration) / flyDuration
        return .flying(progress: CGFloat(min(1, max(0, raw))))
    }
}

// MARK: - VideoLoggerOverlayPlacement

nonisolated enum VideoLoggerOverlayPlacement {
    // MARK: Internal

    static let panelSize = CGSize(width: 380, height: 110)
    static let edgeMargin: CGFloat = 36
    static let avoidancePadding: CGFloat = 28
    static let hysteresisThreshold = 2

    static func candidateRects(reservedTop: CGFloat, reservedBottom: CGFloat) -> [CGRect] {
        let panelW = panelSize.width
        let panelH = panelSize.height
        let margin = edgeMargin
        let videoW = VideoOverlayRenderer.videoWidth
        let videoH = VideoOverlayRenderer.videoHeight
        let topY = max(margin, reservedTop + margin)
        let bottomY = videoH - panelH - max(margin, reservedBottom + margin)
        return [
            CGRect(x: videoW - panelW - margin, y: bottomY, width: panelW, height: panelH),
            CGRect(x: margin, y: bottomY, width: panelW, height: panelH),
            CGRect(x: videoW - panelW - margin, y: topY, width: panelW, height: panelH),
            CGRect(x: margin, y: topY, width: panelW, height: panelH),
        ]
    }

    static func selectRegion(
        markers: [CGPoint],
        previousIndex: Int?,
        reservedTop: CGFloat,
        reservedBottom: CGFloat
    ) -> (rect: CGRect, index: Int) {
        let rects = candidateRects(reservedTop: reservedTop, reservedBottom: reservedBottom)
        let scores = rects.map { rect in occlusionScore(rect: rect, markers: markers) }

        if let previous = previousIndex, previous < scores.count {
            let bestScore = scores.min() ?? 0
            if scores[previous] - bestScore < hysteresisThreshold {
                return (rects[previous], previous)
            }
        }

        let bestIndex = scores
            .enumerated()
            .min { left, right in
                if left.element != right.element {
                    return left.element < right.element
                }
                return left.offset < right.offset
            }?.offset ?? 0
        return (rects[bestIndex], bestIndex)
    }

    // MARK: Private

    private static func occlusionScore(rect: CGRect, markers: [CGPoint]) -> Int {
        let inflated = rect.insetBy(dx: -avoidancePadding, dy: -avoidancePadding)
        return markers.reduce(into: 0) { acc, marker in
            if inflated.contains(marker) {
                acc += 1
            }
        }
    }
}

// MARK: - VideoLoggerOverlayBuildRequest

nonisolated struct VideoLoggerOverlayBuildRequest {
    let moments: [VideoMoment]
    let videoTime: TimeInterval
    let markerScreenPoints: [UUID: CGPoint]
    let previousRegionIndex: Int?
    let reservedTop: CGFloat
    let reservedBottom: CGFloat
}

// MARK: - VideoLoggerOverlayBuilder

nonisolated enum VideoLoggerOverlayBuilder {
    // MARK: Internal

    /// Finds the most recent QSO commit within the active overlay window and returns
    /// the per-frame state, or nil if nothing is active.
    static func build(_ request: VideoLoggerOverlayBuildRequest) -> VideoLoggerOverlayState? {
        guard let active = activeQSO(in: request.moments, videoTime: request.videoTime) else {
            return nil
        }
        let avoid = otherMarkerPoints(
            excludingActiveID: active.qso.id, points: request.markerScreenPoints
        )
        let placement = VideoLoggerOverlayPlacement.selectRegion(
            markers: avoid,
            previousIndex: request.previousRegionIndex,
            reservedTop: request.reservedTop,
            reservedBottom: request.reservedBottom
        )
        let landingPoint = request.markerScreenPoints[active.qso.id]
        return VideoLoggerOverlayState(
            qso: active.qso,
            phase: active.phase,
            panelRect: placement.rect,
            panelRegionIndex: placement.index,
            landingPoint: landingPoint
        )
    }

    // MARK: Private

    private static func activeQSO(
        in moments: [VideoMoment], videoTime: TimeInterval
    ) -> (qso: VideoQSOSnapshot, phase: VideoLoggerOverlayState.Phase)? {
        for moment in moments.reversed() {
            let age = videoTime - moment.videoTime
            if age >= VideoLoggerOverlayTiming.totalDuration {
                return nil
            }
            if age < 0 {
                continue
            }
            for event in moment.events.reversed() {
                if case let .qsoAppeared(qso) = event {
                    if let phase = VideoLoggerOverlayTiming.phase(for: age) {
                        return (qso, phase)
                    }
                }
            }
        }
        return nil
    }

    private static func otherMarkerPoints(
        excludingActiveID: UUID, points: [UUID: CGPoint]
    ) -> [CGPoint] {
        points.compactMap { id, point in
            id == excludingActiveID ? nil : point
        }
    }
}

// MARK: - VideoLoggerOverlayInterpolator

nonisolated enum VideoLoggerOverlayInterpolator {
    /// Applies an ease-in-out cubic curve so the card accelerates out of the panel
    /// and decelerates into the marker.
    static func easedProgress(_ raw: CGFloat) -> CGFloat {
        let clamped = max(0, min(1, raw))
        if clamped < 0.5 {
            return 4 * clamped * clamped * clamped
        }
        let shifted = clamped - 1
        return 1 + 4 * shifted * shifted * shifted
    }

    /// Interpolates between the panel center and the landing point.
    static func currentCenter(panel: CGRect, landing: CGPoint, progress: CGFloat) -> CGPoint {
        let from = CGPoint(x: panel.midX, y: panel.midY)
        let eased = easedProgress(progress)
        return CGPoint(
            x: from.x + (landing.x - from.x) * eased,
            y: from.y + (landing.y - from.y) * eased
        )
    }

    /// Card scales from 1.0 → 0.35 as it lands, simulating a snap to the marker.
    static func currentScale(progress: CGFloat) -> CGFloat {
        let eased = easedProgress(progress)
        return 1.0 - 0.65 * eased
    }

    /// Card fades out across the second half of the flight so the marker takes over.
    static func currentOpacity(progress: CGFloat) -> CGFloat {
        let eased = easedProgress(progress)
        return 1.0 - max(0, (eased - 0.4) / 0.6)
    }
}
