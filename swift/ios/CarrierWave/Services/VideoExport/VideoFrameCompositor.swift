// Video Frame Compositor
//
// Composites map snapshots with Core Graphics overlays into CVPixelBuffer frames.

import AVFoundation
import CoreGraphics
import CoreLocation
import MapKit
import UIKit

// MARK: - FrameRenderResult

/// Result of rendering a single frame.
nonisolated struct FrameRenderResult {
    let buffer: CVPixelBuffer
    let mapImage: UIImage?
}

// MARK: - VideoFrameCompositor

nonisolated final class VideoFrameCompositor: @unchecked Sendable {
    // MARK: Lifecycle

    // MARK: - Init

    init(config: VideoExportConfig) {
        mapStyle = config.mapStyle
        layers = config.layers
        hudDensity = config.hudDensity
        palette = config.palette
    }

    // MARK: Internal

    let videoSize = CGSize(width: 1_920, height: 1_080)
    let mapStyle: VideoExportConfig.MapStyle
    let layers: LayerVisibility
    let hudDensity: HUDDensity
    let palette: VideoThemePalette

    /// Timing from last renderFrame call (ms). Read by pipeline for diagnostics.
    var lastSnapshotMs: Double = 0
    var lastDrawMs: Double = 0
    var lastBaseMs: Double = 0
    var lastDynMs: Double = 0
    var lastUsedCache: Bool = false

    // MARK: - Cancellation

    @MainActor func cancelCurrentSnapshot() {
        currentSnapshotter?.cancel()
        currentSnapshotter = nil
    }

    // MARK: - Render

    /// Returns a FrameRenderResult — caller should cache mapImage for subsequent frames.
    func renderFrame(
        frameState: FrameRenderState, pixelBufferPool: CVPixelBufferPool
    ) async -> FrameRenderResult? {
        // Get or reuse map snapshot
        let mapImage: UIImage?
        var snapshotMs: Double = 0
        if let cached = frameState.cachedMapImage {
            mapImage = cached
        } else {
            let snapStart = CFAbsoluteTimeGetCurrent()
            let snap = await captureAndStoreSnapshot(
                center: frameState.cameraCenter,
                span: frameState.cameraSpan,
                style: mapStyle
            )
            mapImage = snap
            snapshotMs = (CFAbsoluteTimeGetCurrent() - snapStart) * 1_000
            invalidateOverlayCache()
        }

        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferPoolCreatePixelBuffer(nil, pixelBufferPool, &pixelBuffer)
        guard status == kCVReturnSuccess, let buffer = pixelBuffer else {
            return nil
        }

        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }

        guard let context = makeBGRAContext(for: buffer) else {
            return nil
        }

        let drawStart = CFAbsoluteTimeGetCurrent()
        ensureProjectedPoints(state: frameState)
        let usedCache = renderBaseFrame(
            context: context, buffer: buffer,
            mapImage: mapImage, frameState: frameState
        )
        let baseMs = (CFAbsoluteTimeGetCurrent() - drawStart) * 1_000
        let dynStart = CFAbsoluteTimeGetCurrent()
        drawDynamicLayers(in: context, state: frameState)
        let dynMs = (CFAbsoluteTimeGetCurrent() - dynStart) * 1_000

        lastBaseMs = baseMs
        lastDynMs = dynMs
        lastUsedCache = usedCache
        lastSnapshotMs = snapshotMs
        lastDrawMs = baseMs + dynMs

        return FrameRenderResult(buffer: buffer, mapImage: mapImage)
    }

    func invalidateOverlayCache() {
        projectedPoints.removeAll()
        projectedMyPoint = nil
        cachedBaseFrame = nil
        cachedBaseQSOCount = -1
    }

    // MARK: Private

    @MainActor private var currentSnapshotter: MKMapSnapshotter?
    private var cachedSnapshot: MKMapSnapshotter.Snapshot?

    /// Projected screen points keyed by QSO id, valid for current snapshot.
    private var projectedPoints: [UUID: CGPoint] = [:]
    private var projectedMyPoint: CGPoint?

    /// Cached raw pixels of map + static overlays (arcs, markers, cards for opaque QSOs).
    /// Memcpy'd into pixel buffer when nothing visual changed — avoids full CG redraw.
    private var cachedBaseFrame: Data?
    private var cachedBaseQSOCount: Int = -1

    /// Cached HUD strip as CGImage. Re-rendered only when displayed values change.
    private var cachedHUDImage: CGImage?
    private var cachedHUDKey: String = ""

    /// Either restores the cached base frame or draws map + arcs + markers + cards.
    /// Returns true if the cache was used.
    private func renderBaseFrame(
        context: CGContext, buffer: CVPixelBuffer,
        mapImage: UIImage?, frameState: FrameRenderState
    ) -> Bool {
        let opaqueCount = frameState.visibleQSOs.count(where: { $0.opacity >= 1.0 })
        let usedCache = cachedBaseFrame != nil && opaqueCount == cachedBaseQSOCount
        if usedCache {
            restoreCachedFrame(cachedBaseFrame!, into: buffer) // swiftlint:disable:this force_unwrapping
            return true
        }
        drawMapBackground(in: context, mapImage: mapImage)
        if layers.showArcs {
            drawArcs(in: context, state: frameState)
        }
        drawQSOMarkersAndCards(in: context, state: frameState)
        cacheCurrentFrame(from: buffer)
        cachedBaseQSOCount = opaqueCount
        return false
    }
}

// MARK: - Map Snapshot

nonisolated private extension VideoFrameCompositor {
    /// Capture snapshot on MainActor, store it internally, return just the image.
    @MainActor func captureAndStoreSnapshot(
        center: CLLocationCoordinate2D,
        span: MKCoordinateSpan,
        style: VideoExportConfig.MapStyle
    ) async -> UIImage? {
        let snap = await captureMapSnapshotInternal(center: center, span: span, style: style)
        cachedSnapshot = snap
        return snap?.image
    }

    @MainActor private func captureMapSnapshotInternal(
        center: CLLocationCoordinate2D,
        span: MKCoordinateSpan,
        style: VideoExportConfig.MapStyle
    ) async -> MKMapSnapshotter.Snapshot? {
        let options = MKMapSnapshotter.Options()
        options.region = MKCoordinateRegion(center: center, span: span)
        options.size = CGSize(width: 1_920, height: 1_080)
        options.scale = 1.0
        options.mapType = mapType(for: style)

        let snapshotter = MKMapSnapshotter(options: options)
        currentSnapshotter = snapshotter
        let snapshot = try? await snapshotter.start()
        currentSnapshotter = nil
        return snapshot
    }

    func mapType(for style: VideoExportConfig.MapStyle) -> MKMapType {
        switch style {
        case .standard:
            .standard
        case .satellite:
            .satellite
        case .hybrid:
            .hybrid
        }
    }
}

// MARK: - CGContext Factory

nonisolated private extension VideoFrameCompositor {
    func makeBGRAContext(for buffer: CVPixelBuffer) -> CGContext? {
        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        guard let baseAddress = CVPixelBufferGetBaseAddress(buffer) else {
            return nil
        }
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo.byteOrder32Little.rawValue |
            CGImageAlphaInfo.premultipliedFirst.rawValue
        return CGContext(
            data: baseAddress,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        )
    }
}

// MARK: - Map Background

nonisolated private extension VideoFrameCompositor {
    func drawMapBackground(in context: CGContext, mapImage: UIImage?) {
        if let image = mapImage, let cgImage = image.cgImage {
            context.draw(cgImage, in: CGRect(origin: .zero, size: videoSize))
        } else {
            context.setFillColor(palette.mapFallback)
            context.fill(CGRect(origin: .zero, size: videoSize))
        }
    }
}

// MARK: - Frame Caching

nonisolated private extension VideoFrameCompositor {
    func drawDynamicLayers(in context: CGContext, state: FrameRenderState) {
        if state.visibleQSOs.contains(where: { $0.opacity < 1.0 }) {
            drawFadingQSOs(in: context, state: state)
        }
        if layers.showSpots, !state.visibleSpots.isEmpty {
            drawSpots(in: context, state: state)
        }
        if layers.showLoggerOverlay, let overlay = state.loggerOverlay {
            VideoOverlayRenderer.drawLoggerOverlay(in: context, state: overlay, palette: palette)
        }
        if layers.showToasts, let toast = state.toastCard {
            VideoOverlayRenderer.drawToastCard(in: context, toast: toast, palette: palette)
        }
        if hudDensity != .off {
            drawHUD(in: context, state: state)
        }
    }

    func cacheCurrentFrame(from buffer: CVPixelBuffer) {
        let height = CVPixelBufferGetHeight(buffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        guard let base = CVPixelBufferGetBaseAddress(buffer) else {
            return
        }
        cachedBaseFrame = Data(bytes: base, count: height * bytesPerRow)
    }

    func restoreCachedFrame(_ data: Data, into buffer: CVPixelBuffer) {
        guard let base = CVPixelBufferGetBaseAddress(buffer) else {
            return
        }
        let size = min(data.count, CVPixelBufferGetHeight(buffer) * CVPixelBufferGetBytesPerRow(buffer))
        data.withUnsafeBytes { ptr in
            if let src = ptr.baseAddress {
                memcpy(base, src, size)
            }
        }
    }
}

// MARK: - Overlay Drawing

nonisolated private extension VideoFrameCompositor {
    func drawArcs(in context: CGContext, state: FrameRenderState) {
        guard let myPt = projectedMyPoint else {
            return
        }
        for (qso, opacity) in state.visibleQSOs where opacity >= 1.0 {
            guard let pt = projectedPoints[qso.id] else {
                continue
            }
            VideoOverlayRenderer.drawGeodesicArc(
                in: context, shape: arcShape(from: myPt, to: pt),
                opacity: opacity, palette: palette
            )
        }
    }

    func arcShape(from myPt: CGPoint, to pt: CGPoint) -> GeodesicArcShape {
        let dx = pt.x - myPt.x
        let dy = pt.y - myPt.y
        let controlHeight = min(sqrt(dx * dx + dy * dy) * 0.35, 200)
        return GeodesicArcShape(start: myPt, end: pt, controlHeight: controlHeight)
    }

    /// Draws markers for all QSOs, but cards only for the most recent ones.
    func drawQSOMarkersAndCards(in context: CGContext, state: FrameRenderState) {
        let cardLimit = layers.showCallsignCards ? max(0, layers.recentQSOCardCount) : 0
        let cardCutoff = max(0, state.visibleQSOs.count - cardLimit)
        for (idx, entry) in state.visibleQSOs.enumerated() where entry.opacity >= 1.0 {
            guard let pt = projectedPoints[entry.qso.id] else {
                continue
            }
            if layers.showQSOMarkers {
                VideoOverlayRenderer.drawQSOMarker(in: context, at: pt, opacity: 1.0, palette: palette)
            }
            if cardLimit > 0, idx >= cardCutoff {
                VideoOverlayRenderer.drawCallsignCard(
                    in: context, qso: entry.qso, at: pt, opacity: 1.0, palette: palette
                )
            }
        }
    }

    func drawFadingQSOs(in context: CGContext, state: FrameRenderState) {
        guard let myPt = projectedMyPoint else {
            return
        }
        for (qso, opacity) in state.visibleQSOs where opacity < 1.0 {
            guard let pt = projectedPoints[qso.id] else {
                continue
            }
            if layers.showArcs {
                VideoOverlayRenderer.drawGeodesicArc(
                    in: context, shape: arcShape(from: myPt, to: pt),
                    opacity: opacity, palette: palette
                )
            }
            if layers.showQSOMarkers {
                VideoOverlayRenderer.drawQSOMarker(in: context, at: pt, opacity: opacity, palette: palette)
            }
            if layers.showCallsignCards {
                VideoOverlayRenderer.drawCallsignCard(
                    in: context, qso: qso, at: pt, opacity: opacity, palette: palette
                )
            }
        }
    }

    func drawHUD(in context: CGContext, state: FrameRenderState) {
        let height = VideoOverlayRenderer.hudHeight(for: hudDensity)
        guard height > 0 else {
            return
        }
        let hudState = VideoHUDState(
            callsign: state.hudCallsign,
            parkReference: state.hudParkReference,
            frequency: state.hudFrequency,
            mode: state.hudMode,
            elapsedTime: state.hudElapsedTime,
            parkName: state.hudParkName,
            equipmentLine: state.hudEquipmentLine,
            qsoCount: state.hudQSOCount,
            qsoRate: state.hudQSORate
        )
        // Cache key: values that change between frames (time truncated to seconds, QSO count)
        let key = "\(Int(state.hudElapsedTime))-\(state.hudQSOCount)-\(state.hudFrequency)"
        if key == cachedHUDKey, let cached = cachedHUDImage {
            let hudRect = CGRect(x: 0, y: 0, width: videoSize.width, height: height)
            context.draw(cached, in: hudRect)
            return
        }
        // Render HUD into a small offscreen context, cache, and draw
        let hudImage = renderHUDImage(state: hudState, height: height)
        cachedHUDImage = hudImage
        cachedHUDKey = key
        if let img = hudImage {
            let hudRect = CGRect(x: 0, y: 0, width: videoSize.width, height: height)
            context.draw(img, in: hudRect)
        }
    }

    func renderHUDImage(state: VideoHUDState, height: CGFloat) -> CGImage? {
        let width = Int(videoSize.width)
        let pixelHeight = Int(height)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo.byteOrder32Little.rawValue |
            CGImageAlphaInfo.premultipliedFirst.rawValue
        guard let ctx = CGContext(
            data: nil, width: width, height: pixelHeight,
            bitsPerComponent: 8, bytesPerRow: width * 4,
            space: colorSpace, bitmapInfo: bitmapInfo
        ) else {
            return nil
        }
        VideoOverlayRenderer.drawHUD(in: ctx, state: state, palette: palette, density: hudDensity)
        return ctx.makeImage()
    }

    func drawSpots(in context: CGContext, state: FrameRenderState) {
        for (spot, pulseProgress) in state.visibleSpots {
            guard let coord = spot.coordinate,
                  let point = projectViaSnapshot(coord, snapshot: cachedSnapshot)
            else {
                continue
            }
            VideoOverlayRenderer.drawSpotPulse(
                in: context, at: point, pulseProgress: pulseProgress, palette: palette
            )
        }
    }

    /// Project a coordinate to CG context point using the snapshot's built-in projection.
    func projectViaSnapshot(
        _ coord: CLLocationCoordinate2D,
        snapshot: MKMapSnapshotter.Snapshot?
    ) -> CGPoint? {
        guard let snapshot else {
            return nil
        }
        let pt = snapshot.point(for: coord)
        return CGPoint(x: pt.x, y: 1_080 - pt.y)
    }

    /// Build projected screen points cache for all visible QSOs.
    func ensureProjectedPoints(state: FrameRenderState) {
        if let myCoord = state.myCoordinate, projectedMyPoint == nil {
            projectedMyPoint = projectViaSnapshot(myCoord, snapshot: cachedSnapshot)
        }
        for (qso, _) in state.visibleQSOs where projectedPoints[qso.id] == nil {
            if let coord = qso.coordinate {
                projectedPoints[qso.id] = projectViaSnapshot(coord, snapshot: cachedSnapshot)
            }
        }
    }

    func projectCoordinate(_ coordinate: CLLocationCoordinate2D, in region: MKCoordinateRegion) -> CGPoint? {
        guard CLLocationCoordinate2DIsValid(coordinate) else {
            return nil
        }
        let mapPoint = MKMapPoint(coordinate)
        let mapRect = MKMapRect(region: region)
        let xFraction = (mapPoint.x - mapRect.origin.x) / mapRect.size.width
        let yFraction = (mapPoint.y - mapRect.origin.y) / mapRect.size.height
        // CG origin is bottom-left, so invert Y for correct overlay placement
        return CGPoint(x: xFraction * 1_920, y: (1 - yFraction) * 1_080)
    }
}

// MARK: - MKMapRect + MKCoordinateRegion

nonisolated private extension MKMapRect {
    init(region: MKCoordinateRegion) {
        let topLeft = CLLocationCoordinate2D(
            latitude: region.center.latitude + region.span.latitudeDelta / 2,
            longitude: region.center.longitude - region.span.longitudeDelta / 2
        )
        let bottomRight = CLLocationCoordinate2D(
            latitude: region.center.latitude - region.span.latitudeDelta / 2,
            longitude: region.center.longitude + region.span.longitudeDelta / 2
        )
        let topLeftPoint = MKMapPoint(topLeft)
        let bottomRightPoint = MKMapPoint(bottomRight)
        self.init(
            x: topLeftPoint.x,
            y: topLeftPoint.y,
            width: bottomRightPoint.x - topLeftPoint.x,
            height: bottomRightPoint.y - topLeftPoint.y
        )
    }
}
