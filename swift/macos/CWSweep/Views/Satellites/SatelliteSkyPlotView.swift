import CarrierWaveData
import SwiftUI

// MARK: - SatelliteSkyColumnView

/// Left column of the main area: polar sky plot, live Az/El readouts and
/// the elevation-vs-time profile for the selected pass.
struct SatelliteSkyColumnView: View {
    let model: SatellitePassModel

    var body: some View {
        VStack(spacing: 12) {
            SatelliteSkyPlotView(frame: model.frame, rotatorPosition: model.rotator.position)
                .aspectRatio(1, contentMode: .fit)
                .frame(maxWidth: .infinity)
            SatelliteLookReadoutView(look: model.frame.look)
            SatellitePointTrackButton(model: model)
            SatelliteElevationProfileView(frame: model.frame)
                .frame(height: 70)
        }
    }
}

// MARK: - SatelliteSkyPlotView

/// Polar plot of the observer's sky: horizon ring, 30°/60° rings, compass
/// labels, predicted (dashed) and flown (solid) tracks, the dead-reckoned
/// satellite marker and the rotator's reported pointing.
struct SatelliteSkyPlotView: View {
    // MARK: Internal

    let frame: SatellitePassFrame
    let rotatorPosition: RotatorPosition?

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: frame.look == nil)) { timeline in
            Canvas(rendersAsynchronously: false) { context, size in
                draw(context: context, size: size, date: timeline.date)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(SatelliteTheme.panel)
        )
        .onChange(of: frame.predictedTrack, initial: true) { _, track in
            predictedUnitPath = SatellitePassFormat.unitTrackPath(track)
        }
        .onChange(of: frame.flownTrack.count, initial: true) { _, _ in
            flownUnitPath = SatellitePassFormat.unitTrackPath(frame.flownTrack)
        }
    }

    // MARK: Private

    private static let compassLabels: [(azimuth: Double, label: String)] = [
        (0, "N"), (90, "E"), (180, "S"), (270, "W"),
    ]

    @State private var predictedUnitPath: CGPath = CGMutablePath()
    @State private var flownUnitPath: CGPath = CGMutablePath()

    private func draw(context: GraphicsContext, size: CGSize, date: Date) {
        let inset: CGFloat = 26
        let radius = max(10, min(size.width, size.height) / 2 - inset)
        let center = CGPoint(x: size.width / 2, y: size.height / 2)

        drawGrid(context: context, center: center, radius: radius)
        drawTracks(context: context, center: center, radius: radius)
        drawSatellite(context: context, center: center, radius: radius, date: date)
        drawRotator(context: context, center: center, radius: radius)
    }

    private func drawGrid(context: GraphicsContext, center: CGPoint, radius: CGFloat) {
        let horizon = circle(center: center, radius: radius)
        context.fill(horizon, with: .color(SatelliteTheme.background.opacity(0.7)))
        context.stroke(horizon, with: .color(SatelliteTheme.gridLine), lineWidth: 1.2)

        for elevation in [30.0, 60.0] {
            let ring = circle(center: center, radius: radius * CGFloat((90 - elevation) / 90))
            context.stroke(
                ring, with: .color(SatelliteTheme.gridLine), style: StrokeStyle(lineWidth: 0.8, dash: [3, 3])
            )
        }

        // Radial ticks every 30°; cardinal spokes run to the centre.
        var ticks = Path()
        var spokes = Path()
        for step in 0 ..< 12 {
            let azimuth = Double(step) * 30
            let outer = point(azimuth: azimuth, elevation: 0, center: center, radius: radius)
            if step.isMultiple(of: 3) {
                spokes.move(to: center)
                spokes.addLine(to: outer)
            } else {
                ticks.move(to: point(azimuth: azimuth, elevation: 6, center: center, radius: radius))
                ticks.addLine(to: outer)
            }
        }
        context.stroke(spokes, with: .color(SatelliteTheme.gridLine.opacity(0.6)), lineWidth: 0.6)
        context.stroke(ticks, with: .color(SatelliteTheme.gridLine), lineWidth: 1)

        for item in Self.compassLabels {
            let position = point(azimuth: item.azimuth, elevation: 0, center: center, radius: radius + 13)
            context.draw(
                Text(item.label)
                    .font(SatelliteTheme.label(11, weight: .semibold))
                    .foregroundStyle(SatelliteTheme.textSecondary),
                at: position
            )
        }
        for elevation in [30.0, 60.0] {
            let position = point(azimuth: 0, elevation: elevation, center: center, radius: radius)
            context.draw(
                Text("\(Int(elevation))°")
                    .font(SatelliteTheme.mono(9))
                    .foregroundStyle(SatelliteTheme.textTertiary),
                at: CGPoint(x: position.x + 10, y: position.y + 6)
            )
        }
    }

    private func drawTracks(context: GraphicsContext, center: CGPoint, radius: CGFloat) {
        let transform = CGAffineTransform(translationX: center.x, y: center.y).scaledBy(x: radius, y: radius)
        if !predictedUnitPath.isEmpty {
            context.stroke(
                Path(predictedUnitPath).applying(transform),
                with: .color(SatelliteTheme.accent.opacity(0.75)),
                style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [5, 4])
            )
        }
        if !flownUnitPath.isEmpty {
            context.stroke(
                Path(flownUnitPath).applying(transform),
                with: .color(SatelliteTheme.accent),
                style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round)
            )
        }
        if let first = frame.predictedTrack.first, let last = frame.predictedTrack.last {
            drawEndpoint(context: context, label: "AOS", point: first, center: center, radius: radius)
            drawEndpoint(context: context, label: "LOS", point: last, center: center, radius: radius)
        }
    }

    private func drawEndpoint(
        context: GraphicsContext, label: String, point trackPoint: SkyTrackPoint, center: CGPoint, radius: CGFloat
    ) {
        let position = point(
            azimuth: trackPoint.azimuthDeg, elevation: trackPoint.elevationDeg, center: center, radius: radius
        )
        context.fill(circle(center: position, radius: 2.5), with: .color(SatelliteTheme.accent))
        // Push the label outward from the centre so it clears the horizon ring.
        let offsetX = position.x - center.x
        let offsetY = position.y - center.y
        let length = max(1, hypot(offsetX, offsetY))
        let labelPoint = CGPoint(x: position.x + offsetX / length * 14, y: position.y + offsetY / length * 14)
        context.draw(
            Text(label).font(SatelliteTheme.label(9, weight: .semibold)).foregroundStyle(SatelliteTheme.accent),
            at: labelPoint
        )
    }

    private func drawSatellite(context: GraphicsContext, center: CGPoint, radius: CGFloat, date: Date) {
        guard let look = frame.look else {
            return
        }
        let live = look.advanced(by: date.timeIntervalSince(look.at))
        guard live.elevationDeg >= -0.5 else {
            return
        }
        let position = point(azimuth: live.azimuthDeg, elevation: live.elevationDeg, center: center, radius: radius)

        var bearing = Path()
        bearing.move(to: center)
        bearing.addLine(to: position)
        context.stroke(bearing, with: .color(SatelliteTheme.satellite.opacity(0.55)), lineWidth: 1)

        // ~1 Hz pulse: ring grows from 6 → 16 pt while fading out.
        let phase = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1)
        let pulse = circle(center: position, radius: 6 + 10 * CGFloat(phase))
        context.stroke(pulse, with: .color(SatelliteTheme.satellite.opacity(0.7 * (1 - phase))), lineWidth: 1.5)

        let core = circle(center: position, radius: 4.5)
        context.fill(core, with: .color(SatelliteTheme.satellite))
        context.stroke(core, with: .color(SatelliteTheme.background), lineWidth: 1)
    }

    private func drawRotator(context: GraphicsContext, center: CGPoint, radius: CGFloat) {
        guard let rotatorPosition else {
            return
        }
        let position = point(
            azimuth: rotatorPosition.azimuthDeg, elevation: rotatorPosition.elevationDeg,
            center: center, radius: radius
        )
        let reticleRadius: CGFloat = 7
        var reticle = circle(center: position, radius: reticleRadius)
        for (stepX, stepY) in [(1.0, 0.0), (-1.0, 0.0), (0.0, 1.0), (0.0, -1.0)] {
            reticle.move(to: CGPoint(
                x: position.x + stepX * (reticleRadius - 2), y: position.y + stepY * (reticleRadius - 2)
            ))
            reticle.addLine(to: CGPoint(
                x: position.x + stepX * (reticleRadius + 3), y: position.y + stepY * (reticleRadius + 3)
            ))
        }
        context.stroke(reticle, with: .color(SatelliteTheme.rx), lineWidth: 1.2)
    }

    private func circle(center: CGPoint, radius: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
    }

    private func point(azimuth: Double, elevation: Double, center: CGPoint, radius: CGFloat) -> CGPoint {
        SatellitePassFormat.polarPoint(azimuthDeg: azimuth, elevationDeg: elevation, center: center, radius: radius)
    }
}

// MARK: - SatelliteLookReadoutView

/// Big tabular Az/El plus range and range rate for the live look.
struct SatelliteLookReadoutView: View {
    // MARK: Internal

    let look: SatelliteLiveLook?

    var body: some View {
        VStack(spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 18) {
                readout(label: "AZ", value: SatellitePassFormat.degrees(look?.azimuthDeg))
                readout(label: "EL", value: SatellitePassFormat.degrees(look?.elevationDeg))
            }
            HStack(spacing: 14) {
                Text("Range \(SatellitePassFormat.kilometers(look?.rangeKm))")
                Text("Rate \(SatellitePassFormat.kmPerSecond(look?.rangeRateKmPerSec))")
            }
            .font(SatelliteTheme.mono(11))
            .foregroundStyle(SatelliteTheme.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Private

    private var valueColor: Color {
        guard let look else {
            return SatelliteTheme.textTertiary
        }
        return look.isAboveHorizon ? SatelliteTheme.textPrimary : SatelliteTheme.textSecondary
    }

    private func readout(label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(label)
                .font(SatelliteTheme.label(11, weight: .semibold))
                .foregroundStyle(SatelliteTheme.textTertiary)
            Text(value)
                .font(SatelliteTheme.mono(26, weight: .semibold))
                .foregroundStyle(valueColor)
        }
    }
}

// MARK: - SatelliteElevationProfileView

/// Predicted elevation over the pass (AOS → LOS) with a cursor at `now`.
struct SatelliteElevationProfileView: View {
    // MARK: Internal

    let frame: SatellitePassFrame

    var body: some View {
        Canvas(rendersAsynchronously: false) { context, size in
            draw(context: context, size: size)
        }
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(SatelliteTheme.panel)
        )
    }

    // MARK: Private

    /// Maps pass time / elevation into the plot rectangle.
    private struct Scale {
        let pass: SweepPass
        let plot: CGRect
        let maxElevation: Double

        var baseline: CGFloat {
            plot.maxY
        }

        func x(_ date: Date) -> CGFloat {
            let fraction = min(max(date.timeIntervalSince(pass.aos) / pass.duration, 0), 1)
            return plot.minX + plot.width * CGFloat(fraction)
        }

        func y(_ elevation: Double) -> CGFloat {
            baseline - plot.height * CGFloat(min(max(elevation, 0), maxElevation) / maxElevation)
        }
    }

    private func draw(context: GraphicsContext, size: CGSize) {
        let plot = CGRect(x: 10, y: 8, width: size.width - 20, height: size.height - 24)
        guard plot.width > 0, plot.height > 0 else {
            return
        }

        var horizon = Path()
        horizon.move(to: CGPoint(x: plot.minX, y: plot.maxY))
        horizon.addLine(to: CGPoint(x: plot.maxX, y: plot.maxY))
        context.stroke(horizon, with: .color(SatelliteTheme.gridLine), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))

        guard let pass = frame.pass, pass.duration > 0 else {
            context.draw(
                Text("No pass selected").font(SatelliteTheme.label(10)).foregroundStyle(SatelliteTheme.textTertiary),
                at: CGPoint(x: plot.midX, y: plot.midY)
            )
            return
        }
        let scale = Scale(pass: pass, plot: plot, maxElevation: max(90, pass.peakElevationDeg))
        drawProfile(context: context, scale: scale)
        drawMarkers(context: context, scale: scale)
    }

    private func drawProfile(context: GraphicsContext, scale: Scale) {
        let track = frame.predictedTrack
        guard track.count >= 2 else {
            // No track yet: sketch AOS → peak → LOS so the card isn't blank.
            let peakY = scale.y(scale.pass.peakElevationDeg)
            var sketch = Path()
            sketch.move(to: CGPoint(x: scale.plot.minX, y: scale.baseline))
            sketch.addQuadCurve(
                to: CGPoint(x: scale.plot.maxX, y: scale.baseline),
                control: CGPoint(x: scale.x(scale.pass.peak), y: peakY - (scale.baseline - peakY))
            )
            context.stroke(
                sketch, with: .color(SatelliteTheme.accent.opacity(0.5)), style: StrokeStyle(lineWidth: 1, dash: [3, 3])
            )
            return
        }
        var line = Path()
        for (index, sample) in track.enumerated() {
            let position = CGPoint(x: scale.x(sample.time), y: scale.y(sample.elevationDeg))
            if index == 0 {
                line.move(to: position)
            } else {
                line.addLine(to: position)
            }
        }
        var fill = line
        fill.addLine(to: CGPoint(x: scale.x(track[track.count - 1].time), y: scale.baseline))
        fill.addLine(to: CGPoint(x: scale.x(track[0].time), y: scale.baseline))
        fill.closeSubpath()
        context.fill(fill, with: .color(SatelliteTheme.accent.opacity(0.18)))
        context.stroke(line, with: .color(SatelliteTheme.accent), style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))
    }

    private func drawMarkers(context: GraphicsContext, scale: Scale) {
        let pass = scale.pass
        let peakPoint = CGPoint(x: scale.x(pass.peak), y: scale.y(pass.peakElevationDeg))
        context.draw(
            Text(SatellitePassFormat.degrees(pass.peakElevationDeg, decimals: 0))
                .font(SatelliteTheme.mono(9))
                .foregroundStyle(SatelliteTheme.textSecondary),
            at: CGPoint(x: peakPoint.x, y: max(scale.plot.minY + 5, peakPoint.y - 7))
        )

        if pass.isActive(at: frame.now) {
            let cursorX = scale.x(frame.now)
            var cursor = Path()
            cursor.move(to: CGPoint(x: cursorX, y: scale.plot.minY))
            cursor.addLine(to: CGPoint(x: cursorX, y: scale.baseline))
            context.stroke(cursor, with: .color(SatelliteTheme.satellite), lineWidth: 1.2)
        }

        let labelY = scale.baseline + 8
        context.draw(
            endLabel("AOS", pass.aos), at: CGPoint(x: scale.plot.minX, y: labelY), anchor: .leading
        )
        context.draw(
            endLabel("LOS", pass.los), at: CGPoint(x: scale.plot.maxX, y: labelY), anchor: .trailing
        )
    }

    private func endLabel(_ prefix: String, _ date: Date) -> Text {
        Text("\(prefix) \(SatellitePassFormat.utcHHmm(date))")
            .font(SatelliteTheme.mono(9))
            .foregroundStyle(SatelliteTheme.textTertiary)
    }
}
