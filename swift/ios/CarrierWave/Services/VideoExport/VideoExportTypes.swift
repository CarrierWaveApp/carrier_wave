// Video Export Types
//
// Sendable value types used across the video export pipeline.

import CoreLocation
import Foundation
import MapKit
import UIKit

// MARK: - VideoExportConfig

nonisolated struct VideoExportConfig {
    nonisolated enum Mode: Codable {
        case highlightReel
        case fullReplay
    }

    nonisolated enum MapStyle: Int, Codable {
        case standard
        case satellite
        case hybrid
    }

    let sessionId: UUID
    let mode: Mode
    let includeAudio: Bool
    let mapStyle: MapStyle
    let layers: LayerVisibility
    let hudDensity: HUDDensity
    let theme: ThemePreset
}

// MARK: - LayerVisibility

nonisolated struct LayerVisibility: Codable, Equatable {
    // MARK: Lifecycle

    init(
        showSpots: Bool,
        showArcs: Bool,
        showQSOMarkers: Bool,
        showCallsignCards: Bool,
        showToasts: Bool,
        recentQSOCardCount: Int,
        showLoggerOverlay: Bool
    ) {
        self.showSpots = showSpots
        self.showArcs = showArcs
        self.showQSOMarkers = showQSOMarkers
        self.showCallsignCards = showCallsignCards
        self.showToasts = showToasts
        self.recentQSOCardCount = recentQSOCardCount
        self.showLoggerOverlay = showLoggerOverlay
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        showSpots = try container.decode(Bool.self, forKey: .showSpots)
        showArcs = try container.decode(Bool.self, forKey: .showArcs)
        showQSOMarkers = try container.decode(Bool.self, forKey: .showQSOMarkers)
        showCallsignCards = try container.decode(Bool.self, forKey: .showCallsignCards)
        showToasts = try container.decode(Bool.self, forKey: .showToasts)
        recentQSOCardCount = try container.decode(Int.self, forKey: .recentQSOCardCount)
        showLoggerOverlay = try container.decodeIfPresent(Bool.self, forKey: .showLoggerOverlay) ?? true
    }

    // MARK: Internal

    static let defaults = LayerVisibility(
        showSpots: true,
        showArcs: true,
        showQSOMarkers: true,
        showCallsignCards: true,
        showToasts: true,
        recentQSOCardCount: 3,
        showLoggerOverlay: true
    )

    var showSpots: Bool
    var showArcs: Bool
    var showQSOMarkers: Bool
    var showCallsignCards: Bool
    var showToasts: Bool
    var recentQSOCardCount: Int
    var showLoggerOverlay: Bool
}

// MARK: - HUDDensity

nonisolated enum HUDDensity: String, Codable, CaseIterable {
    case full
    case compact
    case minimal
    case off

    // MARK: Internal

    var label: String {
        switch self {
        case .full: "Full"
        case .compact: "Compact"
        case .minimal: "Minimal"
        case .off: "Off"
        }
    }
}

// MARK: - ThemePreset

nonisolated enum ThemePreset: String, Codable, CaseIterable {
    case classic
    case night
    case highContrast
    case minimal

    // MARK: Internal

    var label: String {
        switch self {
        case .classic: "Classic"
        case .night: "Night"
        case .highContrast: "High Contrast"
        case .minimal: "Minimal"
        }
    }
}

// MARK: - VideoExportResult

nonisolated enum VideoExportResult {
    case success(URL)
    case cancelled
    case failed(String)
}

// MARK: - VideoExportProgress

nonisolated struct VideoExportProgress {
    let framesCompleted: Int
    let totalFrames: Int
    let estimatedSecondsRemaining: TimeInterval?
    let latestThumbnail: CGImage?
}

// MARK: - VideoEvent

nonisolated enum VideoEvent {
    case qsoAppeared(VideoQSOSnapshot)
    case spotPulse(VideoSpotSnapshot)
    case qsy(frequency: String, mode: String)
    case potaNote(spotter: String, comment: String)
}

// MARK: - VideoMoment

nonisolated struct VideoMoment {
    let realTime: Date
    let videoTime: TimeInterval
    let events: [VideoEvent]
    let cameraTarget: CLLocationCoordinate2D?
    let cameraZoom: Double?
    let audioSourceOffset: TimeInterval?
}

// MARK: - VideoTimeline

nonisolated struct VideoTimeline {
    let moments: [VideoMoment]
    let totalDuration: TimeInterval
    let totalFrames: Int
    let metadata: VideoSessionSnapshot
}

// MARK: - VideoSessionSnapshot

nonisolated struct VideoSessionSnapshot {
    let callsign: String
    let parkReference: String?
    let parkName: String?
    let myGrid: String?
    let myCoordinate: CLLocationCoordinate2D?
    let startedAt: Date
    let endedAt: Date
    let initialFrequency: String?
    let initialMode: String?
    let myRig: String?
    let myAntenna: String?
    let power: Int?
    let extraEquipment: String?
}

// MARK: - VideoQSOSnapshot

nonisolated struct VideoQSOSnapshot {
    let id: UUID
    let callsign: String
    let timestamp: Date
    let band: String
    let mode: String
    let rstSent: String?
    let rstReceived: String?
    let coordinate: CLLocationCoordinate2D?
    let distanceKm: Double?
    // Enrichment fields
    let name: String?
    let clubEmoji: String?
    let clubName: String?
    let priorQSOCount: Int
    let theirParkRef: String?
    let sotaRef: String?
    let wwffRef: String?
    let country: String?
}

// MARK: - VideoSpotSnapshot

nonisolated struct VideoSpotSnapshot {
    let id: UUID
    let timestamp: Date
    let spotter: String
    let snr: Int?
    let coordinate: CLLocationCoordinate2D?
}

// MARK: - VideoRecordingSnapshot

nonisolated struct VideoRecordingSnapshot {
    let fileURL: URL
    let startedAt: Date
    let durationSeconds: Double
    let frequencyKHz: Double
    let mode: String
    let parameterChanges: [VideoParameterChange]
}

// MARK: - VideoPOTAComment

nonisolated struct VideoPOTAComment {
    let spotter: String
    let comment: String
    let timestamp: Date
}

// MARK: - VideoTimelineRequest

nonisolated struct VideoTimelineRequest {
    let session: VideoSessionSnapshot
    let qsos: [VideoQSOSnapshot]
    let spots: [VideoSpotSnapshot]
    let parameterEvents: [VideoParameterChange]
    let potaComments: [VideoPOTAComment]
    let recording: VideoRecordingSnapshot?
    let config: VideoExportConfig
}

// MARK: - VideoParameterChange

nonisolated struct VideoParameterChange {
    nonisolated enum ChangeType {
        case frequency
        case mode
        case pause
        case resume
        case sdrDisconnected
        case sdrConnected
    }

    let type: ChangeType
    let offsetSeconds: Double
    let oldValue: String
    let newValue: String
}

// MARK: - FrameRenderState

/// All state needed to render a single video frame.
/// Built by the pipeline from the VideoTimeline for each frame index.
nonisolated struct FrameRenderState: @unchecked Sendable {
    // @unchecked because UIImage is not Sendable, but FrameRenderState
    // never crosses actor boundaries — it's built and consumed within
    // VideoExportActor's pipeline loop.

    /// Visible QSOs with their fade-in opacity (0 = invisible, 1 = fully visible)
    let visibleQSOs: [(qso: VideoQSOSnapshot, opacity: CGFloat)]

    /// Visible spots with pulse animation progress (0 = start, 1 = fully expanded)
    let visibleSpots: [(spot: VideoSpotSnapshot, pulseProgress: CGFloat)]

    /// Current toast card state (nil = no toast visible)
    let toastCard: ToastCardState?

    /// HUD values
    let hudCallsign: String
    let hudParkReference: String?
    let hudFrequency: String
    let hudMode: String
    let hudElapsedTime: TimeInterval
    let hudParkName: String?
    let hudEquipmentLine: String?
    let hudQSOCount: Int
    let hudQSORate: String?

    /// Camera state for map snapshot
    let cameraCenter: CLLocationCoordinate2D
    let cameraSpan: MKCoordinateSpan

    /// Cached map image from previous frame (nil = need new snapshot)
    let cachedMapImage: UIImage?

    /// Map region for coordinate-to-screen-point projection.
    let mapRegion: MKCoordinateRegion

    /// Operator's screen coordinate (projected from myCoordinate)
    let myScreenPoint: CGPoint?

    /// Operator's raw coordinate for snapshot-based projection
    let myCoordinate: CLLocationCoordinate2D?

    /// Active logger overlay (panel + hero animation), nil when no recent commit.
    let loggerOverlay: VideoLoggerOverlayState?
}

// MARK: - ToastCardState

nonisolated struct ToastCardState {
    let text: String
    let iconName: String
    /// 0 = fully offscreen below, 1 = fully visible, decreasing = sliding out
    let slideProgress: CGFloat
    /// QSO-specific enrichment for toast card display
    let name: String?
    let rstSent: String?
    let rstReceived: String?
    let parkRef: String?
}
