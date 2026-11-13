//
//  FT8WaterfallView.swift
//  CarrierWave
//

import CarrierWaveData
import SwiftUI

// MARK: - FT8WaterfallView

struct FT8WaterfallView: View {
    // MARK: Internal

    let data: FT8WaterfallData

    /// Current cycle's decoded results (for channel highlighting).
    let currentDecodes: [FT8DecodeResult]

    var rxFrequency: Double = 1_500
    var txFrequency: Double = 1_500

    /// When true, the TX channel is highlighted as the active QSO channel.
    var isInQSO: Bool = false

    /// When true, the waterfall accepts taps to set TX frequency.
    var isInteractive: Bool = false

    /// Called when the user taps the waterfall to select a frequency (Hz).
    var onTapFrequency: ((Double) -> Void)?

    var body: some View {
        // Snapshot @MainActor data before entering Canvas rendering thread
        let frame = Frame(
            rows: data.magnitudes,
            bins: data.frequencyBins,
            minHz: data.minFrequency,
            maxHz: data.maxFrequency,
            decodes: currentDecodes.map {
                DecodeMarker(frequency: $0.frequency, snr: $0.snr, isCQ: $0.message.isCallable)
            },
            rxHz: rxFrequency,
            txHz: txFrequency,
            previewHz: dragPreview
        )

        VStack(spacing: 0) {
            spectrogramCanvas(frame: frame)
            frequencyAxis(minHz: frame.minHz, maxHz: frame.maxHz)
        }
    }

    // MARK: Fileprivate

    fileprivate struct DecodeMarker {
        let frequency: Double
        let snr: Int
        let isCQ: Bool
    }

    /// Snapshot of @MainActor data passed into the Canvas rendering thread.
    fileprivate struct Frame {
        let rows: [[Float]]
        let bins: Int
        let minHz: Float
        let maxHz: Float
        let decodes: [DecodeMarker]
        let rxHz: Double
        let txHz: Double
        let previewHz: Double?
    }

    /// Per-marker spec for `drawFrequencyMarker` — keeps that function
    /// under the 5-parameter linter budget.
    fileprivate struct MarkerSpec {
        let hz: Double
        let color: Color
    }

    fileprivate static let maxVisibleRows = 60
    fileprivate static let tickFrequencies: [Float] = [500, 1_000, 1_500, 2_000, 2_500]

    /// FT8 signal bandwidth is ~50 Hz (8 tones × 6.25 Hz spacing).
    fileprivate static let channelWidth: CGFloat = 50

    // MARK: Private

    @State private var dragPreview: Double?

    private func spectrogramCanvas(frame: Frame) -> some View {
        Canvas { context, size in
            drawChannelGrid(context: context, size: size, minHz: frame.minHz, maxHz: frame.maxHz)

            if !frame.rows.isEmpty, frame.bins > 0 {
                drawWaterfall(context: context, size: size, rows: frame.rows, bins: frame.bins)
            }

            drawChannelMarkers(
                context: context, size: size,
                decodes: frame.decodes, minHz: frame.minHz, maxHz: frame.maxHz
            )
            if isInQSO {
                drawActiveChannel(
                    context: context, size: size,
                    hz: frame.txHz, minHz: frame.minHz, maxHz: frame.maxHz
                )
            }
            drawFrequencyMarker(
                context: context, size: size,
                spec: MarkerSpec(hz: frame.rxHz, color: .green),
                minHz: frame.minHz, maxHz: frame.maxHz
            )
            drawFrequencyMarker(
                context: context, size: size,
                spec: MarkerSpec(hz: frame.txHz, color: .red),
                minHz: frame.minHz, maxHz: frame.maxHz
            )
            if let previewHz = frame.previewHz {
                drawDragPreview(
                    context: context, size: size,
                    hz: previewHz, minHz: frame.minHz, maxHz: frame.maxHz
                )
            }
        }
        .background(Color.black) // Intentional: spectrogram needs black canvas
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(
                    isInteractive ? Color.accentColor : Color.white.opacity(0.08),
                    lineWidth: isInteractive ? 2 : 0.5
                )
        }
        .contentShape(Rectangle())
        .overlay {
            if isInteractive {
                interactiveDragOverlay(minHz: frame.minHz, maxHz: frame.maxHz)
            }
        }
    }

    private func interactiveDragOverlay(minHz: Float, maxHz: Float) -> some View {
        GeometryReader { geo in
            Color.clear.contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            dragPreview = snappedFrequency(
                                xPos: value.location.x,
                                width: geo.size.width,
                                minHz: minHz, maxHz: maxHz
                            )
                        }
                        .onEnded { value in
                            let hz = snappedFrequency(
                                xPos: value.location.x,
                                width: geo.size.width,
                                minHz: minHz, maxHz: maxHz
                            )
                            dragPreview = nil
                            onTapFrequency?(hz)
                        }
                )
        }
    }

    private func frequencyAxis(minHz: Float, maxHz: Float) -> some View {
        GeometryReader { geo in
            let range = maxHz - minHz
            ZStack(alignment: .top) {
                ForEach(Self.tickFrequencies, id: \.self) { freq in
                    let fraction = CGFloat((freq - minHz) / range)
                    let xPos = fraction * geo.size.width
                    VStack(spacing: 1) {
                        Rectangle()
                            .fill(Color.secondary.opacity(0.7))
                            .frame(width: 1, height: 4)
                        Text("\(Int(freq))")
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    .position(x: xPos, y: geo.size.height / 2)
                }
            }
        }
        .frame(height: 18)
        .background(Color.black) // Intentional: matches spectrogram canvas
    }

    private func snappedFrequency(
        xPos: CGFloat, width: CGFloat,
        minHz: Float, maxHz: Float
    ) -> Double {
        guard width > 0 else {
            return Double(minHz)
        }
        let range = Double(maxHz - minHz)
        let fraction = max(0, min(1, xPos / width))
        let hz = Double(minHz) + range * fraction
        let snapped = (hz / 50).rounded() * 50
        return max(200, min(snapped, 2_800))
    }
}

// MARK: - Canvas Drawing

extension FT8WaterfallView {
    private func drawWaterfall(
        context: GraphicsContext,
        size: CGSize,
        rows: [[Float]],
        bins: Int
    ) {
        let visibleRows = Array(rows.suffix(Self.maxVisibleRows).reversed())
        // Fixed row height so new rows push older rows down pixel-by-pixel from the top
        // instead of stretching to fill the canvas while data is sparse.
        let rowHeight = size.height / CGFloat(Self.maxVisibleRows)
        let binWidth = size.width / CGFloat(bins)

        for (rowIdx, row) in visibleRows.enumerated() {
            for (binIdx, magnitude) in row.enumerated() {
                let rect = CGRect(
                    x: CGFloat(binIdx) * binWidth,
                    y: CGFloat(rowIdx) * rowHeight,
                    width: binWidth + 1,
                    height: rowHeight + 1
                )
                context.fill(
                    Path(rect),
                    with: .color(waterfallColor(magnitude))
                )
            }
        }
    }

    /// Faint vertical lines at every 50 Hz channel boundary so the user can
    /// see the FT8 channel grid that TX frequencies snap to.
    private func drawChannelGrid(
        context: GraphicsContext,
        size: CGSize,
        minHz: Float,
        maxHz: Float
    ) {
        let range = CGFloat(maxHz - minHz)
        guard range > 0 else {
            return
        }

        let step = Self.channelWidth // 50 Hz
        var hz = ceil(CGFloat(minHz) / step) * step
        let endHz = CGFloat(maxHz)
        while hz <= endHz {
            let fraction = (hz - CGFloat(minHz)) / range
            let xPos = fraction * size.width
            let line = CGRect(x: xPos, y: 0, width: 0.5, height: size.height)
            // Slightly brighter line every 250 Hz so the eye can count.
            let isMajor = Int(hz).isMultiple(of: 250)
            let opacity = isMajor ? 0.18 : 0.08
            context.fill(Path(line), with: .color(.white.opacity(opacity)))
            hz += step
        }
    }

    /// Highlights the 50 Hz channel containing the active QSO TX frequency.
    private func drawActiveChannel(
        context: GraphicsContext,
        size: CGSize,
        hz: Double,
        minHz: Float,
        maxHz: Float
    ) {
        let range = CGFloat(maxHz - minHz)
        guard range > 0 else {
            return
        }

        let centerFraction = CGFloat(Float(hz) - minHz) / range
        let centerX = centerFraction * size.width
        let halfWidth = (Self.channelWidth / range) * size.width / 2
        let rect = CGRect(
            x: centerX - halfWidth,
            y: 0,
            width: halfWidth * 2,
            height: size.height
        )
        context.fill(Path(rect), with: .color(.yellow.opacity(0.18)))

        let leftEdge = CGRect(x: rect.minX, y: 0, width: 1, height: size.height)
        let rightEdge = CGRect(x: rect.maxX - 1, y: 0, width: 1, height: size.height)
        context.fill(Path(leftEdge), with: .color(.yellow.opacity(0.7)))
        context.fill(Path(rightEdge), with: .color(.yellow.opacity(0.7)))
    }

    /// Draws decode markers, weighted by SNR so strong signals pop more than
    /// background noise-floor decodes.
    private func drawChannelMarkers(
        context: GraphicsContext,
        size: CGSize,
        decodes: [DecodeMarker],
        minHz: Float,
        maxHz: Float
    ) {
        let range = CGFloat(maxHz - minHz)
        guard range > 0 else {
            return
        }

        for decode in decodes {
            let centerFraction = CGFloat(Float(decode.frequency) - minHz) / range
            let halfWidth = (Self.channelWidth / range) * size.width / 2
            let centerX = centerFraction * size.width

            let markerRect = CGRect(
                x: centerX - halfWidth,
                y: 0,
                width: halfWidth * 2,
                height: size.height
            )

            // SNR -25..+10 dB → strength 0..1. Weight fill + edge by signal strength.
            let clampedSNR = max(-25, min(10, decode.snr))
            let strength = Double(clampedSNR + 25) / 35.0
            let fillOpacity = 0.10 + 0.20 * strength
            let edgeOpacity = 0.40 + 0.40 * strength

            let color: Color = decode.isCQ ? .green : .cyan
            context.fill(Path(markerRect), with: .color(color.opacity(fillOpacity)))

            let leftEdge = CGRect(x: markerRect.minX, y: 0, width: 1, height: size.height)
            let rightEdge = CGRect(x: markerRect.maxX - 1, y: 0, width: 1, height: size.height)
            context.fill(Path(leftEdge), with: .color(color.opacity(edgeOpacity)))
            context.fill(Path(rightEdge), with: .color(color.opacity(edgeOpacity)))
        }
    }

    /// Vertical TX/RX marker line. Labels were removed at user request —
    /// the colored vertical line is enough to locate the channel; the band
    /// row above the waterfall already shows the numeric TX frequency.
    private func drawFrequencyMarker(
        context: GraphicsContext,
        size: CGSize,
        spec: MarkerSpec,
        minHz: Float,
        maxHz: Float
    ) {
        let range = CGFloat(maxHz - minHz)
        guard range > 0 else {
            return
        }

        let fraction = CGFloat(Float(spec.hz) - minHz) / range
        let xPos = fraction * size.width
        let line = CGRect(x: xPos - 1, y: 0, width: 2, height: size.height)
        context.fill(Path(line), with: .color(spec.color.opacity(0.85)))
    }

    /// Live preview shown while the user is dragging in pick mode.
    /// Highlights the snapped 50 Hz channel and shows a Hz readout that
    /// tracks the finger position.
    private func drawDragPreview(
        context: GraphicsContext,
        size: CGSize,
        hz: Double,
        minHz: Float,
        maxHz: Float
    ) {
        let range = CGFloat(maxHz - minHz)
        guard range > 0 else {
            return
        }

        let centerFraction = CGFloat(Float(hz) - minHz) / range
        let centerX = centerFraction * size.width
        let halfWidth = (Self.channelWidth / range) * size.width / 2
        let rect = CGRect(
            x: centerX - halfWidth,
            y: 0,
            width: halfWidth * 2,
            height: size.height
        )

        // Snap-channel highlight + edges + center hairline
        context.fill(Path(rect), with: .color(.white.opacity(0.10)))
        let leftEdge = CGRect(x: rect.minX, y: 0, width: 1, height: size.height)
        let rightEdge = CGRect(x: rect.maxX - 1, y: 0, width: 1, height: size.height)
        context.fill(Path(leftEdge), with: .color(.white.opacity(0.6)))
        context.fill(Path(rightEdge), with: .color(.white.opacity(0.6)))
        let center = CGRect(x: centerX - 0.5, y: 0, width: 1, height: size.height)
        context.fill(Path(center), with: .color(.white.opacity(0.95)))

        // Frequency readout that tracks the finger
        let resolved = context.resolve(
            Text("\(Int(hz)) Hz")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(.white)
        )
        let textSize = resolved.measure(in: CGSize(width: 80, height: 20))
        let badgeWidth = textSize.width + 10
        let badgeHeight = textSize.height + 5
        let badgeX = max(4, min(size.width - badgeWidth - 4, centerX - badgeWidth / 2))
        let badgeRect = CGRect(x: badgeX, y: size.height - badgeHeight - 6, width: badgeWidth, height: badgeHeight)
        context.fill(
            Path(roundedRect: badgeRect, cornerRadius: 4),
            with: .color(.black.opacity(0.75))
        )
        context.stroke(
            Path(roundedRect: badgeRect, cornerRadius: 4),
            with: .color(.white.opacity(0.4)),
            lineWidth: 0.5
        )
        context.draw(resolved, at: CGPoint(x: badgeRect.midX, y: badgeRect.midY))
    }

    /// Inferno-inspired perceptual ramp: black → indigo → magenta → orange → yellow.
    /// Reads better than rainbow on dark UIs and makes strong signals "pop" white-hot.
    private func waterfallColor(_ magnitude: Float) -> Color {
        let value = max(0, min(1, Double(magnitude)))
        if value < 0.25 {
            let blend = value * 4
            return Color(red: 0.10 * blend, green: 0.0, blue: 0.30 * blend)
        } else if value < 0.50 {
            let blend = (value - 0.25) * 4
            return Color(
                red: 0.10 + 0.55 * blend,
                green: 0.0 + 0.10 * blend,
                blue: 0.30 + 0.10 * blend
            )
        } else if value < 0.75 {
            let blend = (value - 0.50) * 4
            return Color(
                red: 0.65 + 0.33 * blend,
                green: 0.10 + 0.40 * blend,
                blue: 0.40 - 0.30 * blend
            )
        } else {
            let blend = (value - 0.75) * 4
            return Color(
                red: 0.98 + 0.02 * blend,
                green: 0.50 + 0.45 * blend,
                blue: 0.10 + 0.40 * blend
            )
        }
    }
}
