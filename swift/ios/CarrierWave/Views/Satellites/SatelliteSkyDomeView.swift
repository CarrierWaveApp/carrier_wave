import CoreMotion
import SwiftUI

// MARK: - SatelliteSkyDomeView

/// Attitude-driven sky view: raise the phone and pan it around to see the
/// ham satellites at their true az/el. The selected satellite is
/// highlighted with lock-on and polarization guidance; tilting the phone
/// back down returns to the map.
struct SatelliteSkyDomeView: View {
    // MARK: Internal

    let model: SatelliteTrackerModel
    let motion: AntennaMotionService
    let onClose: () -> Void

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.02, green: 0.03, blue: 0.10), Color(red: 0.05, green: 0.09, blue: 0.22)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            if arEnabled, camera.isAuthorized {
                PointingCameraPreview(session: camera.session)
                    .ignoresSafeArea()
                Color.black.opacity(0.25)
                    .ignoresSafeArea()
            }
            if let matrix = motion.rotationMatrix {
                sky(matrix: matrix)
            } else {
                ProgressView()
            }
            overlayChrome
        }
        .onChange(of: isOnTarget) { _, nowOnTarget in
            if nowOnTarget, !wasOnTarget {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            }
            wasOnTarget = nowOnTarget
        }
        .onChange(of: hoveredSky?.position.noradID) { _, noradID in
            refreshHoverTrack(for: noradID)
        }
        .onChange(of: arEnabled) { _, enabled in
            if enabled {
                Task {
                    await camera.start()
                    cameraDenied = !camera.isAuthorized
                }
            } else {
                camera.stop()
                cameraDenied = false
            }
        }
        .task {
            if arEnabled {
                await camera.start()
                cameraDenied = !camera.isAuthorized
            }
        }
        .onDisappear {
            camera.stop()
        }
    }

    // MARK: Private

    private static let lockDeg = 5.0
    /// Aim within this many degrees of a satellite to "hover" it.
    private static let hoverDeg = 7.0

    @State private var wasOnTarget = false
    @State private var camera = PointingCameraController()
    @State private var cameraDenied = false
    /// Camera passthrough behind the sky dome (persisted).
    @AppStorage("satelliteSkyDomeAROverlay") private var arEnabled = false
    @State private var hoverTrack: [SatellitePosition] = []
    @State private var hoverTrackID: Int?

    private var interpolationElapsed: TimeInterval {
        Date().timeIntervalSince(model.positionsSyncedAt)
    }

    private var selectedSky: SkySighting? {
        guard let position = model.selectedPosition,
              let azimuth = position.azimuthDeg,
              let elevation = position.elevationDeg
        else {
            return nil
        }
        let elapsed = interpolationElapsed
        return SkySighting(
            position: position,
            azDeg: Self.wrapAzimuth(azimuth + position.azRateDegPerSec * elapsed),
            elDeg: elevation + position.elRateDegPerSec * elapsed
        )
    }

    private var isOnTarget: Bool {
        guard let matrix = motion.rotationMatrix, let selected = selectedSky,
              selected.elDeg > 0
        else {
            return false
        }
        let projector = SkyProjector(matrix: matrix, size: CGSize(width: 1, height: 1))
        return projector.offAxisDeg(azDeg: selected.azDeg, elDeg: selected.elDeg) < Self.lockDeg
    }

    /// The satellite nearest the crosshair, within `hoverDeg` of the aim.
    private var hoveredSky: SkySighting? {
        guard let matrix = motion.rotationMatrix else {
            return nil
        }
        let projector = SkyProjector(matrix: matrix, size: CGSize(width: 1, height: 1))
        let elapsed = interpolationElapsed
        var best: SkySighting?
        var bestOffAxis = Self.hoverDeg
        for position in model.positions {
            guard let baseAz = position.azimuthDeg, let baseEl = position.elevationDeg else {
                continue
            }
            let azNow = Self.wrapAzimuth(baseAz + position.azRateDegPerSec * elapsed)
            let elNow = baseEl + position.elRateDegPerSec * elapsed
            guard elNow > -2 else {
                continue
            }
            let offAxis = projector.offAxisDeg(azDeg: azNow, elDeg: elNow)
            if offAxis < bestOffAxis {
                bestOffAxis = offAxis
                best = SkySighting(position: position, azDeg: azNow, elDeg: elNow)
            }
        }
        return best
    }

    private var overlayChrome: some View {
        VStack {
            HStack {
                Label("Sky view — move the phone around", systemImage: "sparkles")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.thinMaterial, in: Capsule())
                RotatorStatusChip()
                Spacer()
                Button {
                    arEnabled.toggle()
                } label: {
                    Image(systemName: arEnabled ? "video.fill" : "video")
                        .font(.title3)
                        .foregroundStyle(arEnabled ? Color.orange : Color.secondary)
                }
                .accessibilityLabel(arEnabled ? "Turn off camera view" : "Turn on camera view")
                Button {
                    onClose()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
                .accessibilityLabel("Close sky view")
            }
            .padding()
            if arEnabled, cameraDenied {
                Text("Camera access denied — allow it in Settings to use the camera view")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            Spacer()
            RotatorPointTrackButton(model: model, hovered: hoveredSky?.position)
                .padding(.bottom, 10)
            SkyDomeFooter(
                hovered: hoveredSky,
                selected: selectedSky,
                selectedNoradID: model.selectedNoradID,
                isOnTarget: isOnTarget,
                elementTiltDeg: motion.elementTiltDeg,
                transmitters: { model.transmitters(for: $0) },
                polarization: { model.polarization(for: $0) }
            )
            .padding(.bottom, 12)
        }
    }

    /// TimelineView drives redraws on a clock (20 fps), so dead-reckoned
    /// satellite motion continues even when the attitude is perfectly
    /// still — interpolation must not depend on motion-sensor noise.
    private func sky(matrix: CMRotationMatrix) -> some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20.0)) { _ in
            Canvas { context, size in
                let projector = SkyProjector(matrix: matrix, size: size)
                drawSkyLine(context, projector: projector, elevation: 0, opacity: 0.5)
                drawSkyLine(context, projector: projector, elevation: 30, opacity: 0.15)
                drawSkyLine(context, projector: projector, elevation: 60, opacity: 0.15)
                drawCardinals(context, projector: projector)
                drawSkyPath(context, projector: projector)
                drawSatellites(context, projector: projector, size: size)
                drawCrosshair(context, size: size)
                drawOffscreenArrow(context, projector: projector, size: size)
            }
        }
        .ignoresSafeArea()
    }

    private static func wrapAzimuth(_ degrees: Double) -> Double {
        var value = degrees.truncatingRemainder(dividingBy: 360)
        if value < 0 {
            value += 360
        }
        return value
    }

    /// Fetch the hovered satellite's pass path (cached in the model) so the
    /// dome can draw it even when the satellite isn't selected.
    private func refreshHoverTrack(for noradID: Int?) {
        guard let noradID else {
            hoverTrack = []
            hoverTrackID = nil
            return
        }
        guard noradID != hoverTrackID else {
            return
        }
        hoverTrackID = noradID
        Task {
            let track = await model.skyTrack(for: noradID)
            if hoverTrackID == noradID {
                hoverTrack = track
            }
        }
    }
}

// MARK: - Sky drawing

private extension SatelliteSkyDomeView {
    /// Pass arcs projected into the sky wherever they're above the horizon:
    /// orange for the selected satellite, white for a hovered one.
    func drawSkyPath(_ context: GraphicsContext, projector: SkyProjector) {
        strokeSkyTrack(
            context,
            projector: projector,
            track: model.selectedTrack,
            color: .orange.opacity(0.55)
        )
        if let hoverTrackID, hoverTrackID != model.selectedNoradID {
            strokeSkyTrack(
                context,
                projector: projector,
                track: hoverTrack,
                color: .white.opacity(0.45)
            )
        }
    }

    func strokeSkyTrack(
        _ context: GraphicsContext,
        projector: SkyProjector,
        track: [SatellitePosition],
        color: Color
    ) {
        var path = Path()
        var previous: CGPoint?
        for point in track {
            guard let azimuth = point.azimuthDeg,
                  let elevation = point.elevationDeg,
                  elevation > 0,
                  let screen = projector.project(azDeg: azimuth, elDeg: elevation)
            else {
                previous = nil
                continue
            }
            if let last = previous, abs(screen.x - last.x) < 300, abs(screen.y - last.y) < 300 {
                path.addLine(to: screen)
            } else {
                path.move(to: screen)
            }
            previous = screen
        }
        context.stroke(
            path,
            with: .color(color),
            style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])
        )
    }

    func drawSkyLine(
        _ context: GraphicsContext,
        projector: SkyProjector,
        elevation: Double,
        opacity: Double
    ) {
        var path = Path()
        var previous: CGPoint?
        for azimuth in stride(from: 0.0, through: 360.0, by: 3.0) {
            let point = projector.project(azDeg: azimuth, elDeg: elevation)
            if let point, let last = previous, abs(point.x - last.x) < 200, abs(point.y - last.y) < 200 {
                path.addLine(to: point)
            } else if let point {
                path.move(to: point)
            }
            previous = point
        }
        let style = StrokeStyle(lineWidth: elevation == 0 ? 1.5 : 1, dash: elevation == 0 ? [] : [4, 6])
        context.stroke(path, with: .color(.white.opacity(opacity)), style: style)
    }

    private func drawCardinals(_ context: GraphicsContext, projector: SkyProjector) {
        let cardinals: [(String, Double)] = [("N", 0), ("E", 90), ("S", 180), ("W", 270)]
        for (label, azimuth) in cardinals {
            guard let point = projector.project(azDeg: azimuth, elDeg: 2) else {
                continue
            }
            context.draw(
                Text(label)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(Color.white.opacity(0.7)),
                at: point
            )
        }
    }

    private func drawSatellites(
        _ context: GraphicsContext,
        projector: SkyProjector,
        size: CGSize
    ) {
        let elapsed = interpolationElapsed
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let hoveredID = hoveredSky?.position.noradID
        for position in model.positions {
            guard let baseAz = position.azimuthDeg, let baseEl = position.elevationDeg else {
                continue
            }
            let azNow = Self.wrapAzimuth(baseAz + position.azRateDegPerSec * elapsed)
            let elNow = baseEl + position.elRateDegPerSec * elapsed
            guard elNow > -2, let point = projector.project(azDeg: azNow, elDeg: elNow) else {
                continue
            }
            let isSelected = position.noradID == model.selectedNoradID
            let isHovered = position.noradID == hoveredID
            drawDot(context, at: point, isSelected: isSelected, isHovered: isHovered)
            let distanceToCenter = hypot(point.x - center.x, point.y - center.y)
            if isSelected || isHovered || distanceToCenter < 80 {
                context.draw(
                    Text(position.name)
                        .font(isHovered ? .caption2.weight(.bold) : .caption2)
                        .foregroundStyle(
                            isSelected ? Color.orange : Color.white.opacity(isHovered ? 1 : 0.8)
                        ),
                    at: CGPoint(x: point.x, y: point.y - 16)
                )
            }
        }
    }

    private func drawDot(
        _ context: GraphicsContext,
        at point: CGPoint,
        isSelected: Bool,
        isHovered: Bool
    ) {
        if isHovered {
            let halo = CGRect(x: point.x - 15, y: point.y - 15, width: 30, height: 30)
            context.stroke(
                Path(ellipseIn: halo),
                with: .color(.white.opacity(0.8)),
                style: StrokeStyle(lineWidth: 1, dash: [3, 3])
            )
        }
        if isSelected {
            let ring = CGRect(x: point.x - 11, y: point.y - 11, width: 22, height: 22)
            context.stroke(Path(ellipseIn: ring), with: .color(.orange), lineWidth: 1.5)
            let dot = CGRect(x: point.x - 5, y: point.y - 5, width: 10, height: 10)
            context.fill(Path(ellipseIn: dot), with: .color(.orange))
        } else {
            let size: CGFloat = isHovered ? 8 : 6
            let dot = CGRect(x: point.x - size / 2, y: point.y - size / 2, width: size, height: size)
            context.fill(
                Path(ellipseIn: dot),
                with: .color(isHovered ? .white : .teal.opacity(0.9))
            )
        }
    }

    private func drawCrosshair(_ context: GraphicsContext, size: CGSize) {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let color = Color.white.opacity(isOnTarget ? 0 : 0.6)
        let ring = CGRect(x: center.x - 14, y: center.y - 14, width: 28, height: 28)
        context.stroke(
            Path(ellipseIn: ring),
            with: .color(isOnTarget ? .green : color),
            lineWidth: isOnTarget ? 2.5 : 1.5
        )
    }

    private func drawOffscreenArrow(
        _ context: GraphicsContext,
        projector: SkyProjector,
        size: CGSize
    ) {
        guard let selected = selectedSky, selected.elDeg > 0,
              projector.project(azDeg: selected.azDeg, elDeg: selected.elDeg) == nil
              || projector.offAxisDeg(azDeg: selected.azDeg, elDeg: selected.elDeg) > 60
        else {
            return
        }
        let direction = projector.screenDirection(azDeg: selected.azDeg, elDeg: selected.elDeg)
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let radius = min(size.width, size.height) / 2 - 50
        let tip = CGPoint(
            x: center.x + direction.dx * radius,
            y: center.y + direction.dy * radius
        )
        var arrow = Path()
        let angle = atan2(direction.dy, direction.dx)
        arrow.move(to: tip)
        arrow.addLine(to: CGPoint(
            x: tip.x - 18 * cos(angle - 0.4), y: tip.y - 18 * sin(angle - 0.4)
        ))
        arrow.addLine(to: CGPoint(
            x: tip.x - 18 * cos(angle + 0.4), y: tip.y - 18 * sin(angle + 0.4)
        ))
        arrow.closeSubpath()
        context.fill(arrow, with: .color(.orange))
    }
}
