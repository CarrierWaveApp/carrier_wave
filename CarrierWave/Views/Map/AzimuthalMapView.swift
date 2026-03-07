//
//  AzimuthalMapView.swift
//  CarrierWave
//
//  Azimuthal equidistant projection view showing spot density heatmap,
//  antenna radiation pattern overlay, and QSO markers on a polar plot.
//

import CarrierWaveCore
import SwiftUI

// MARK: - AzimuthalMapView

struct AzimuthalMapView: View {
    // MARK: Internal

    let sectors: [BearingSector]
    let spotPoints: [AzimuthalSpotPoint]
    let qsoPoints: [AzimuthalSpotPoint]
    let antennaPattern: AntennaPattern?
    let compassHeading: Double? // nil = no compass, use manual
    let maxDistanceKm: Double
    var worldRotation: Double = 0 // Degrees to rotate world (negative = CW on screen)

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            let viewRadius = (size / 2) * 0.84 // Leave margin for degree labels

            Canvas { context, canvasSize in
                let cx = canvasSize.width / 2
                let cy = canvasSize.height / 2

                drawBackground(context: context, center: CGPoint(x: cx, y: cy), radius: viewRadius)
                drawDistanceRings(context: context, center: CGPoint(x: cx, y: cy), radius: viewRadius)
                drawSectorHeatmap(
                    context: context, center: CGPoint(x: cx, y: cy), radius: viewRadius
                )
                if let pattern = antennaPattern {
                    drawAntennaPattern(
                        context: context, center: CGPoint(x: cx, y: cy),
                        radius: viewRadius, pattern: pattern
                    )
                }
                drawQSODots(context: context, center: CGPoint(x: cx, y: cy), radius: viewRadius)
                drawSpotDots(context: context, center: CGPoint(x: cx, y: cy), radius: viewRadius)
                drawCompassLabels(
                    context: context, center: CGPoint(x: cx, y: cy), radius: viewRadius
                )
                drawCenterDot(context: context, center: CGPoint(x: cx, y: cy))
            }
            .frame(width: geo.size.width, height: geo.size.height)

            // Legend overlay
            legendOverlay
                .position(x: center.x, y: geo.size.height - 20)
        }
        .aspectRatio(1, contentMode: .fit)
    }

    // MARK: Private

    private static let ringDistancesKm: [Double] = [2_500, 5_000, 10_000, 15_000]

    @Environment(\.colorScheme) private var colorScheme

    private var spotSources: [SpotSource] {
        let sources = Set(spotPoints.compactMap(\.source))
        return SpotSource.allCases.filter { sources.contains($0) }
    }

    private var legendOverlay: some View {
        HStack(spacing: 12) {
            ForEach(spotSources, id: \.self) { source in
                legendItem(color: source.color, label: source.displayName)
            }
            if !qsoPoints.isEmpty {
                legendItem(color: .green, label: "QSOs")
            }
            if antennaPattern != nil {
                legendItem(color: .orange, label: "Pattern")
            }
        }
        .font(.caption2)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.ultraThinMaterial, in: Capsule())
    }

    private func legendItem(color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(label)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Canvas Drawing

private extension AzimuthalMapView {
    func drawBackground(context: GraphicsContext, center: CGPoint, radius: CGFloat) {
        let bgColor = colorScheme == .dark
            ? Color(white: 0.12)
            : Color(white: 0.96)
        let circle = Path(ellipseIn: CGRect(
            x: center.x - radius,
            y: center.y - radius,
            width: radius * 2,
            height: radius * 2
        ))
        context.fill(circle, with: .color(bgColor))
    }

    func drawDistanceRings(context: GraphicsContext, center: CGPoint, radius: CGFloat) {
        let ringColor = colorScheme == .dark
            ? Color.white.opacity(0.12)
            : Color.black.opacity(0.1)

        for ringKm in Self.ringDistancesKm where ringKm < maxDistanceKm {
            let ringRadius = CGFloat(ringKm / maxDistanceKm) * radius
            let ringPath = Path(ellipseIn: CGRect(
                x: center.x - ringRadius,
                y: center.y - ringRadius,
                width: ringRadius * 2,
                height: ringRadius * 2
            ))
            context.stroke(ringPath, with: .color(ringColor), lineWidth: 0.5)

            // Distance label
            let labelText = ringKm >= 1_000
                ? "\(Int(ringKm / 1_000))k km"
                : "\(Int(ringKm)) km"
            let text = Text(labelText)
                .font(.system(size: 8))
                .foregroundColor(colorScheme == .dark ? .white.opacity(0.3) : .black.opacity(0.25))
            context.draw(
                context.resolve(text),
                at: CGPoint(x: center.x + ringRadius + 2, y: center.y),
                anchor: .leading
            )
        }
    }

    /// Rotate a bearing by the world rotation amount
    func rotatedBearing(_ bearing: Double) -> Double {
        var b = bearing + worldRotation
        b = b.truncatingRemainder(dividingBy: 360.0)
        if b < 0 {
            b += 360.0
        }
        return b
    }

    func drawCompassLabels(context: GraphicsContext, center: CGPoint, radius: CGFloat) {
        let cardinals: [(String, Double)] = [("N", 0), ("E", 90), ("S", 180), ("W", 270)]
        let labelRadius = radius + 14

        drawDegreeTicks(
            context: context, center: center, radius: radius,
            labelRadius: labelRadius, cardinals: cardinals
        )
        drawCardinalLabels(
            context: context, center: center,
            labelRadius: labelRadius, cardinals: cardinals
        )
        drawCrosshairLines(context: context, center: center, radius: radius)
    }

    func drawDegreeTicks(
        context: GraphicsContext, center: CGPoint, radius: CGFloat,
        labelRadius: CGFloat, cardinals: [(String, Double)]
    ) {
        let tickColor = colorScheme == .dark
            ? Color.white.opacity(0.25)
            : Color.black.opacity(0.2)
        for deg in stride(from: 0.0, to: 360.0, by: 30.0) {
            let rotated = rotatedBearing(deg)
            let radians = rotated * .pi / 180.0
            let isCardinal = cardinals.contains { $0.1 == deg }

            let innerR = isCardinal ? radius - 6 : radius - 4
            var tick = Path()
            tick.move(to: CGPoint(
                x: center.x + innerR * CGFloat(sin(radians)),
                y: center.y - innerR * CGFloat(cos(radians))
            ))
            tick.addLine(to: CGPoint(
                x: center.x + radius * CGFloat(sin(radians)),
                y: center.y - radius * CGFloat(cos(radians))
            ))
            context.stroke(tick, with: .color(tickColor), lineWidth: isCardinal ? 1.5 : 0.75)

            if !isCardinal {
                let degLabel = Text("\(Int(deg))°")
                    .font(.system(size: 8))
                    .foregroundColor(
                        colorScheme == .dark ? .white.opacity(0.3) : .black.opacity(0.25)
                    )
                context.draw(
                    context.resolve(degLabel),
                    at: CGPoint(
                        x: center.x + labelRadius * CGFloat(sin(radians)),
                        y: center.y - labelRadius * CGFloat(cos(radians))
                    ),
                    anchor: .center
                )
            }
        }
    }

    func drawCardinalLabels(
        context: GraphicsContext, center: CGPoint,
        labelRadius: CGFloat, cardinals: [(String, Double)]
    ) {
        for (label, bearing) in cardinals {
            let rotated = rotatedBearing(bearing)
            let radians = rotated * .pi / 180.0
            let x = center.x + labelRadius * CGFloat(sin(radians))
            let y = center.y - labelRadius * CGFloat(cos(radians))
            let color: Color = label == "N" ? .red : .secondary
            let text = Text(label)
                .font(.system(size: 11, weight: label == "N" ? .bold : .medium))
                .foregroundColor(color)
            context.draw(context.resolve(text), at: CGPoint(x: x, y: y), anchor: .center)
        }
    }

    func drawCrosshairLines(context: GraphicsContext, center: CGPoint, radius: CGFloat) {
        let lineColor = colorScheme == .dark
            ? Color.white.opacity(0.08)
            : Color.black.opacity(0.06)

        for bearing in [0.0, 90.0] {
            let radians = rotatedBearing(bearing) * .pi / 180.0
            var path = Path()
            path.move(to: CGPoint(
                x: center.x + radius * CGFloat(sin(radians)),
                y: center.y - radius * CGFloat(cos(radians))
            ))
            path.addLine(to: CGPoint(
                x: center.x - radius * CGFloat(sin(radians)),
                y: center.y + radius * CGFloat(cos(radians))
            ))
            context.stroke(path, with: .color(lineColor), lineWidth: 0.5)
        }
    }

    func drawSectorHeatmap(context: GraphicsContext, center: CGPoint, radius: CGFloat) {
        for sector in sectors where sector.density > 0 {
            let startAngle = Angle(degrees: rotatedBearing(sector.startBearing) - 90)
            let endAngle = Angle(degrees: rotatedBearing(sector.endBearing) - 90)
            let opacity = 0.08 + sector.density * 0.35

            var sectorPath = Path()
            sectorPath.move(to: center)
            sectorPath.addArc(
                center: center,
                radius: radius,
                startAngle: startAngle,
                endAngle: endAngle,
                clockwise: false
            )
            sectorPath.closeSubpath()

            context.fill(sectorPath, with: .color(Color.blue.opacity(opacity)))
        }
    }

    func drawAntennaPattern(
        context: GraphicsContext,
        center: CGPoint,
        radius: CGFloat,
        pattern: AntennaPattern
    ) {
        let points = pattern.polarPoints(steps: 72)
        let patternRadius = radius * 0.85 // Slightly inside the edge

        var path = Path()
        for (index, point) in points.enumerated() {
            let radians = point.angle * .pi / 180.0
            let pointRadius = CGFloat(point.radius) * patternRadius
            let x = center.x + pointRadius * CGFloat(sin(radians))
            let y = center.y - pointRadius * CGFloat(cos(radians))

            if index == 0 {
                path.move(to: CGPoint(x: x, y: y))
            } else {
                path.addLine(to: CGPoint(x: x, y: y))
            }
        }
        path.closeSubpath()

        // Fill with semi-transparent orange
        context.fill(path, with: .color(Color.orange.opacity(0.12)))
        // Stroke outline
        context.stroke(path, with: .color(Color.orange.opacity(0.6)), lineWidth: 1.5)
    }

    func drawSpotDots(context: GraphicsContext, center: CGPoint, radius: CGFloat) {
        for point in spotPoints {
            let pos = AzimuthalProjection.cartesian(
                from: AzimuthalPoint(
                    bearing: rotatedBearing(point.bearing),
                    distanceKm: point.distanceKm,
                    normalizedRadius: point.normalizedRadius
                ),
                centerX: Double(center.x),
                centerY: Double(center.y),
                viewRadius: Double(radius)
            )
            let dotColor = point.source?.color ?? .blue
            let dot = Path(ellipseIn: CGRect(x: pos.x - 2, y: pos.y - 2, width: 4, height: 4))
            context.fill(dot, with: .color(dotColor.opacity(0.7)))
        }
    }

    func drawQSODots(context: GraphicsContext, center: CGPoint, radius: CGFloat) {
        for point in qsoPoints {
            let pos = AzimuthalProjection.cartesian(
                from: AzimuthalPoint(
                    bearing: rotatedBearing(point.bearing),
                    distanceKm: point.distanceKm,
                    normalizedRadius: point.normalizedRadius
                ),
                centerX: Double(center.x),
                centerY: Double(center.y),
                viewRadius: Double(radius)
            )
            let dot = Path(ellipseIn: CGRect(x: pos.x - 3, y: pos.y - 3, width: 6, height: 6))
            context.fill(dot, with: .color(Color.green.opacity(0.8)))
            context.stroke(dot, with: .color(Color.green), lineWidth: 0.5)
        }
    }

    func drawCenterDot(context: GraphicsContext, center: CGPoint) {
        let dotSize: CGFloat = 6
        let dot = Path(ellipseIn: CGRect(
            x: center.x - dotSize / 2,
            y: center.y - dotSize / 2,
            width: dotSize,
            height: dotSize
        ))
        context.fill(dot, with: .color(.red))
    }
}
