import SwiftUI

// MARK: - SatellitePolarFrame

/// Polar sky projection: azimuth is the angle clockwise from the top of the
/// view (less `headingDeg`, so that azimuth sits at the top), elevation is
/// the radius — horizon at the rim, zenith at the centre.
struct SatellitePolarFrame {
    // MARK: Internal

    let center: CGPoint
    let radius: CGFloat
    let headingDeg: Double

    func point(azimuthDeg: Double, elevationDeg: Double) -> CGPoint {
        let elevation = min(max(elevationDeg, 0), 90)
        return point(azimuthDeg: azimuthDeg, ring: radius * CGFloat((90 - elevation) / 90))
    }

    /// A point `inset` outside the horizon rim at an azimuth (labels).
    func rimPoint(azimuthDeg: Double, inset: CGFloat) -> CGPoint {
        point(azimuthDeg: azimuthDeg, ring: radius + inset)
    }

    // MARK: Private

    private func point(azimuthDeg: Double, ring: CGFloat) -> CGPoint {
        let theta = (azimuthDeg - headingDeg) * .pi / 180
        return CGPoint(x: center.x + ring * sin(theta), y: center.y - ring * cos(theta))
    }
}

// MARK: - SatellitePassArcView

/// Compact polar plot of one pass across the observer's sky: horizon rim,
/// 30°/60° rings, cardinals, the pass arc from rise to set with a travel
/// chevron (dimmed behind `now`), and the satellite — at its live position
/// when up, else at its rise point on the rim. Draws once per parent
/// render; the caller supplies the clock and the rotation.
struct SatellitePassArcView: View {
    // MARK: Internal

    let arc: [SatelliteSkySample]
    let pass: SatellitePass?
    /// Live look while the bird is up (nil below the horizon).
    let liveAzDeg: Double?
    let liveElDeg: Double?
    /// Azimuth drawn at the top (boom/pointing azimuth, or 0 for north-up).
    let headingDeg: Double
    let now: Date

    var body: some View {
        Canvas { context, size in
            let frame = SatellitePolarFrame(
                center: CGPoint(x: size.width / 2, y: size.height / 2),
                radius: min(size.width, size.height) / 2 - Self.labelRoom,
                headingDeg: headingDeg
            )
            drawGrid(context, frame: frame)
            drawArc(context, frame: frame)
            drawSatellite(context, frame: frame)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityLabel(accessibilityDescription)
    }

    // MARK: Private

    private static let labelRoom: CGFloat = 16
    private static let gridColor = Color.white.opacity(0.35)
    private static let arcColor = Color(red: 0.45, green: 0.62, blue: 0.98)
    private static let satelliteColor = Color.orange

    private var accessibilityDescription: String {
        if let liveAzDeg, let liveElDeg, liveElDeg > 0 {
            return "Satellite up at \(SatellitePassRow.compassLabel(liveAzDeg)), "
                + "elevation \(Int(liveElDeg)) degrees"
        }
        if let pass {
            return "Pass rises at \(SatellitePassRow.compassLabel(pass.aosAzimuthDeg)), peaks at "
                + "\(Int(pass.peakElevationDeg)) degrees, sets at "
                + SatellitePassRow.compassLabel(pass.losAzimuthDeg)
        }
        return "No pass"
    }

    private static func arrowHead(tip: CGPoint, direction: CGVector, length: CGFloat, width: CGFloat) -> Path {
        let magnitude = hypot(direction.dx, direction.dy)
        guard magnitude > 0 else {
            return Path()
        }
        let unit = CGVector(dx: direction.dx / magnitude, dy: direction.dy / magnitude)
        let normal = CGVector(dx: -unit.dy, dy: unit.dx)
        let base = CGPoint(x: tip.x - unit.dx * length, y: tip.y - unit.dy * length)
        var path = Path()
        path.move(to: tip)
        path.addLine(to: CGPoint(x: base.x + normal.dx * width / 2, y: base.y + normal.dy * width / 2))
        path.addLine(to: CGPoint(x: base.x - normal.dx * width / 2, y: base.y - normal.dy * width / 2))
        path.closeSubpath()
        return path
    }

    private func drawGrid(_ context: GraphicsContext, frame: SatellitePolarFrame) {
        for elevation in [0.0, 30.0, 60.0] {
            let ring = frame.radius * CGFloat((90 - elevation) / 90)
            let path = Path(ellipseIn: CGRect(
                x: frame.center.x - ring, y: frame.center.y - ring, width: ring * 2, height: ring * 2
            ))
            context.stroke(
                path,
                with: .color(elevation == 0 ? Color.white.opacity(0.7) : Self.gridColor),
                lineWidth: elevation == 0 ? 1.5 : 1
            )
        }
        var spokes = Path()
        for azimuth in stride(from: 0.0, to: 360.0, by: 45.0) {
            spokes.move(to: frame.center)
            spokes.addLine(to: frame.point(azimuthDeg: azimuth, elevationDeg: 0))
        }
        context.stroke(spokes, with: .color(Self.gridColor.opacity(0.6)), lineWidth: 1)
        let cardinals: [(String, Double)] = [("N", 0), ("E", 90), ("S", 180), ("W", 270)]
        for (letter, azimuth) in cardinals {
            context.draw(
                Text(letter)
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.9)),
                at: frame.rimPoint(azimuthDeg: azimuth, inset: Self.labelRoom - 6)
            )
        }
    }

    /// Dim behind "now", dashed ahead, chevron a third of the way along,
    /// rise/set dots on the rim.
    private func drawArc(_ context: GraphicsContext, frame: SatellitePolarFrame) {
        if let pass {
            for azimuth in [pass.aosAzimuthDeg, pass.losAzimuthDeg] {
                let mark = frame.point(azimuthDeg: azimuth, elevationDeg: 0)
                let dot = Path(ellipseIn: CGRect(x: mark.x - 3, y: mark.y - 3, width: 6, height: 6))
                context.fill(dot, with: .color(Self.arcColor))
            }
        }
        guard arc.count >= 2 else {
            return
        }
        let points = arc.map { frame.point(azimuthDeg: $0.azimuthDeg, elevationDeg: $0.elevationDeg) }
        var elapsed = Path()
        var remaining = Path()
        for (index, sample) in arc.enumerated() {
            if sample.date < now {
                if index == 0 {
                    elapsed.move(to: points[index])
                } else {
                    elapsed.addLine(to: points[index])
                }
            } else {
                if remaining.isEmpty {
                    remaining.move(to: points[max(index - 1, 0)])
                }
                remaining.addLine(to: points[index])
            }
        }
        let style = StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round)
        context.stroke(elapsed, with: .color(Self.arcColor.opacity(0.35)), style: style)
        context.stroke(
            remaining, with: .color(Self.arcColor),
            style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round, dash: [8, 5])
        )
        let chevron = max(min(arc.count / 3, arc.count - 2), 1)
        let direction = CGVector(
            dx: points[chevron + 1].x - points[chevron - 1].x,
            dy: points[chevron + 1].y - points[chevron - 1].y
        )
        context.fill(
            Self.arrowHead(tip: points[chevron], direction: direction, length: 9, width: 9),
            with: .color(Self.arcColor)
        )
    }

    private func drawSatellite(_ context: GraphicsContext, frame: SatellitePolarFrame) {
        let point: CGPoint
        let isUp: Bool
        if let liveAzDeg, let liveElDeg, liveElDeg > 0 {
            point = frame.point(azimuthDeg: liveAzDeg, elevationDeg: liveElDeg)
            isUp = true
        } else if let pass {
            point = frame.point(azimuthDeg: pass.aosAzimuthDeg, elevationDeg: 0)
            isUp = false
        } else {
            return
        }
        if isUp {
            let halo = Path(ellipseIn: CGRect(x: point.x - 10, y: point.y - 10, width: 20, height: 20))
            context.fill(halo, with: .color(Self.satelliteColor.opacity(0.25)))
        }
        let dot = Path(ellipseIn: CGRect(x: point.x - 5.5, y: point.y - 5.5, width: 11, height: 11))
        context.fill(dot, with: .color(Self.satelliteColor))
        context.stroke(dot, with: .color(.white.opacity(0.85)), lineWidth: 1.2)
    }
}
