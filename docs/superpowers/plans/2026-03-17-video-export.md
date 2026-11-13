# Video Export Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Export a polished, YouTube-ready 1080p MP4 video from a completed logging session, combining map replay with WebSDR audio and event toast cards.

**Architecture:** Three-stage pipeline (Event Sequencer → Frame Compositor → Video Writer) orchestrated by a background `VideoExportActor`. Data loaded via SwiftData, converted to `Sendable` snapshots. Map rendered via `MKMapSnapshotter` (hopping to `@MainActor`), overlays drawn with Core Graphics, output written with `AVAssetWriter`.

**Tech Stack:** AVFoundation (AVAssetWriter/AVAssetReader), MapKit (MKMapSnapshotter), Core Graphics, SwiftData

**Spec:** `docs/superpowers/specs/2026-03-17-video-export-design.md`

---

## Task 1: Types & Snapshots (`VideoExportTypes.swift`)

Define all value types used across the pipeline. No dependencies on other new files.

**Files:**
- Create: `CarrierWave/Services/VideoExport/VideoExportTypes.swift`

- [ ] **Step 1: Create the types file**

```swift
// Video Export Types
//
// Sendable value types used across the video export pipeline.

import CoreLocation
import Foundation

// MARK: - VideoExportConfig

struct VideoExportConfig: Sendable {
    enum Mode: Sendable {
        case highlightReel
        case fullReplay
    }

    enum MapStyle: Int, Sendable {
        case standard
        case satellite
        case hybrid
    }

    let sessionId: UUID
    let mode: Mode
    let includeAudio: Bool
    let mapStyle: MapStyle
}

// MARK: - VideoExportResult

enum VideoExportResult: Sendable {
    case success(URL)
    case cancelled
    case failed(String)
}

// MARK: - VideoExportProgress

struct VideoExportProgress: Sendable {
    let framesCompleted: Int
    let totalFrames: Int
    let estimatedSecondsRemaining: TimeInterval?
    let latestThumbnail: CGImage?
}

// MARK: - VideoEvent

enum VideoEvent: Sendable {
    case qsoAppeared(VideoQSOSnapshot)
    case spotPulse(VideoSpotSnapshot)
    case qsy(frequency: String, mode: String)
    case potaNote(spotter: String, comment: String)
}

// MARK: - VideoMoment

struct VideoMoment: Sendable {
    let realTime: Date
    let videoTime: TimeInterval
    let events: [VideoEvent]
    let cameraTarget: CLLocationCoordinate2D?
    let cameraZoom: Double?
    let audioSourceOffset: TimeInterval?
}

// MARK: - VideoTimeline

struct VideoTimeline: Sendable {
    let moments: [VideoMoment]
    let totalDuration: TimeInterval
    let totalFrames: Int
    let metadata: VideoSessionSnapshot
}

// MARK: - Sendable Snapshots

struct VideoSessionSnapshot: Sendable {
    let callsign: String
    let parkReference: String?
    let parkName: String?
    let myGrid: String?
    let myCoordinate: CLLocationCoordinate2D?
    let startedAt: Date
    let endedAt: Date
    let initialFrequency: String?
    let initialMode: String?
}

struct VideoQSOSnapshot: Sendable {
    let id: UUID
    let callsign: String
    let timestamp: Date
    let band: String
    let mode: String
    let rstSent: String?
    let rstReceived: String?
    let coordinate: CLLocationCoordinate2D?
    let distanceKm: Double?
}

struct VideoSpotSnapshot: Sendable {
    let id: UUID
    let timestamp: Date
    let spotter: String
    let snr: Int?
    let coordinate: CLLocationCoordinate2D?
}

struct VideoRecordingSnapshot: Sendable {
    let fileURL: URL
    let startedAt: Date
    let durationSeconds: Double
    let frequencyKHz: Double
    let mode: String
    let parameterChanges: [VideoParameterChange]
}

struct VideoParameterChange: Sendable {
    enum ChangeType: Sendable {
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
struct FrameRenderState: Sendable {
    /// Visible QSOs with their fade-in opacity (0 = invisible, 1 = fully visible)
    let visibleQSOs: [(qso: VideoQSOSnapshot, opacity: CGFloat)]

    /// Visible spots with pulse animation progress (0 = start, 1 = fully expanded)
    let visibleSpots: [(spot: VideoSpotSnapshot, pulseProgress: CGFloat)]

    /// Residual spot dots after pulse animation (with fade-out opacity)
    let residualSpotDots: [(spot: VideoSpotSnapshot, opacity: CGFloat)]

    /// Current toast card state (nil = no toast visible)
    let toastCard: ToastCardState?

    /// HUD values
    let hudCallsign: String
    let hudParkReference: String?
    let hudFrequency: String
    let hudMode: String
    let hudElapsedTime: TimeInterval

    /// Camera state for map snapshot
    let cameraCenter: CLLocationCoordinate2D
    let cameraSpan: MKCoordinateSpan

    /// Cached map image from previous frame (nil = need new snapshot)
    let cachedMapImage: UIImage?

    /// Map region for coordinate-to-screen-point projection.
    /// The compositor uses this with MKMapSnapshotter.point(for:) or
    /// manual MKMapRect projection — no closure needed.
    let mapRegion: MKCoordinateRegion

    /// Operator's screen coordinate (projected from myCoordinate)
    let myScreenPoint: CGPoint?
}

// MARK: - ToastCardState

struct ToastCardState: Sendable {
    let text: String
    let iconName: String
    /// 0 = fully offscreen below, 1 = fully visible, decreasing = sliding out
    let slideProgress: CGFloat
}
```

Note: `FrameRenderState` imports `MapKit` (`MKCoordinateSpan`, `MKCoordinateRegion`) and `UIKit` (`UIImage`). The `UIImage` field for `cachedMapImage` is safe because `FrameRenderState` never crosses actor boundaries — it's built and consumed entirely within `VideoExportActor`'s pipeline loop. Mark the struct `@unchecked Sendable` if the compiler objects, with a comment explaining why.

- [ ] **Step 2: Run SwiftLint**

Run: `swiftlint lint --path CarrierWave/Services/VideoExport/VideoExportTypes.swift`
Expected: No warnings

- [ ] **Step 3: Commit**

```bash
git add CarrierWave/Services/VideoExport/VideoExportTypes.swift
git commit -m "feat(video-export): add Sendable types for video export pipeline"
```

---

## Task 2: Event Sequencer (`VideoEventSequencer.swift`)

Builds a `VideoTimeline` from session data snapshots. Pure logic, no framework dependencies beyond Foundation. Testable in isolation.

**Files:**
- Create: `CarrierWave/Services/VideoExport/VideoEventSequencer.swift`
- Create: `CarrierWaveTests/VideoExport/VideoEventSequencerTests.swift`

- [ ] **Step 1: Write tests for real-time mode**

```swift
import Testing
@testable import CarrierWave
import CoreLocation
import Foundation

@Suite("VideoEventSequencer")
struct VideoEventSequencerTests {
    let sequencer = VideoEventSequencer()

    let sessionStart = Date(timeIntervalSince1970: 1_000_000)

    func makeSession(endOffset: TimeInterval = 3600) -> VideoSessionSnapshot {
        VideoSessionSnapshot(
            callsign: "N3VEM",
            parkReference: "US-4557",
            parkName: "Test Park",
            myGrid: "FM19",
            myCoordinate: CLLocationCoordinate2D(latitude: 39.0, longitude: -77.0),
            startedAt: sessionStart,
            endedAt: sessionStart.addingTimeInterval(endOffset),
            initialFrequency: "7043.5",
            initialMode: "CW"
        )
    }

    func makeQSO(offsetSeconds: TimeInterval, callsign: String = "KM4CFT") -> VideoQSOSnapshot {
        VideoQSOSnapshot(
            id: UUID(),
            callsign: callsign,
            timestamp: sessionStart.addingTimeInterval(offsetSeconds),
            band: "40m",
            mode: "CW",
            rstSent: "599",
            rstReceived: "579",
            coordinate: CLLocationCoordinate2D(latitude: 35.0, longitude: -80.0),
            distanceKm: 500
        )
    }

    @Test("Real-time mode maps videoTime to session offset")
    func realTimeModeMapping() {
        let qsos = [makeQSO(offsetSeconds: 60), makeQSO(offsetSeconds: 120, callsign: "W1AW")]
        let timeline = sequencer.buildTimeline(
            session: makeSession(),
            qsos: qsos,
            spots: [],
            parameterEvents: [],
            potaComments: [],
            recording: nil,
            config: VideoExportConfig(
                sessionId: UUID(), mode: .fullReplay,
                includeAudio: false, mapStyle: .standard
            )
        )

        #expect(timeline.moments.count == 2)
        #expect(abs(timeline.moments[0].videoTime - 60) < 0.01)
        #expect(abs(timeline.moments[1].videoTime - 120) < 0.01)
    }

    @Test("Real-time mode total duration matches session length")
    func realTimeDuration() {
        let qsos = [makeQSO(offsetSeconds: 60)]
        let timeline = sequencer.buildTimeline(
            session: makeSession(endOffset: 3600),
            qsos: qsos, spots: [], parameterEvents: [],
            potaComments: [], recording: nil,
            config: VideoExportConfig(
                sessionId: UUID(), mode: .fullReplay,
                includeAudio: false, mapStyle: .standard
            )
        )
        #expect(abs(timeline.totalDuration - 3600) < 0.01)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xc test-unit` (or targeted test if available)
Expected: FAIL — `VideoEventSequencer` does not exist

- [ ] **Step 3: Implement `VideoEventSequencer`**

Key methods:
- `buildTimeline(session:qsos:spots:parameterEvents:potaComments:recording:config:) -> VideoTimeline`
- Private: `buildRealTimeTimeline(...)` — maps events 1:1
- Private: `buildHighlightTimeline(...)` — applies gap compression algorithm
- Private: `mergeEvents(...)` — merges events within 1s tolerance into single moments
- Private: `computeCamera(...)` — calculates camera target/zoom for each moment

Gap compression rules (highlight mode):
- Gap < 30s: keep real-time
- Gap 30s–5min: compress to 4s
- Gap > 5min: compress to 6s

Frame count: `Int(totalDuration * 30)` (30fps).

The sequencer is a plain struct (no actor needed — it's pure computation called from the actor).

```swift
// Video Event Sequencer
//
// Builds a VideoTimeline from session data snapshots.
// Pure logic — no framework dependencies beyond Foundation/CoreLocation.

import CoreLocation
import Foundation

// MARK: - VideoEventSequencer

struct VideoEventSequencer {
    // MARK: Internal

    static let framesPerSecond: Double = 30

    func buildTimeline(
        session: VideoSessionSnapshot,
        qsos: [VideoQSOSnapshot],
        spots: [VideoSpotSnapshot],
        parameterEvents: [VideoParameterChange],
        potaComments: [(spotter: String, comment: String, timestamp: Date)],
        recording: VideoRecordingSnapshot?,
        config: VideoExportConfig
    ) -> VideoTimeline {
        // ... implementation
    }
}
```

Implementation details:
- Collect all raw events into a unified `[(Date, VideoEvent)]` array
- Sort by timestamp
- Merge events within 1s into grouped moments
- Apply compression (highlight) or direct mapping (real-time) to compute `videoTime`
- Compute camera targets: center on operator, expand to include all visible QSOs
- Set `audioSourceOffset` by computing `realTime - recording.startedAt` when recording exists

**Grid→coordinate conversion:** When building `VideoSpotSnapshot`s from `SessionSpot`, convert `spotterGrid` to `CLLocationCoordinate2D` via `MaidenheadConverter.coordinate(from:)`. This happens in `VideoExportActor.loadSessionData(...)`, not in the sequencer — the sequencer receives pre-resolved coordinates.

**POTA comments source:** POTA notes are `POTASpotComment`s decoded from `LoggingSession.spotComments` (a JSON blob on the session model). Do NOT query `ActivityItem`. After fetching the `LoggingSession`, read `session.spotComments` and convert to the `(spotter: String, comment: String, timestamp: Date)` tuples the sequencer expects.

- [ ] **Step 4: Run tests to verify they pass**

Run: `xc test-unit`
Expected: PASS

- [ ] **Step 5: Write tests for highlight mode compression**

```swift
@Test("Highlight mode compresses large gaps")
func highlightCompression() {
    // QSOs at 60s and 600s (9-minute gap)
    let qsos = [
        makeQSO(offsetSeconds: 60),
        makeQSO(offsetSeconds: 600, callsign: "W1AW"),
    ]
    let timeline = sequencer.buildTimeline(
        session: makeSession(endOffset: 700),
        qsos: qsos, spots: [], parameterEvents: [],
        potaComments: [], recording: nil,
        config: VideoExportConfig(
            sessionId: UUID(), mode: .highlightReel,
            includeAudio: false, mapStyle: .standard
        )
    )

    // Second moment should be much earlier than 600s in video time
    let gap = timeline.moments[1].videoTime - timeline.moments[0].videoTime
    #expect(gap < 30) // compressed from 540s gap
    #expect(timeline.totalDuration < 60) // way shorter than 700s
}

@Test("Events within 1s merge into single moment")
func eventMerging() {
    let qso = makeQSO(offsetSeconds: 60)
    let spot = VideoSpotSnapshot(
        id: UUID(),
        timestamp: sessionStart.addingTimeInterval(60.5),
        spotter: "TI7W", snr: 23,
        coordinate: CLLocationCoordinate2D(latitude: 10, longitude: -84)
    )
    let timeline = sequencer.buildTimeline(
        session: makeSession(),
        qsos: [qso], spots: [spot], parameterEvents: [],
        potaComments: [], recording: nil,
        config: VideoExportConfig(
            sessionId: UUID(), mode: .fullReplay,
            includeAudio: false, mapStyle: .standard
        )
    )

    #expect(timeline.moments.count == 1)
    #expect(timeline.moments[0].events.count == 2)
}
```

@Test("Zero QSOs produces empty timeline")
func zeroQSOs() {
    let timeline = sequencer.buildTimeline(
        session: makeSession(endOffset: 3600),
        qsos: [], spots: [], parameterEvents: [],
        potaComments: [], recording: nil,
        config: VideoExportConfig(
            sessionId: UUID(), mode: .highlightReel,
            includeAudio: false, mapStyle: .standard
        )
    )
    #expect(timeline.moments.isEmpty)
    #expect(timeline.totalFrames == 0)
}

@Test("Single QSO produces one moment with minimum screen time")
func singleQSO() {
    let qsos = [makeQSO(offsetSeconds: 60)]
    let timeline = sequencer.buildTimeline(
        session: makeSession(endOffset: 120),
        qsos: qsos, spots: [], parameterEvents: [],
        potaComments: [], recording: nil,
        config: VideoExportConfig(
            sessionId: UUID(), mode: .highlightReel,
            includeAudio: false, mapStyle: .standard
        )
    )
    #expect(timeline.moments.count == 1)
    #expect(timeline.totalDuration >= 4) // minimum QSO screen time
}
```

- [ ] **Step 6: Make highlight/merge/edge-case tests pass**

Implement the remaining logic in the sequencer.

- [ ] **Step 7: Run all tests**

Run: `xc test-unit`
Expected: All PASS

- [ ] **Step 8: Commit**

```bash
git add CarrierWave/Services/VideoExport/VideoEventSequencer.swift
git add CarrierWaveTests/VideoExport/VideoEventSequencerTests.swift
git commit -m "feat(video-export): implement event sequencer with time compression"
```

---

## Task 3: Overlay Renderer (`VideoOverlayRenderer.swift`)

Core Graphics drawing helpers for toast cards, HUD, spot pulses, QSO markers, and geodesic arcs. Pure CG — no SwiftUI, no MapKit.

**Files:**
- Create: `CarrierWave/Services/VideoExport/VideoOverlayRenderer.swift`

- [ ] **Step 1: Create overlay renderer**

The renderer is a struct with static methods. Each method takes a `CGContext` (already set up at 1920x1080) and draws into it.

Key methods:

```swift
// Video Overlay Renderer
//
// Core Graphics drawing helpers for video export overlays.
// All methods draw into a provided CGContext at 1920x1080.

import CoreGraphics
import CoreLocation
import CoreText
import Foundation

// MARK: - VideoOverlayRenderer

struct VideoOverlayRenderer {
    static let videoWidth: CGFloat = 1920
    static let videoHeight: CGFloat = 1080

    // MARK: - Toast Cards

    /// Draw a toast card at the bottom of the frame.
    /// `slideProgress`: 0 = fully offscreen, 1 = fully visible
    static func drawToastCard(
        in context: CGContext,
        text: String,
        iconName: String,
        slideProgress: CGFloat
    ) { ... }

    // MARK: - HUD

    /// Draw the top HUD bar with session info.
    static func drawHUD(
        in context: CGContext,
        callsign: String,
        parkReference: String?,
        frequency: String,
        mode: String,
        elapsedTime: TimeInterval
    ) { ... }

    // MARK: - QSO Markers

    /// Draw a QSO marker pin at a screen point.
    static func drawQSOMarker(
        in context: CGContext,
        at point: CGPoint,
        opacity: CGFloat
    ) { ... }

    /// Draw a callsign label next to a marker.
    static func drawCallsignLabel(
        in context: CGContext,
        callsign: String,
        at point: CGPoint,
        opacity: CGFloat
    ) { ... }

    // MARK: - Geodesic Arcs

    /// Draw a geodesic arc between two screen points.
    static func drawGeodesicArc(
        in context: CGContext,
        from: CGPoint,
        to: CGPoint,
        controlHeight: CGFloat,
        opacity: CGFloat
    ) { ... }

    // MARK: - Spot Pulses

    /// Draw a spot pulse ripple effect at a screen point.
    /// `pulseProgress`: 0 = start, 1 = fully expanded and faded
    static func drawSpotPulse(
        in context: CGContext,
        at point: CGPoint,
        pulseProgress: CGFloat
    ) { ... }

    /// Draw a small residual dot after the pulse animation.
    static func drawSpotDot(
        in context: CGContext,
        at point: CGPoint,
        opacity: CGFloat
    ) { ... }
}
```

Implementation notes:
- Use `CTFont` with SF Pro for text rendering (create via `CTFontCreateWithName("SFProText-Regular", size, nil)`)
- Toast card: rounded rect path with `CGContext.addPath`, fill with black at 85% opacity, white text
- HUD: similar semi-transparent strip at top
- QSO marker: filled blue circle with white stroke
- Geodesic arc: quadratic Bezier curve (visual approximation — actual geodesic projection is handled by the compositor's coordinate mapping)
- Spot pulse: two concentric circle strokes with expanding radius and fading opacity
- Format elapsed time as `HH:MM:SS`

- [ ] **Step 2: Run SwiftLint**

Run: `swiftlint lint --path CarrierWave/Services/VideoExport/VideoOverlayRenderer.swift`
Expected: No warnings. If approaching 500 lines, split HUD/toast into a separate file.

- [ ] **Step 3: Commit**

```bash
git add CarrierWave/Services/VideoExport/VideoOverlayRenderer.swift
git commit -m "feat(video-export): add Core Graphics overlay renderer"
```

---

## Task 4: Frame Compositor (`VideoFrameCompositor.swift`)

Orchestrates map snapshots and overlay drawing into `CVPixelBuffer` frames. Handles MKMapSnapshotter (main thread hop), coordinate projection, and layer compositing.

**Files:**
- Create: `CarrierWave/Services/VideoExport/VideoFrameCompositor.swift`

- [ ] **Step 1: Create frame compositor**

```swift
// Video Frame Compositor
//
// Composites map snapshots with CG overlays into CVPixelBuffer frames.
// Handles MKMapSnapshotter (main thread) and coordinate projection.

import AVFoundation
import CoreGraphics
import CoreLocation
import MapKit
import UIKit

// MARK: - VideoFrameCompositor

final class VideoFrameCompositor {
    // MARK: Internal

    let videoSize = CGSize(width: 1920, height: 1080)
    let mapStyle: VideoExportConfig.MapStyle

    init(mapStyle: VideoExportConfig.MapStyle) {
        self.mapStyle = mapStyle
    }

    /// Cancel any in-flight map snapshot. Called from VideoExportActor.cancel().
    @MainActor
    func cancelCurrentSnapshot() {
        currentSnapshotter?.cancel()
        currentSnapshotter = nil
    }

    // MARK: Private

    @MainActor
    private var currentSnapshotter: MKMapSnapshotter?

    /// Render a single frame as a CVPixelBuffer.
    /// Called from VideoExportActor. Hops to @MainActor for map snapshots.
    func renderFrame(
        frameState: FrameRenderState,
        pixelBufferPool: CVPixelBufferPool
    ) async -> CVPixelBuffer? {
        // 1. Get or reuse map snapshot
        let mapImage: UIImage
        if let cached = frameState.cachedMapImage {
            mapImage = cached
        } else {
            guard let snapshot = await captureMapSnapshot(
                center: frameState.cameraCenter,
                span: frameState.cameraSpan,
                style: mapStyle
            ) else {
                return nil
            }
            mapImage = snapshot
        }

        // 2. Create pixel buffer from pool
        var pixelBuffer: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, pixelBufferPool, &pixelBuffer)
        guard let buffer = pixelBuffer else { return nil }

        // 3. Draw into CG context
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }

        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: Int(videoSize.width),
            height: Int(videoSize.height),
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return nil }

        // Layer 1: Map
        if let cgMap = mapImage.cgImage {
            context.draw(cgMap, in: CGRect(origin: .zero, size: videoSize))
        }

        // Layers 2-6: Overlays
        drawOverlays(in: context, state: frameState)

        return buffer
    }

    // MARK: Private

    @MainActor
    private func captureMapSnapshot(
        center: CLLocationCoordinate2D,
        span: MKCoordinateSpan,
        style: VideoExportConfig.MapStyle
    ) async -> UIImage? {
        let options = MKMapSnapshotter.Options()
        options.region = MKCoordinateRegion(center: center, span: span)
        options.size = CGSize(width: 1920, height: 1080)
        options.scale = 1.0

        switch style {
        case .standard:
            options.mapType = .standard
        case .satellite:
            options.mapType = .satellite
        case .hybrid:
            options.mapType = .hybrid
        }

        let snapshotter = MKMapSnapshotter(options: options)
        currentSnapshotter = snapshotter
        let result = try? await snapshotter.start().image
        currentSnapshotter = nil
        return result
    }

    private func drawOverlays(in context: CGContext, state: FrameRenderState) {
        // Draw arcs, markers, pulses, toast, HUD using VideoOverlayRenderer
        // Project coordinates to screen points using state.coordinateToPoint()
        // ...
    }
}
```

`FrameRenderState` (add to `VideoExportTypes.swift` or define here):
- Current visible QSOs with opacity (fade-in progress)
- Current visible spots with pulse progress
- Current toast card state (text, slide progress)
- Current HUD values (freq, mode, elapsed time)
- Camera center/span
- Cached map image (if camera hasn't moved)
- Coordinate-to-screen-point projection closure

- [ ] **Step 2: Add `FrameRenderState` to types**

Add `FrameRenderState` struct to `VideoExportTypes.swift` with all fields needed by the compositor.

- [ ] **Step 3: Run SwiftLint**

Run: `swiftlint lint --path CarrierWave/Services/VideoExport/VideoFrameCompositor.swift`
Expected: No warnings

- [ ] **Step 4: Commit**

```bash
git add CarrierWave/Services/VideoExport/VideoFrameCompositor.swift
git add CarrierWave/Services/VideoExport/VideoExportTypes.swift
git commit -m "feat(video-export): add frame compositor with map snapshot + CG overlays"
```

---

## Task 5: Video Writer (`VideoWriter.swift`)

AVAssetWriter wrapper. Accepts pixel buffers and optional audio samples, writes H.264/AAC MP4.

**Files:**
- Create: `CarrierWave/Services/VideoExport/VideoWriter.swift`

- [ ] **Step 1: Create video writer**

```swift
// Video Writer
//
// AVAssetWriter wrapper for writing H.264 video with optional AAC audio.

import AVFoundation
import Foundation

// MARK: - VideoWriter

final class VideoWriter {
    // MARK: Lifecycle

    init(outputURL: URL, includeAudio: Bool, sampleRate: Double = 12_000) throws {
        self.outputURL = outputURL
        writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)

        // Video input
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: 1920,
            AVVideoHeightKey: 1080,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 8_000_000,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
            ],
        ]
        videoInput = AVAssetWriterInput(
            mediaType: .video, outputSettings: videoSettings
        )
        videoInput.expectsMediaDataInRealTime = false

        let bufferAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: 1920,
            kCVPixelBufferHeightKey as String: 1080,
        ]
        adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: videoInput,
            sourcePixelBufferAttributes: bufferAttributes
        )
        writer.add(videoInput)

        // Audio input (optional)
        // sampleRate must match the source recording's actual rate
        // (read from AVAssetTrack.naturalTimeScale before creating writer)
        if includeAudio {
            let audioSettings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: sampleRate,
                AVNumberOfChannelsKey: 1,
                AVEncoderBitRateKey: 64_000,
            ]
            let input = AVAssetWriterInput(
                mediaType: .audio, outputSettings: audioSettings
            )
            input.expectsMediaDataInRealTime = false
            writer.add(input)
            audioInput = input
        }

        writer.startWriting()
        writer.startSession(atSourceTime: .zero)
    }

    // MARK: Internal

    var pixelBufferPool: CVPixelBufferPool? { adaptor.pixelBufferPool }

    func appendVideoFrame(_ buffer: CVPixelBuffer, at time: CMTime) -> Bool {
        guard videoInput.isReadyForMoreMediaData else { return false }
        return adaptor.append(buffer, withPresentationTime: time)
    }

    func appendAudioSamples(_ sampleBuffer: CMSampleBuffer) -> Bool {
        guard let input = audioInput, input.isReadyForMoreMediaData else {
            return false
        }
        return input.append(sampleBuffer)
    }

    func finish() async -> Bool {
        videoInput.markAsFinished()
        audioInput?.markAsFinished()
        await writer.finishWriting()
        return writer.status == .completed
    }

    func cancel() {
        writer.cancelWriting()
    }

    // MARK: Private

    private let outputURL: URL
    private let writer: AVAssetWriter
    private let videoInput: AVAssetWriterInput
    private let adaptor: AVAssetWriterInputPixelBufferAdaptor
    private var audioInput: AVAssetWriterInput?
}
```

- [ ] **Step 2: Run SwiftLint**

Expected: No warnings

- [ ] **Step 3: Commit**

```bash
git add CarrierWave/Services/VideoExport/VideoWriter.swift
git commit -m "feat(video-export): add AVAssetWriter wrapper"
```

---

## Task 6: Audio Mixer (`VideoAudioMixer.swift`)

Reads WebSDR recording via AVAssetReader, produces audio sample buffers aligned to the video timeline.

**Files:**
- Create: `CarrierWave/Services/VideoExport/VideoAudioMixer.swift`

- [ ] **Step 1: Create audio mixer**

```swift
// Video Audio Mixer
//
// Reads WebSDR audio recording and produces sample buffers
// aligned to the video timeline. Handles segment extraction
// for highlight mode and silence filling for gaps.

import AVFoundation
import Foundation

// MARK: - VideoAudioMixer

struct VideoAudioMixer {
    // MARK: Internal

    /// Prepare audio reader for the source recording file.
    /// Returns reader and the actual sample rate of the source file.
    static func makeReader(for fileURL: URL) throws -> (reader: AVAssetReader, sampleRate: Double) {
        let asset = AVURLAsset(url: fileURL)
        let reader = try AVAssetReader(asset: asset)

        guard let audioTrack = asset.tracks(withMediaType: .audio).first else {
            throw VideoAudioMixerError.noAudioTrack
        }

        // Read the actual sample rate from the source track
        let sampleRate = Double(audioTrack.naturalTimeScale)

        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
        ]

        let output = AVAssetReaderTrackOutput(
            track: audioTrack, outputSettings: outputSettings
        )
        reader.add(output)
        return (reader, sampleRate)
    }

    /// Generate a silent audio CMSampleBuffer for a given duration.
    static func silenceBuffer(
        duration: TimeInterval,
        sampleRate: Double,
        presentationTime: CMTime
    ) -> CMSampleBuffer? {
        let sampleCount = Int(duration * sampleRate)
        guard sampleCount > 0 else { return nil }

        // Allocate zeroed PCM data (16-bit mono = 2 bytes per sample)
        let dataSize = sampleCount * 2
        let data = UnsafeMutablePointer<Int16>.allocate(capacity: sampleCount)
        data.initialize(repeating: 0, count: sampleCount)

        // Wrap in CMBlockBuffer
        var blockBuffer: CMBlockBuffer?
        CMBlockBufferCreateWithMemoryBlock(
            allocator: nil, memoryBlock: data,
            blockLength: dataSize, blockAllocator: nil,
            customBlockSource: nil, offsetToData: 0,
            dataLength: dataSize, flags: 0, blockBufferOut: &blockBuffer
        )

        guard let block = blockBuffer else {
            data.deallocate()
            return nil
        }

        // Create CMSampleBuffer
        var formatDesc: CMAudioFormatDescription?
        var asbd = AudioStreamBasicDescription(
            mSampleRate: sampleRate, mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kLinearPCMFormatFlagIsSignedInteger,
            mBytesPerPacket: 2, mFramesPerPacket: 1,
            mBytesPerFrame: 2, mChannelsPerFrame: 1,
            mBitsPerChannel: 16, mReserved: 0
        )
        CMAudioFormatDescriptionCreate(
            allocator: nil, asbd: &asbd, layoutSize: 0,
            layout: nil, magicCookieSize: 0, magicCookie: nil,
            extensions: nil, formatDescriptionOut: &formatDesc
        )

        guard let fmt = formatDesc else { return nil }

        var sampleBuffer: CMSampleBuffer?
        CMAudioSampleBufferCreateReadyWithPacketDescriptions(
            allocator: nil, dataBuffer: block, formatDescription: fmt,
            sampleCount: sampleCount, presentationTimeStamp: presentationTime,
            packetDescriptions: nil, sampleBufferOut: &sampleBuffer
        )
        return sampleBuffer
    }

    /// Apply a linear crossfade ramp to the first/last N samples of a PCM buffer.
    /// `fadeInSamples`: number of samples to ramp up from 0 at the start.
    /// `fadeOutSamples`: number of samples to ramp down to 0 at the end.
    static func applyCrossfade(
        to data: UnsafeMutablePointer<Int16>,
        sampleCount: Int,
        fadeInSamples: Int,
        fadeOutSamples: Int
    ) {
        // Fade in: linear ramp 0→1 over fadeInSamples
        for idx in 0 ..< min(fadeInSamples, sampleCount) {
            let scale = Float(idx) / Float(fadeInSamples)
            data[idx] = Int16(Float(data[idx]) * scale)
        }
        // Fade out: linear ramp 1→0 over fadeOutSamples
        let fadeOutStart = max(sampleCount - fadeOutSamples, 0)
        for idx in fadeOutStart ..< sampleCount {
            let scale = Float(sampleCount - idx) / Float(fadeOutSamples)
            data[idx] = Int16(Float(data[idx]) * scale)
        }
    }

    /// For highlight mode: compute which source time ranges to read
    /// and where to insert silence, based on the VideoTimeline moments.
    static func buildAudioSegmentPlan(
        timeline: VideoTimeline,
        recordingStart: Date
    ) -> [AudioSegment] {
        var segments: [AudioSegment] = []
        var lastVideoTime: TimeInterval = 0

        for moment in timeline.moments {
            // Insert silence for any gap between last segment and this moment
            let gapDuration = moment.videoTime - lastVideoTime
            if gapDuration > 0.01 {
                segments.append(.silence(
                    duration: gapDuration, videoTime: lastVideoTime
                ))
            }

            // If this moment has audio, copy from source
            if let audioOffset = moment.audioSourceOffset {
                // Find how long this real-time segment lasts
                // (until next moment's videoTime or end of timeline)
                let segmentDuration = min(4.0, timeline.totalDuration - moment.videoTime)
                segments.append(.source(
                    sourceOffset: audioOffset,
                    duration: segmentDuration,
                    videoTime: moment.videoTime
                ))
                lastVideoTime = moment.videoTime + segmentDuration
            } else {
                lastVideoTime = moment.videoTime
            }
        }

        return segments
    }
}

// MARK: - AudioSegment

enum AudioSegment: Sendable {
    /// Copy audio from source at this offset for this duration
    case source(sourceOffset: TimeInterval, duration: TimeInterval, videoTime: TimeInterval)
    /// Insert silence for this duration
    case silence(duration: TimeInterval, videoTime: TimeInterval)
}

// MARK: - VideoAudioMixerError

enum VideoAudioMixerError: Error {
    case noAudioTrack
    case readerFailed(String)
}
```

- [ ] **Step 2: Run SwiftLint**

Expected: No warnings

- [ ] **Step 3: Commit**

```bash
git add CarrierWave/Services/VideoExport/VideoAudioMixer.swift
git commit -m "feat(video-export): add audio mixer for WebSDR recording sync"
```

---

## Task 7: Export Actor — Core (`VideoExportActor.swift`)

The orchestrator. Owns the pipeline, creates ModelContext, loads data into snapshots, coordinates the other components.

**Files:**
- Create: `CarrierWave/Services/VideoExport/VideoExportActor.swift`

- [ ] **Step 1: Create the actor**

```swift
// Video Export Actor
//
// Orchestrator for the video export pipeline.
// Creates ModelContext, loads data into Sendable snapshots,
// and coordinates sequencer → compositor → writer.

import CarrierWaveData
import Foundation
import SwiftData

// MARK: - VideoExportActor

actor VideoExportActor {
    // MARK: Internal

    /// Start the export process. Returns an AsyncStream of progress updates.
    /// The final progress update contains the result URL or error.
    func startExport(
        container: ModelContainer,
        config: VideoExportConfig
    ) -> AsyncStream<VideoExportProgress> {
        AsyncStream { continuation in
            exportTask = Task {
                await runExport(
                    container: container,
                    config: config,
                    continuation: continuation
                )
            }
        }
    }

    /// Cancel an in-progress export.
    /// Also cancels any in-flight MKMapSnapshotter via the compositor.
    func cancel() {
        isCancelled = true
        exportTask?.cancel()
        Task { @MainActor in
            compositor?.cancelCurrentSnapshot()
        }
    }

    private var compositor: VideoFrameCompositor?

    /// The result of the export (available after the stream completes).
    var result: VideoExportResult?

    // MARK: Private

    private var isCancelled = false
    private var exportTask: Task<Void, Never>?
}
```

Key responsibilities:
- `runExport(...)`: loads data via `loadSessionData(...)`, builds timeline via `VideoEventSequencer`, then delegates to the pipeline extension
- `loadSessionData(...)`: creates `ModelContext`, fetches `LoggingSession`, `QSO`s, `SessionSpot`s, `WebSDRRecording`, `POTASpotComment`s, converts to snapshots, discards context
- Filters QSOs using `QSOMode.isMetadata(_:)` to exclude metadata pseudo-modes

- [ ] **Step 2: Run SwiftLint**

Expected: No warnings

- [ ] **Step 3: Commit**

```bash
git add CarrierWave/Services/VideoExport/VideoExportActor.swift
git commit -m "feat(video-export): add export actor core with data loading"
```

---

## Task 8: Export Actor — Pipeline (`VideoExportActor+Pipeline.swift`)

Frame loop, snapshot coordination, writing frames.

**Files:**
- Create: `CarrierWave/Services/VideoExport/VideoExportActor+Pipeline.swift`

- [ ] **Step 1: Create pipeline extension**

```swift
// Video Export Actor — Pipeline
//
// Frame loop: iterates through timeline, renders frames via compositor,
// writes to video file via writer. Handles map snapshot caching and
// backpressure from AVAssetWriter.

import AVFoundation
import CoreGraphics
import CoreLocation
import Foundation
import MapKit

extension VideoExportActor {
    func runPipeline(
        timeline: VideoTimeline,
        config: VideoExportConfig,
        recording: VideoRecordingSnapshot?,
        continuation: AsyncStream<VideoExportProgress>.Continuation
    ) async -> VideoExportResult {
        // 1. Create temp output URL
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("video-export-\(UUID().uuidString).mp4")

        // 2. Set up writer
        guard let writer = try? VideoWriter(
            outputURL: outputURL,
            includeAudio: config.includeAudio && recording != nil
        ) else {
            return .failed("Failed to create video writer")
        }

        guard let pool = writer.pixelBufferPool else {
            return .failed("Failed to create pixel buffer pool")
        }

        // 3. Set up compositor
        let compositor = VideoFrameCompositor(mapStyle: config.mapStyle)

        // 4. Build frame states from timeline
        // 5. Frame loop with cancellation check
        // 6. Audio pass (if applicable)
        // 7. Finish writing

        let startTime = CFAbsoluteTimeGetCurrent()
        var framesWritten = 0
        let totalFrames = timeline.totalFrames

        // ... frame loop iterating at 30fps through totalDuration
        // Each iteration:
        //   - Check isCancelled
        //   - Build FrameRenderState for current video time
        //   - Render frame via compositor
        //   - Append to writer
        //   - Every 100 frames: yield progress with thumbnail

        // ... audio pass if needed

        guard await writer.finish() else {
            return .failed("Writer failed to finish")
        }

        return .success(outputURL)
    }
}
```

Key implementation details:
- Frame loop runs `for frameIndex in 0..<totalFrames`
- Current `videoTime = Double(frameIndex) / 30.0`
- Build `FrameRenderState` by scanning timeline moments up to current time
- Cache map snapshot: only re-snapshot when camera target/span changes
- Check `isCancelled` at top of each iteration
- Yield `VideoExportProgress` every 100 frames with `CGImage` thumbnail
- Audio: after video pass, run audio segment plan (real-time: sequential read, highlight: segment-based read with silence fills)
- Check `ProcessInfo.processInfo.thermalState` periodically, `Task.yield()` if `.serious`

- [ ] **Step 2: Run SwiftLint**

Expected: No warnings. Monitor file length — split if approaching 500 lines.

- [ ] **Step 3: Commit**

```bash
git add CarrierWave/Services/VideoExport/VideoExportActor+Pipeline.swift
git commit -m "feat(video-export): add pipeline frame loop and writer coordination"
```

---

## Task 9: Export Actor — Progress (`VideoExportActor+Progress.swift`)

Progress stream helpers and cancellation.

**Files:**
- Create: `CarrierWave/Services/VideoExport/VideoExportActor+Progress.swift`

- [ ] **Step 1: Create progress extension**

```swift
// Video Export Actor — Progress
//
// Progress reporting helpers and cancellation support.

import CoreGraphics
import Foundation

extension VideoExportActor {
    /// Create a progress update, optionally with a thumbnail.
    func makeProgress(
        framesCompleted: Int,
        totalFrames: Int,
        startTime: CFAbsoluteTime,
        thumbnail: CGImage? = nil
    ) -> VideoExportProgress {
        let elapsed = CFAbsoluteTimeGetCurrent() - startTime
        let rate = Double(framesCompleted) / max(elapsed, 0.001)
        let remaining = Double(totalFrames - framesCompleted) / max(rate, 0.001)

        return VideoExportProgress(
            framesCompleted: framesCompleted,
            totalFrames: totalFrames,
            estimatedSecondsRemaining: remaining,
            latestThumbnail: thumbnail
        )
    }

    /// Extract a CGImage thumbnail from a CVPixelBuffer.
    func thumbnailFromBuffer(_ buffer: CVPixelBuffer) -> CGImage? {
        let ciImage = CIImage(cvPixelBuffer: buffer)
        let ciContext = CIContext()
        return ciContext.createCGImage(ciImage, from: ciImage.extent)
    }

    /// Check thermal state and yield if needed.
    /// Returns true if export should continue, false if cancelled during cooldown.
    func checkThermalState() async -> Bool {
        let state = ProcessInfo.processInfo.thermalState
        if state == .critical || state == .serious {
            // Pause to let the device cool, loop until thermal state improves
            while ProcessInfo.processInfo.thermalState == .critical
                || ProcessInfo.processInfo.thermalState == .serious
            {
                try? await Task.sleep(for: .seconds(2))
                if isCancelled { return false }
            }
        }
        return !isCancelled
    }
}
```

- [ ] **Step 2: Run SwiftLint**

Expected: No warnings

- [ ] **Step 3: Build verification gate — all services must compile together**

Run: `xc build`
Expected: Clean build. All 9 service files (VideoExportTypes, VideoEventSequencer, VideoOverlayRenderer, VideoFrameCompositor, VideoWriter, VideoAudioMixer, VideoExportActor, +Pipeline, +Progress) compile as a unit.

- [ ] **Step 4: Commit**

```bash
git add CarrierWave/Services/VideoExport/VideoExportActor+Progress.swift
git commit -m "feat(video-export): add progress reporting and thermal monitoring"
```

---

## Task 10: Export UI — Configuration Sheet (`VideoExportSheet.swift`)

SwiftUI sheet with mode toggle, audio toggle, map style picker, and export button. Transitions to progress view during rendering.

**Files:**
- Create: `CarrierWave/Views/Sessions/VideoExportSheet.swift`

- [ ] **Step 1: Create the sheet view**

```swift
// Video Export Sheet
//
// Configuration and progress UI for video export.
// Shows mode selection, audio toggle, map style picker.
// Transitions to progress view during rendering.

import CarrierWaveData
import SwiftData
import SwiftUI

// MARK: - VideoExportSheet

struct VideoExportSheet: View {
    // MARK: Internal

    let session: LoggingSession
    let hasRecording: Bool

    @Environment(\.dismiss) var dismiss
    @Environment(\.modelContext) var modelContext

    var body: some View {
        NavigationStack {
            Group {
                if isExporting {
                    progressContent
                } else {
                    configContent
                }
            }
            .navigationTitle("Export Video")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        if isExporting {
                            cancelExport()
                        } else {
                            dismiss()
                        }
                    }
                }
            }
        }
    }

    // MARK: Private

    @State private var mode: VideoExportConfig.Mode = .highlightReel
    @State private var includeAudio = true
    @State private var mapStyle: VideoExportConfig.MapStyle = .standard
    @State private var isExporting = false
    @State private var progress: VideoExportProgress?
    @State private var thumbnailImage: UIImage?
    @State private var exportResult: VideoExportResult?
    @State private var showShareSheet = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var exportedFileURL: URL?
    @State private var exportActor: VideoExportActor?
}
```

Config content: `Form` with sections for mode (Picker), audio (Toggle, conditional on `hasRecording`), map style (Picker), and Export button.

Progress content: see Task 11.

- [ ] **Step 2: Run SwiftLint**

Expected: No warnings

- [ ] **Step 3: Commit**

```bash
git add CarrierWave/Views/Sessions/VideoExportSheet.swift
git commit -m "feat(video-export): add export configuration sheet UI"
```

---

## Task 11: Export UI — Progress View (`VideoExportSheet+Progress.swift`)

Progress bar, frame count, estimated time, preview thumbnail, cancel button.

**Files:**
- Create: `CarrierWave/Views/Sessions/VideoExportSheet+Progress.swift`

- [ ] **Step 1: Create progress view extension**

```swift
// Video Export Sheet — Progress
//
// Progress view shown during video rendering.

import SwiftUI

extension VideoExportSheet {
    var progressContent: some View {
        VStack(spacing: 24) {
            Spacer()

            // Preview thumbnail
            if let img = thumbnailImage {
                Image(uiImage: img)
                    .resizable()
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal, 32)
            } else {
                RoundedRectangle(cornerRadius: 12)
                    .fill(.quaternary)
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .overlay {
                        ProgressView()
                    }
                    .padding(.horizontal, 32)
            }

            // Progress info
            if let prog = progress {
                VStack(spacing: 8) {
                    ProgressView(
                        value: Double(prog.framesCompleted),
                        total: Double(max(prog.totalFrames, 1))
                    )

                    HStack {
                        Text("Frame \(prog.framesCompleted) / \(prog.totalFrames)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        if let remaining = prog.estimatedSecondsRemaining {
                            Text(formatRemaining(remaining))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.horizontal, 32)
            }

            Spacer()
        }
    }

    func formatRemaining(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        if mins > 0 {
            return "\(mins)m \(secs)s remaining"
        }
        return "\(secs)s remaining"
    }
}
```

- [ ] **Step 2: Run SwiftLint**

Expected: No warnings

- [ ] **Step 3: Commit**

```bash
git add CarrierWave/Views/Sessions/VideoExportSheet+Progress.swift
git commit -m "feat(video-export): add export progress view with thumbnail preview"
```

---

## Task 12: Export Button & Session Detail Integration

Add the "Export Video" button to session detail and wire up the sheet presentation.

**Files:**
- Create: `CarrierWave/Views/Sessions/VideoExportButton.swift`
- Modify: `CarrierWave/Views/Sessions/SessionDetailView+Components.swift:~275-281` — add export button near Session Replay

- [ ] **Step 1: Create export button view**

```swift
// Video Export Button
//
// Entry point for video export on the session detail screen.
// Only enabled for sessions with at least 1 QSO with coordinates.

import CarrierWaveData
import SwiftUI

// MARK: - VideoExportButton

struct VideoExportButton: View {
    let session: LoggingSession
    let hasQSOsWithCoordinates: Bool
    let hasRecording: Bool

    @State private var showExportSheet = false

    var body: some View {
        Button {
            showExportSheet = true
        } label: {
            Label("Export Video", systemImage: "film")
        }
        .disabled(!hasQSOsWithCoordinates)
        .sheet(isPresented: $showExportSheet) {
            VideoExportSheet(
                session: session,
                hasRecording: hasRecording
            )
        }
    }
}
```

- [ ] **Step 2: Add button to SessionDetailView+Components.swift**

Find the "Session Replay" NavigationLink (around line 276) and add the export button below it:

```swift
// After the Session Replay NavigationLink:
VideoExportButton(
    session: session,
    hasQSOsWithCoordinates: hasQSOsWithCoordinates,
    hasRecording: hasRecording
)
```

The `hasQSOsWithCoordinates` and `hasRecording` booleans need to be computed or passed in. Check how the session detail view already loads QSO data and WebSDR recordings to determine the right approach — avoid adding new fetches if the data is already available.

**File length warning:** `SessionDetailView+Components.swift` is ~430 lines. Before adding the export button, check `wc -l` — if the addition would push it over 500 lines, split an existing section (e.g., the map/replay section) into a new `SessionDetailView+MapReplay.swift` extension file first.

- [ ] **Step 3: Run SwiftLint and build**

Run: `xc quality`
Expected: Clean build, no lint warnings

- [ ] **Step 4: Commit**

```bash
git add CarrierWave/Views/Sessions/VideoExportButton.swift
git add CarrierWave/Views/Sessions/SessionDetailView+Components.swift
git commit -m "feat(video-export): add export button to session detail"
```

---

## Task 13: Wire Up Export Flow

Connect the export sheet to the actor. Start export on button tap, observe progress stream, present share sheet on completion.

**Files:**
- Modify: `CarrierWave/Views/Sessions/VideoExportSheet.swift` — add export logic

- [ ] **Step 1: Add export trigger and progress observation**

Add to `VideoExportSheet`:

```swift
private func startExport() {
    let actor = VideoExportActor()
    exportActor = actor
    isExporting = true

    let config = VideoExportConfig(
        sessionId: session.id,
        mode: mode,
        includeAudio: includeAudio && hasRecording,
        mapStyle: mapStyle
    )

    Task {
        let stream = await actor.startExport(
            container: modelContext.container,
            config: config
        )

        for await prog in stream {
            progress = prog
            if let thumb = prog.latestThumbnail {
                thumbnailImage = UIImage(cgImage: thumb)
            }
        }

        // Export complete
        if let result = await actor.result {
            handleResult(result)
        }
    }
}

private func handleResult(_ result: VideoExportResult) {
    switch result {
    case let .success(url):
        exportedFileURL = url
        showShareSheet = true
    case .cancelled:
        isExporting = false
    case let .failed(message):
        errorMessage = message
        showError = true
        isExporting = false
    }
}

private func cancelExport() {
    Task {
        await exportActor?.cancel()
    }
    isExporting = false
}
```

Add share sheet and error alert modifiers to the view body.

- [ ] **Step 2: Run build**

Run: `xc build`
Expected: Clean build

- [ ] **Step 3: Commit**

```bash
git add CarrierWave/Views/Sessions/VideoExportSheet.swift
git commit -m "feat(video-export): wire up export flow with progress observation"
```

---

## Task 14: Update FILE_INDEX.md

Add all new files to the file index.

**Files:**
- Modify: `docs/FILE_INDEX.md`

- [ ] **Step 1: Add entries**

Add a new section for `Services/VideoExport/` and update `Views/Sessions/` entries:

```markdown
## Services - Video Export (`CarrierWave/Services/VideoExport/`)

| File | Description |
|------|-------------|
| `VideoExportActor.swift` | Orchestrator: pipeline setup, data loading, public API |
| `VideoExportActor+Pipeline.swift` | Frame loop, map snapshot coordination, writer feeding |
| `VideoExportActor+Progress.swift` | Progress stream, thermal monitoring, cancellation |
| `VideoEventSequencer.swift` | Builds VideoTimeline from session data with time compression |
| `VideoFrameCompositor.swift` | MKMapSnapshotter + Core Graphics layer compositing |
| `VideoWriter.swift` | AVAssetWriter wrapper for H.264 + AAC muxing |
| `VideoAudioMixer.swift` | WebSDR audio segment extraction and silence filling |
| `VideoOverlayRenderer.swift` | Core Graphics drawing for toast cards, HUD, markers, pulses |
| `VideoExportTypes.swift` | Sendable value types: VideoMoment, VideoEvent, snapshots, config |
```

And in the Sessions views section:
```markdown
| `VideoExportButton.swift` | Export Video entry point on session detail |
| `VideoExportSheet.swift` | Export configuration and progress UI |
| `VideoExportSheet+Progress.swift` | Progress view with thumbnail preview |
```

- [ ] **Step 2: Commit**

```bash
git add docs/FILE_INDEX.md
git commit -m "docs: add video export files to FILE_INDEX.md"
```

---

## Task 15: Update CHANGELOG.md

- [ ] **Step 1: Add entry under `[Unreleased]`**

```markdown
### Added
- Export session replay as YouTube-ready 1080p MP4 video with map, WebSDR audio, and event toast cards
```

- [ ] **Step 2: Commit**

```bash
git add CHANGELOG.md
git commit -m "docs: add video export to changelog"
```

---

## Implementation Notes

### Build Verification Points

After Tasks 1-9 (services layer): run `xc build` to verify all services compile together. The types, sequencer, compositor, writer, mixer, and actor should compile as a unit even though they aren't wired to UI yet.

After Tasks 10-13 (UI layer): run `xc quality` (format + lint + build) to verify full integration.

### Testing Strategy

- **Unit tests** (Task 2): `VideoEventSequencer` is pure logic and fully testable. Test both modes, edge cases (zero QSOs, single QSO, rapid-fire events, very long gaps).
- **Integration testing**: Manual on-device testing required. Export a video from a real session with WebSDR recording and verify:
  - Map renders correctly with arcs and markers
  - Toast cards appear at correct times
  - Audio syncs with events in real-time mode
  - Highlight mode produces reasonable compression
  - Share sheet presents the MP4 successfully
  - Video plays in Photos and YouTube upload works

### Files Created (12 new)

| File | Lines (est.) |
|------|-------------|
| `VideoExportTypes.swift` | ~150 |
| `VideoEventSequencer.swift` | ~250 |
| `VideoOverlayRenderer.swift` | ~300 |
| `VideoFrameCompositor.swift` | ~200 |
| `VideoWriter.swift` | ~100 |
| `VideoAudioMixer.swift` | ~150 |
| `VideoExportActor.swift` | ~150 |
| `VideoExportActor+Pipeline.swift` | ~250 |
| `VideoExportActor+Progress.swift` | ~60 |
| `VideoExportButton.swift` | ~40 |
| `VideoExportSheet.swift` | ~150 |
| `VideoExportSheet+Progress.swift` | ~80 |

### Files Modified (2)

- `SessionDetailView+Components.swift` — add `VideoExportButton`
- `docs/FILE_INDEX.md` — add new file entries
