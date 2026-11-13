import SwiftUI

// MARK: - Mini-Map Rail

extension ContestBandScopeView {
    /// 38pt left rail showing the full band with spot density and viewport rectangle
    func miniMapRail(height: CGFloat) -> some View {
        Canvas { context, canvasSize in
            guard let band = selectedBand else {
                return
            }

            // Background
            context.fill(
                Path(CGRect(origin: .zero, size: canvasSize)),
                with: .color(Color(nsColor: .controlBackgroundColor).opacity(0.3))
            )

            drawMiniMapLabels(ctx: context, size: canvasSize, band: band)

            let plotTop: CGFloat = 16
            let plotBottom = canvasSize.height - 16
            let plotHeight = plotBottom - plotTop

            drawMiniMapSpots(ctx: context, size: canvasSize, band: band,
                             plotTop: plotTop, plotHeight: plotHeight)
            drawMiniMapViewport(ctx: context, size: canvasSize,
                                plotTop: plotTop, plotHeight: plotHeight)
            drawMiniMapVFO(ctx: context, size: canvasSize, band: band,
                           plotTop: plotTop, plotHeight: plotHeight)
            drawMiniMapBookmarks(ctx: context, size: canvasSize, band: band,
                                 plotTop: plotTop, plotHeight: plotHeight)
        }
        .frame(width: Self.miniMapWidth)
    }

    private func drawMiniMapLabels(
        ctx: GraphicsContext, size: CGSize, band: BandEdge
    ) {
        let topLabel = Text(String(format: "%.0f", band.lowerKHz))
            .font(.system(size: 7, weight: .semibold, design: .monospaced))
            .foregroundStyle(.tertiary)
        ctx.draw(ctx.resolve(topLabel),
                 at: CGPoint(x: size.width / 2, y: 8),
                 anchor: .center)

        let bottomLabel = Text(String(format: "%.0f", band.upperKHz))
            .font(.system(size: 7, weight: .semibold, design: .monospaced))
            .foregroundStyle(.tertiary)
        ctx.draw(ctx.resolve(bottomLabel),
                 at: CGPoint(x: size.width / 2, y: size.height - 8),
                 anchor: .center)
    }

    private func drawMiniMapSpots(
        ctx: GraphicsContext, size: CGSize, band: BandEdge,
        plotTop: CGFloat, plotHeight: CGFloat
    ) {
        for spot in spotsOnBand {
            let frac = (spot.spot.frequencyKHz - band.lowerKHz) / band.widthKHz
            let yPosition = plotTop + frac * plotHeight
            let isMult = spot.neededStatus == .newEntity || spot.neededStatus == .newBandSlot
            let color: Color = isMult
                ? Color(nsColor: .systemGreen)
                : Color(nsColor: .systemBlue)
            let dotHeight: CGFloat = isMult ? 3 : 2

            let rect = CGRect(
                x: size.width / 2 - 5,
                y: yPosition - dotHeight / 2,
                width: 10,
                height: dotHeight
            )
            ctx.fill(Path(rect), with: .color(color.opacity(isMult ? 1.0 : 0.6)))
        }
    }

    private func drawMiniMapViewport(
        ctx: GraphicsContext, size: CGSize,
        plotTop: CGFloat, plotHeight: CGFloat
    ) {
        guard zoomScale > 1.01 else {
            return
        }
        let visibleHeight = 1.0 / zoomScale
        let visibleStart = panOffset - visibleHeight / 2
        let vpTop = plotTop + visibleStart * plotHeight
        let vpHeight = visibleHeight * plotHeight

        let vpRect = CGRect(
            x: 4, y: vpTop,
            width: size.width - 8, height: vpHeight
        )
        ctx.stroke(
            Path(roundedRect: vpRect, cornerRadius: 3),
            with: .color(Color(nsColor: .systemBlue)),
            lineWidth: 1.5
        )
        ctx.fill(
            Path(roundedRect: vpRect, cornerRadius: 3),
            with: .color(Color(nsColor: .systemBlue).opacity(0.08))
        )
    }

    private func drawMiniMapVFO(
        ctx: GraphicsContext, size: CGSize, band: BandEdge,
        plotTop: CGFloat, plotHeight: CGFloat
    ) {
        let radioFreqKHz = radioManager.frequency * 1_000
        guard radioFreqKHz >= band.lowerKHz, radioFreqKHz <= band.upperKHz else {
            return
        }
        let vfoFrac = (radioFreqKHz - band.lowerKHz) / band.widthKHz
        let vfoY = plotTop + vfoFrac * plotHeight

        var vfoLine = Path()
        vfoLine.move(to: CGPoint(x: 4, y: vfoY))
        vfoLine.addLine(to: CGPoint(x: size.width - 4, y: vfoY))
        ctx.stroke(
            vfoLine,
            with: .color(Color(nsColor: .systemRed)),
            lineWidth: 1.5
        )
    }

    private func drawMiniMapBookmarks(
        ctx: GraphicsContext, size: CGSize, band: BandEdge,
        plotTop: CGFloat, plotHeight: CGFloat
    ) {
        for bookmark in bookmarksOnBand {
            let frac = (bookmark.frequencyKHz - band.lowerKHz) / band.widthKHz
            let yPosition = plotTop + frac * plotHeight
            var line = Path()
            line.move(to: CGPoint(x: 4, y: yPosition))
            line.addLine(to: CGPoint(x: size.width - 4, y: yPosition))
            ctx.stroke(
                line,
                with: .color(Color(nsColor: .systemOrange).opacity(0.6)),
                lineWidth: 1
            )
        }
    }
}

// MARK: - Cursor Crosshair

extension ContestBandScopeView {
    func cursorCrosshair(at location: CGPoint, size: CGSize) -> some View {
        Canvas { context, _ in
            // Horizontal dashed line at cursor Y
            var line = Path()
            line.move(to: CGPoint(x: 0, y: location.y))
            line.addLine(to: CGPoint(x: size.width, y: location.y))
            context.stroke(
                line,
                with: .color(Color(nsColor: .systemBlue).opacity(0.5)),
                style: StrokeStyle(lineWidth: 1, dash: [4, 3])
            )

            // Small dot at cursor position
            let dot = Path(
                ellipseIn: CGRect(
                    x: location.x - 3, y: location.y - 3,
                    width: 6, height: 6
                )
            )
            context.fill(dot, with: .color(Color(nsColor: .systemBlue)))
        }
        .allowsHitTesting(false)
    }
}
