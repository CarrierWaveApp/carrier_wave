//
//  FT8WaterfallView.swift
//  CarrierWave
//

import CarrierWaveData
import SwiftUI

struct FT8WaterfallView: View {
    // MARK: Internal

    let data: FT8WaterfallData

    /// Current cycle's decoded results (for channel highlighting).
    let currentDecodes: [FT8DecodeResult]

    var rxFrequency: Double = 1_500
    var txFrequency: Double = 1_500

    /// When true, the waterfall accepts taps to set TX frequency.
    var isInteractive: Bool = false

    /// Called when the user taps the waterfall to select a frequency (Hz).
    var onTapFrequency: ((Double) -> Void)?

    var body: some View {
        // Snapshot @MainActor data before entering Canvas rendering thread
        let rows = data.magnitudes
        let bins = data.frequencyBins
        let minHz = data.minFrequency
        let maxHz = data.maxFrequency
        let decodeFreqs = currentDecodes.map { DecodeMarker(frequency: $0.frequency, isCQ: $0.message.isCallable) }
        let rxHz = rxFrequency
        let txHz = txFrequency

        VStack(spacing: 0) {
            Canvas { context, size in
                guard !rows.isEmpty, bins > 0 else {
                    return
                }

                drawWaterfall(context: context, size: size, rows: rows, bins: bins)
                drawChannelMarkers(
                    context: context,
                    size: size,
                    decodes: decodeFreqs,
                    minHz: minHz,
                    maxHz: maxHz
                )
                drawFrequencyMarker(
                    context: context, size: size,
                    hz: rxHz, color: .green, minHz: minHz
                )
                drawFrequencyMarker(
                    context: context, size: size,
                    hz: txHz, color: .red, minHz: minHz
                )
            }
            .background(Color.black)
            .overlay {
                if isInteractive {
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.accentColor, lineWidth: 2)
                }
            }
            .contentShape(Rectangle())
            .overlay {
                if isInteractive {
                    GeometryReader { geo in
                        Color.clear.contentShape(Rectangle())
                            .gesture(
                                DragGesture(minimumDistance: 0)
                                    .onEnded { value in
                                        tapToFrequency(
                                            x: value.location.x,
                                            width: geo.size.width,
                                            minHz: minHz,
                                            maxHz: maxHz
                                        )
                                    }
                            )
                    }
                }
            }

            frequencyAxis(minHz: minHz, maxHz: maxHz)
        }
    }

    // MARK: Private

    private struct DecodeMarker {
        let frequency: Double
        let isCQ: Bool
    }

    private static let maxVisibleRows = 60
    private static let tickFrequencies: [Float] = [500, 1_000, 1_500, 2_000, 2_500]

    /// FT8 signal bandwidth is ~50 Hz (8 tones × 6.25 Hz spacing).
    private static let channelWidth: CGFloat = 50

    private func frequencyAxis(minHz: Float, maxHz: Float) -> some View {
        GeometryReader { geo in
            let range = maxHz - minHz
            ZStack(alignment: .top) {
                ForEach(Self.tickFrequencies, id: \.self) { freq in
                    let fraction = CGFloat((freq - minHz) / range)
                    let xPos = fraction * geo.size.width
                    VStack(spacing: 1) {
                        Rectangle()
                            .fill(Color.secondary)
                            .frame(width: 1, height: 4)
                        Text("\(Int(freq))")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    .position(x: xPos, y: geo.size.height / 2)
                }
            }
        }
        .frame(height: 18)
        .background(Color.black)
    }

    private func drawWaterfall(
        context: GraphicsContext,
        size: CGSize,
        rows: [[Float]],
        bins: Int
    ) {
        let visibleRows = Array(rows.suffix(Self.maxVisibleRows).reversed())
        let rowHeight = size.height / CGFloat(min(visibleRows.count, Self.maxVisibleRows))
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
            let halfWidth = (Self.channelWidth / CGFloat(maxHz - minHz)) * size.width / 2
            let centerX = centerFraction * size.width

            let markerRect = CGRect(
                x: centerX - halfWidth,
                y: 0,
                width: halfWidth * 2,
                height: size.height
            )

            let color: Color = decode.isCQ ? .green : .cyan
            context.fill(Path(markerRect), with: .color(color.opacity(0.2)))

            // Thin edge lines
            let leftEdge = CGRect(x: markerRect.minX, y: 0, width: 1, height: size.height)
            let rightEdge = CGRect(x: markerRect.maxX - 1, y: 0, width: 1, height: size.height)
            context.fill(Path(leftEdge), with: .color(color.opacity(0.5)))
            context.fill(Path(rightEdge), with: .color(color.opacity(0.5)))
        }
    }

    private func drawFrequencyMarker(
        context: GraphicsContext,
        size: CGSize,
        hz: Double,
        color: Color,
        minHz: Float
    ) {
        let range = CGFloat(data.maxFrequency - minHz)
        guard range > 0 else {
            return
        }

        let fraction = CGFloat(Float(hz) - minHz) / range
        let x = fraction * size.width
        let line = CGRect(x: x - 1, y: 0, width: 2, height: size.height)
        context.fill(Path(line), with: .color(color.opacity(0.8)))
    }

    private func tapToFrequency(
        x: CGFloat,
        width: CGFloat,
        minHz: Float,
        maxHz: Float
    ) {
        guard let onTapFrequency, width > 0 else {
            return
        }
        let range = Double(maxHz - minHz)
        let fraction = max(0, min(1, x / width))
        let hz = Double(minHz) + range * fraction
        let snapped = (hz / 50).rounded() * 50
        let clamped = max(200, min(snapped, 2_800))
        onTapFrequency(clamped)
    }

    private func waterfallColor(_ magnitude: Float) -> Color {
        let value = Double(magnitude)
        if value < 0.25 {
            return Color(red: 0, green: 0, blue: value * 4)
        } else if value < 0.5 {
            let blend = (value - 0.25) * 4
            return Color(red: 0, green: blend, blue: 1.0 - blend)
        } else if value < 0.75 {
            let blend = (value - 0.5) * 4
            return Color(red: blend, green: 1.0, blue: 0)
        } else {
            let blend = (value - 0.75) * 4
            return Color(red: 1.0, green: 1.0 - blend, blue: 0)
        }
    }
}
