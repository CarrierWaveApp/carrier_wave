import AppKit
import CoreGraphics
import SwiftUI

// MARK: - SatelliteWaterfallBuffer

/// Ring buffer of synthetic waterfall lines (newest last) plus the bitmap
/// the Canvas blits. One line is appended every ~150 ms from the view's
/// `.task`; the latest frame / presentation are mirrored in here so the
/// loop always synthesizes against current Doppler.
@MainActor
@Observable
final class SatelliteWaterfallBuffer {
    // MARK: Internal

    static let capacity = 120
    static let bins = SatelliteWaterfallSynth.defaultBins

    private(set) var lines: [SatelliteWaterfallSynth.Line] = []
    private(set) var image: CGImage?

    var frame = SatellitePassFrame(now: Date())
    var corrected = true

    var newestLine: SatelliteWaterfallSynth.Line? {
        lines.last
    }

    /// Passband centre for the current presentation (nil = nothing to show).
    var centerHz: Double? {
        guard let doppler = frame.doppler else {
            return nil
        }
        return corrected ? doppler.correctedDownlinkHz : doppler.nominalDownlinkHz
    }

    /// Synthesize one line and rebuild the bitmap.
    func tick() {
        seed &+= 1
        let strength = frame.look?.isAboveHorizon == true ? frame.signalStrength : 0
        let line = SatelliteWaterfallSynth.line(
            centerHz: centerHz ?? 0,
            signalHz: frame.doppler?.correctedDownlinkHz,
            widthHz: SatelliteWaterfallSynth.signalWidthHz(mode: frame.transmitter?.kind ?? .fm),
            strength: strength,
            bins: Self.bins,
            seed: seed
        )
        lines.append(line)
        if lines.count > Self.capacity {
            lines.removeFirst(lines.count - Self.capacity)
        }
        image = Self.render(lines)
    }

    // MARK: Private

    /// RGBA bytes for `SatelliteTheme.waterfallLUT`, resolved once.
    private static let lutRGBA: [UInt8] = {
        var bytes = [UInt8](repeating: 255, count: 256 * 4)
        for (index, color) in SatelliteTheme.waterfallLUT.enumerated() {
            let resolved = NSColor(color).usingColorSpace(.sRGB) ?? NSColor(color)
            bytes[index * 4] = UInt8(max(0, min(255, (resolved.redComponent * 255).rounded())))
            bytes[index * 4 + 1] = UInt8(max(0, min(255, (resolved.greenComponent * 255).rounded())))
            bytes[index * 4 + 2] = UInt8(max(0, min(255, (resolved.blueComponent * 255).rounded())))
        }
        return bytes
    }()

    private var seed: UInt64 = 0

    /// Newest line on the top row; every cell is the LUT colour for its
    /// magnitude. Built as a bitmap so the Canvas draws one image instead
    /// of 512 × 120 rectangles per repaint.
    private static func render(_ lines: [SatelliteWaterfallSynth.Line]) -> CGImage? {
        guard !lines.isEmpty else {
            return nil
        }
        let width = bins
        let height = lines.count
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let lut = lutRGBA
        for (row, line) in lines.reversed().enumerated() {
            let rowBase = row * width * 4
            let count = min(width, line.magnitudes.count)
            for bin in 0 ..< count {
                let index = Int(min(max(line.magnitudes[bin], 0), 1) * 255) * 4
                let offset = rowBase + bin * 4
                pixels[offset] = lut[index]
                pixels[offset + 1] = lut[index + 1]
                pixels[offset + 2] = lut[index + 2]
                pixels[offset + 3] = 255
            }
        }
        guard let provider = CGDataProvider(data: Data(pixels) as CFData),
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)
        else {
            return nil
        }
        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )
    }
}

// MARK: - SatelliteWaterfallView

/// Full-width synthetic waterfall: noise floor plus the Doppler-shifted
/// downlink. "Corrected" centres the passband on the corrected downlink so
/// the signal stays put; "Uncorrected" centres on the nominal downlink so
/// the signal drifts across the display. Not fed by `WaterfallStore` by
/// design — this is a teaching display, not an SDR.
struct SatelliteWaterfallView: View {
    // MARK: Internal

    let frame: SatellitePassFrame
    let corrected: Bool

    var body: some View {
        VStack(spacing: 0) {
            waterfall
            scale
                .frame(height: 16)
            legend
                .frame(height: 18)
        }
        .padding(.horizontal, 12)
        .padding(.top, 6)
        .padding(.bottom, 4)
        .background(SatelliteTheme.background)
        .onChange(of: frame, initial: true) { _, newFrame in
            buffer.frame = newFrame
        }
        .onChange(of: corrected, initial: true) { _, newValue in
            buffer.corrected = newValue
        }
        .task {
            while !Task.isCancelled {
                buffer.tick()
                try? await Task.sleep(for: Self.lineInterval)
            }
        }
    }

    // MARK: Private

    private static let lineInterval: Duration = .milliseconds(150)

    @State private var buffer = SatelliteWaterfallBuffer()

    private var waterfall: some View {
        Canvas(rendersAsynchronously: false) { context, size in
            guard let image = buffer.image else {
                return
            }
            // Newest line at the top; rows fill downward until the buffer is full.
            let rowHeight = size.height / CGFloat(SatelliteWaterfallBuffer.capacity)
            let drawnHeight = rowHeight * CGFloat(image.height)
            let target = CGRect(x: 0, y: 0, width: size.width, height: drawnHeight)
            context.draw(Image(decorative: image, scale: 1).interpolation(.none), in: target)
            drawRigMarker(context: context, size: size)
        }
        .background(SatelliteTheme.background)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(SatelliteTheme.hairline, lineWidth: 1)
        )
        .overlay {
            if frame.doppler == nil {
                Text("Select a pass to see the downlink")
                    .font(SatelliteTheme.label(11))
                    .foregroundStyle(SatelliteTheme.textTertiary)
            }
        }
    }

    private var scale: some View {
        Canvas(rendersAsynchronously: false) { context, size in
            guard let center = buffer.centerHz else {
                return
            }
            let span = SatelliteWaterfallSynth.halfSpanHz * 2
            let tickCount = 5
            for index in 0 ..< tickCount {
                let fraction = CGFloat(index) / CGFloat(tickCount - 1)
                let tickX = fraction * size.width
                let tickHz = center - SatelliteWaterfallSynth.halfSpanHz + Double(fraction) * span
                var tick = Path()
                tick.move(to: CGPoint(x: tickX, y: 0))
                tick.addLine(to: CGPoint(x: tickX, y: 4))
                context.stroke(tick, with: .color(SatelliteTheme.gridLine), lineWidth: 1)
                let anchor: UnitPoint = index == 0 ? .topLeading : (index == tickCount - 1 ? .topTrailing : .top)
                context.draw(
                    Text(SatellitePassFormat.mhzTick(tickHz))
                        .font(SatelliteTheme.mono(9))
                        .foregroundStyle(
                            index == tickCount / 2 ? SatelliteTheme.textPrimary : SatelliteTheme.textSecondary
                        ),
                    at: CGPoint(x: tickX, y: 5),
                    anchor: anchor
                )
            }
        }
    }

    private var legend: some View {
        HStack(spacing: 10) {
            Text("±25 kHz")
                .foregroundStyle(SatelliteTheme.textTertiary)
            Text(corrected ? "Corrected (signal stays put)" : "Uncorrected (signal drifts)")
                .foregroundStyle(corrected ? SatelliteTheme.rx : SatelliteTheme.satellite)
            Spacer()
            if let doppler = frame.doppler {
                Text("Signal \(SatellitePassFormat.mhz(doppler.correctedDownlinkHz)) · \(frame.sMeterLabel)")
                    .foregroundStyle(SatelliteTheme.textSecondary)
            }
        }
        .font(SatelliteTheme.mono(10))
    }

    private func drawRigMarker(context: GraphicsContext, size: CGSize) {
        guard let line = buffer.newestLine, let doppler = frame.doppler else {
            return
        }
        let markerHz = frame.rigFrequencyHz ?? doppler.correctedDownlinkHz
        guard let bin = SatelliteWaterfallSynth.bin(for: markerHz, in: line) else {
            return
        }
        let markerX = CGFloat(bin / Double(line.magnitudes.count)) * size.width
        var marker = Path()
        marker.move(to: CGPoint(x: markerX, y: 0))
        marker.addLine(to: CGPoint(x: markerX, y: size.height))
        context.stroke(
            marker,
            with: .color(SatelliteTheme.nearWhite.opacity(0.85)),
            style: StrokeStyle(lineWidth: 1, dash: [4, 3])
        )
        let label = frame.rigFrequencyHz == nil ? "DL" : "RIG"
        context.draw(
            Text(label).font(SatelliteTheme.label(8, weight: .bold)).foregroundStyle(SatelliteTheme.nearWhite),
            at: CGPoint(x: markerX, y: 7)
        )
    }
}
