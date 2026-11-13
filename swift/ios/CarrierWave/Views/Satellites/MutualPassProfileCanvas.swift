import CoreLocation
import SwiftUI

// MARK: - MutualPassProfileCanvas

/// The cross-section drawing itself.
struct MutualPassProfileCanvas: View {
    // MARK: Internal

    let samples: [MutualPassSample]
    let plane: MutualProfilePlane
    let currentIndex: Int
    let labelA: String
    let labelB: String

    var body: some View {
        Canvas { context, size in
            let projection = ProfileProjection(plane: plane, samples: samples, size: size)
            drawEarth(in: &context, projection: projection)
            drawCoverage(in: &context, projection: projection)
            drawPath(in: &context, projection: projection)
            drawStations(in: &context, projection: projection)
            drawSatellite(in: &context, projection: projection)
        }
        .accessibilityLabel("Pass profile: Earth cross-section with both stations and the satellite path")
    }

    // MARK: Private

    private func drawEarth(in context: inout GraphicsContext, projection: ProfileProjection) {
        let surface = projection.surfacePath()
        var ground = surface
        ground.addLine(to: CGPoint(x: projection.size.width, y: projection.size.height))
        ground.addLine(to: CGPoint(x: 0, y: projection.size.height))
        ground.closeSubpath()
        context.fill(ground, with: .color(Color(.systemGray5)))
        context.stroke(surface, with: .color(.secondary), lineWidth: 1.5)
    }

    /// Surface arc currently inside the satellite's footprint.
    private func drawCoverage(in context: inout GraphicsContext, projection: ProfileProjection) {
        let sample = samples[currentIndex]
        let point = plane.planePoint(
            latitude: sample.latitude, longitude: sample.longitude, altitudeKm: sample.altitudeKm
        )
        let beta = acos(MutualProfilePlane.earthRadiusKm / (MutualProfilePlane.earthRadiusKm + sample.altitudeKm))
        let arc = projection.surfacePath(from: point.theta - beta, to: point.theta + beta)
        context.stroke(arc, with: .color(.orange.opacity(0.55)), style: StrokeStyle(lineWidth: 5, lineCap: .round))
    }

    private func drawPath(in context: inout GraphicsContext, projection: ProfileProjection) {
        var both = Path()
        var one = Path()
        var none = Path()
        for index in 1 ..< samples.count {
            let previous = projection.point(for: samples[index - 1])
            let current = projection.point(for: samples[index])
            var segment = Path()
            segment.move(to: previous)
            segment.addLine(to: current)
            if samples[index].bothVisible, samples[index - 1].bothVisible {
                both.addPath(segment)
            } else if samples[index].eitherVisible {
                one.addPath(segment)
            } else {
                none.addPath(segment)
            }
        }
        context.stroke(none, with: .color(.secondary.opacity(0.35)), lineWidth: 2)
        context.stroke(one, with: .color(.orange), lineWidth: 2.5)
        context.stroke(both, with: .color(.green), lineWidth: 3.5)
    }

    private func drawStations(in context: inout GraphicsContext, projection: ProfileProjection) {
        let pointA = projection.point(theta: 0, radiusKm: MutualProfilePlane.earthRadiusKm)
        let pointB = projection.point(theta: plane.gamma, radiusKm: MutualProfilePlane.earthRadiusKm)
        // Stagger labels vertically when the stations render close together.
        let crowded = abs(pointB.x - pointA.x) < 70
        for (point, label, offset) in [(pointA, labelA, 14.0), (pointB, labelB, crowded ? 28.0 : 14.0)] {
            let dot = Path(ellipseIn: CGRect(x: point.x - 5, y: point.y - 5, width: 10, height: 10))
            context.fill(dot, with: .color(.primary))
            context.draw(
                Text(label)
                    .font(.caption2.weight(.semibold).monospaced())
                    .foregroundStyle(.secondary),
                at: CGPoint(x: point.x, y: point.y + offset)
            )
        }
    }

    private func drawSatellite(in context: inout GraphicsContext, projection: ProfileProjection) {
        let sample = samples[currentIndex]
        let satPoint = projection.point(for: sample)
        let stations: [(theta: Double, elevation: Double)] =
            [(0, sample.elevationADeg), (plane.gamma, sample.elevationBDeg)]
        for station in stations where station.elevation > 0 {
            let base = projection.point(theta: station.theta, radiusKm: MutualProfilePlane.earthRadiusKm)
            var sight = Path()
            sight.move(to: base)
            sight.addLine(to: satPoint)
            context.stroke(
                sight,
                with: .color(.green.opacity(0.5)),
                style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])
            )
        }
        let dot = Path(ellipseIn: CGRect(x: satPoint.x - 6, y: satPoint.y - 6, width: 12, height: 12))
        context.fill(dot, with: .color(PointingInstrumentStyle.flyTo))
        context.stroke(dot, with: .color(.white), lineWidth: 1.5)
    }
}

// MARK: - ProfileProjection

/// Maps in-plane polar coordinates to screen points, framed so the surface
/// chord between the stations and the whole sampled path fit the canvas at
/// true proportions.
struct ProfileProjection {
    // MARK: Lifecycle

    init(plane: MutualProfilePlane, samples: [MutualPassSample], size: CGSize) {
        self.size = size
        planeRef = plane
        var minTheta = 0.0
        var maxTheta = plane.gamma
        var maxAltKm = 0.0
        for sample in samples {
            let point = plane.planePoint(
                latitude: sample.latitude, longitude: sample.longitude, altitudeKm: sample.altitudeKm
            )
            minTheta = min(minTheta, point.theta)
            maxTheta = max(maxTheta, point.theta)
            maxAltKm = max(maxAltKm, sample.altitudeKm)
        }
        let margin = 0.06
        minTheta -= margin
        maxTheta += margin
        mid = (minTheta + maxTheta) / 2
        let halfSpan = max((maxTheta - minTheta) / 2, 0.02)
        // Altitude is log-compressed so high orbits (Molniya/HEO apogees)
        // don't shrink the Earth to a bump; LEO stays essentially true.
        let compressedAlt = log(1 + maxAltKm / MutualProfilePlane.earthRadiusKm)
        let altFactor = 1 + compressedAlt
        let inset = 16.0
        let widthLimit = (size.width / 2 - inset) / (sin(min(halfSpan, 1.4)) * altFactor)
        let heightLimit = (size.height - 2 * inset) /
            ((1 - cos(min(halfSpan, 1.4))) + compressedAlt)
        earthRadiusPx = max(min(widthLimit, heightLimit), 1)
        center = CGPoint(x: size.width / 2, y: inset + earthRadiusPx * altFactor)
        surfaceSpan = (minTheta, maxTheta)
    }

    // MARK: Internal

    let size: CGSize

    func point(theta: Double, radiusKm: Double) -> CGPoint {
        let earthKm = MutualProfilePlane.earthRadiusKm
        let altitude = max(radiusKm - earthKm, 0)
        let displayFactor = 1 + log(1 + altitude / earthKm)
        let radius = earthRadiusPx * displayFactor
        return CGPoint(
            x: center.x + radius * sin(theta - mid),
            y: center.y - radius * cos(theta - mid)
        )
    }

    func point(for sample: MutualPassSample) -> CGPoint {
        let polar = planeRef.planePoint(
            latitude: sample.latitude, longitude: sample.longitude, altitudeKm: sample.altitudeKm
        )
        return point(theta: polar.theta, radiusKm: polar.radiusKm)
    }

    func surfacePath() -> Path {
        surfacePath(from: surfaceSpan.0 - 0.3, to: surfaceSpan.1 + 0.3)
    }

    func surfacePath(from startTheta: Double, to endTheta: Double) -> Path {
        var path = Path()
        let steps = 64
        for step in 0 ... steps {
            let theta = startTheta + (endTheta - startTheta) * Double(step) / Double(steps)
            let screen = point(theta: theta, radiusKm: MutualProfilePlane.earthRadiusKm)
            if step == 0 {
                path.move(to: screen)
            } else {
                path.addLine(to: screen)
            }
        }
        return path
    }

    // MARK: Private

    private let planeRef: MutualProfilePlane
    private let mid: Double
    private let earthRadiusPx: Double
    private let center: CGPoint
    private let surfaceSpan: (Double, Double)
}
