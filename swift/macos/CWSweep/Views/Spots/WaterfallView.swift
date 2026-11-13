import SwiftUI

// MARK: - WaterfallView

/// Canvas-based waterfall display backed by `WaterfallStore`. Identical for
/// every radio source — the store hides which producer (SCU-LAN10, FlexRadio
/// VITA-49) is currently pushing lines.
///
/// Includes a spot overlay strip showing filtered spots from SpotAggregator
/// at their frequency positions above the waterfall.
struct WaterfallView: View {
    // MARK: Internal

    @Environment(SpotAggregator.self) var spotAggregator

    let store: WaterfallStore
    let radioManager: RadioManager

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                waterfallHeader
                bandSelector
                if store.magnitudes.isEmpty {
                    emptyState
                } else {
                    frequencyScale
                    spotOverlayStrip(width: geo.size.width)
                    waterfallCanvas(size: geo.size)
                }
            }
        }
    }

    // MARK: Private

    /// Fraction of total bins to display (0.0-1.0). Lower = more zoomed in.
    @State private var zoomLevel: Double = 1.0
    /// Pan offset as fraction of total bins (0.0 = left edge, 1.0 = right edge)
    @State private var panOffset: Double = 0.5

    @AppStorage("bandScopeColorMode") private var colorMode: BandScopeColorMode = .source
    @AppStorage("bandScopeMaxAgeMinutes") private var maxAgeMinutes: Int = 30
    @AppStorage("bandScopeStatusFilter") private var statusFilter: SpotStatusFilter = .all

    /// Scope span in kHz (total width of the spectrum display).
    private var scopeSpanKHz: Double {
        store.spanKHz > 0 ? store.spanKHz : 100
    }

    /// Center frequency in MHz used for axis labels and tap-to-tune.
    private var centerFrequencyMHz: Double {
        store.centerFrequencyMHz > 0 ? store.centerFrequencyMHz : radioManager.frequency
    }

    private var totalBins: Int {
        store.activeBinCount
    }

    private var visibleBins: Int {
        max(1, Int(Double(totalBins) * zoomLevel))
    }

    private var centerBin: Int {
        Int(Double(totalBins) * panOffset)
    }

    private var startBin: Int {
        max(0, centerBin - visibleBins / 2)
    }

    private var endBin: Int {
        min(totalBins, startBin + visibleBins)
    }

    /// VFO frequency bin (always the center of the scope data).
    private var vfoBin: Int {
        totalBins / 2
    }
}

// MARK: - Header & Band Selector

extension WaterfallView {
    private var waterfallHeader: some View {
        HStack(spacing: 6) {
            frequencyDisplay
            Spacer()
            zoomControls
            receivingIndicator
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.bar)
    }

    private var frequencyDisplay: some View {
        HStack(spacing: 4) {
            Image(systemName: "waveform")
                .foregroundStyle(.secondary)
            if radioManager.frequency > 0 {
                Text(formatFrequency(radioManager.frequency))
                    .fontDesign(.monospaced)
                Text(radioManager.mode)
                    .foregroundStyle(.secondary)
            } else {
                Text("No frequency")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.caption)
    }

    private var zoomControls: some View {
        HStack(spacing: 4) {
            Button("−", action: { zoomLevel = min(1.0, zoomLevel * 1.5) })
                .buttonStyle(.plain)
            Text("\(Int(zoomLevel * 100))%")
                .foregroundStyle(.tertiary)
                .frame(width: 32)
            Button("+", action: { zoomLevel = max(0.05, zoomLevel / 1.5) })
                .buttonStyle(.plain)
        }
        .font(.caption)
    }

    @ViewBuilder
    private var receivingIndicator: some View {
        if store.isReceiving {
            HStack(spacing: 4) {
                Text(store.source.label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Circle()
                    .fill(.green)
                    .frame(width: 6, height: 6)
            }
        }
    }

    private var bandSelector: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                ForEach(BandEdges.hfBands) { band in
                    bandButton(band)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
        }
        .background(.bar.opacity(0.7))
    }

    private func bandButton(_ band: BandEdge) -> some View {
        let freqKHz = radioManager.frequency * 1_000
        let isActive = freqKHz >= band.lowerKHz && freqKHz <= band.upperKHz
        return Button(band.label) {
            let centerKHz = (band.lowerKHz + band.upperKHz) / 2
            Task { await radioManager.tuneToFrequency(centerKHz / 1_000) }
        }
        .buttonStyle(.plain)
        .font(.caption2)
        .fontWeight(isActive ? .bold : .regular)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(isActive ? Color.accentColor.opacity(0.3) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 3))
    }
}

// MARK: - Frequency Scale

extension WaterfallView {
    private var frequencyScale: some View {
        Canvas { context, size in
            guard totalBins > 0, endBin > startBin else {
                return
            }
            drawFrequencyTicks(context: context, size: size)
        }
        .frame(height: 18)
        .background(Color(white: 0.08))
    }

    private func drawFrequencyTicks(
        context: GraphicsContext, size: CGSize
    ) {
        let displayBins = endBin - startBin
        let center = centerFrequencyMHz
        guard center > 0 else {
            return
        }

        // Compute frequency range of visible portion
        let binOffsetLow = startBin - vfoBin
        let binOffsetHigh = endBin - vfoBin
        let lowMHz = center + Double(binOffsetLow) / Double(totalBins) * scopeSpanKHz / 1_000
        let highMHz = center + Double(binOffsetHigh) / Double(totalBins) * scopeSpanKHz / 1_000
        let spanMHz = highMHz - lowMHz
        guard spanMHz > 0 else {
            return
        }

        // Choose tick interval based on visible span
        let tickIntervalMHz = chooseTickInterval(spanMHz)
        let firstTick = (lowMHz / tickIntervalMHz).rounded(.up) * tickIntervalMHz

        var freq = firstTick
        while freq < highMHz {
            let frac = (freq - lowMHz) / spanMHz
            let xPos = CGFloat(frac) * size.width
            drawTick(context: context, xPos: xPos, freqMHz: freq, size: size)
            freq += tickIntervalMHz
        }

        // VFO marker on scale
        let vfoFrac = CGFloat(vfoBin - startBin) / CGFloat(displayBins)
        let vfoX = vfoFrac * size.width
        if vfoX >= 0, vfoX <= size.width {
            var vfoPath = Path()
            vfoPath.move(to: CGPoint(x: vfoX, y: size.height - 4))
            vfoPath.addLine(to: CGPoint(x: vfoX - 3, y: size.height))
            vfoPath.addLine(to: CGPoint(x: vfoX + 3, y: size.height))
            vfoPath.closeSubpath()
            context.fill(vfoPath, with: .color(.red))
        }
    }

    private func drawTick(
        context: GraphicsContext, xPos: CGFloat, freqMHz: Double, size: CGSize
    ) {
        var tickPath = Path()
        tickPath.move(to: CGPoint(x: xPos, y: size.height - 3))
        tickPath.addLine(to: CGPoint(x: xPos, y: size.height))
        context.stroke(tickPath, with: .color(.gray), lineWidth: 0.5)

        let label = formatScaleLabel(freqMHz)
        let text = Text(label).font(.system(size: 8)).foregroundColor(.gray)
        context.draw(
            context.resolve(text),
            at: CGPoint(x: xPos, y: size.height / 2),
            anchor: .center
        )
    }

    private func chooseTickInterval(_ spanMHz: Double) -> Double {
        let spanKHz = spanMHz * 1_000
        if spanKHz > 100 {
            return 0.025
        } // 25 kHz ticks
        if spanKHz > 50 {
            return 0.010
        } // 10 kHz ticks
        if spanKHz > 20 {
            return 0.005
        } // 5 kHz ticks
        return 0.002 // 2 kHz ticks
    }

    private func formatScaleLabel(_ freqMHz: Double) -> String {
        let kHz = freqMHz * 1_000
        if kHz == kHz.rounded() {
            return String(format: "%.0f", kHz)
        }
        return String(format: "%.1f", kHz)
    }
}

// MARK: - Spot Overlay

extension WaterfallView {
    /// Visible frequency range in MHz based on current zoom/pan
    var visibleFrequencyRange: (lowMHz: Double, highMHz: Double)? {
        let center = centerFrequencyMHz
        guard center > 0, totalBins > 0, endBin > startBin else {
            return nil
        }
        let binOffsetLow = startBin - vfoBin
        let binOffsetHigh = endBin - vfoBin
        let low = center + Double(binOffsetLow) / Double(totalBins) * scopeSpanKHz / 1_000
        let high = center + Double(binOffsetHigh) / Double(totalBins) * scopeSpanKHz / 1_000
        return (low, high)
    }

    /// Filtered spots within the visible frequency range
    var visibleSpots: [EnrichedSpot] {
        guard let range = visibleFrequencyRange else {
            return []
        }
        let lowKHz = range.lowMHz * 1_000
        let highKHz = range.highMHz * 1_000
        let maxSeconds = Double(maxAgeMinutes) * 60
        return spotAggregator.spots.filter { spot in
            spot.spot.frequencyKHz >= lowKHz
                && spot.spot.frequencyKHz <= highKHz
                && statusFilter.matches(status: spot.neededStatus, isWorkedToday: false)
                && SpotAgeFactor.effectiveAge(for: spot) <= maxSeconds
        }
    }

    @ViewBuilder
    func spotOverlayStrip(width: CGFloat) -> some View {
        if let range = visibleFrequencyRange {
            WaterfallSpotOverlay(
                spots: visibleSpots,
                lowFreqMHz: range.lowMHz,
                highFreqMHz: range.highMHz,
                colorMode: colorMode,
                maxAgeMinutes: maxAgeMinutes
            )
        }
    }
}

// MARK: - Waterfall Canvas

extension WaterfallView {
    private func waterfallCanvas(size: CGSize) -> some View {
        Canvas { context, canvasSize in
            let lines = store.magnitudes
            guard !lines.isEmpty, endBin > startBin else {
                return
            }
            drawSpectrumLines(
                context: context, canvasSize: canvasSize, lines: lines
            )
            drawSpotTickMarks(context: context, canvasSize: canvasSize)
            drawVFOMarker(context: context, canvasSize: canvasSize)
        }
        .background(.black)
        .gesture(
            DragGesture()
                .onChanged { drag in
                    let pctDelta = drag.translation.width / size.width * zoomLevel
                    panOffset = max(0, min(1, panOffset - pctDelta * 0.01))
                }
        )
        .onTapGesture { location in
            handleTap(at: location, canvasWidth: size.width)
        }
    }

    /// Draws the visible lines as one bitmap. Filling one rect per bin was
    /// ~95k fills per redraw at 200 lines x 475 bins, redrawn for every scope
    /// line (IC-9700 over LAN: ~90% of a core); one image per redraw is cheap.
    private func drawSpectrumLines(
        context: GraphicsContext,
        canvasSize: CGSize,
        lines: [[Float]]
    ) {
        let displayBins = endBin - startBin
        let lineHeight = max(1.0, canvasSize.height / CGFloat(store.maxLines))
        let rows = min(lines.count, Int(ceil(canvasSize.height / lineHeight)))
        guard displayBins > 0, rows > 0,
              let image = Self.waterfallImage(lines: lines.prefix(rows), startBin: startBin, width: displayBins)
        else {
            return
        }
        let rect = CGRect(x: 0, y: 0, width: canvasSize.width, height: CGFloat(rows) * lineHeight)
        context.draw(Image(decorative: image, scale: 1).interpolation(.none), in: rect)
    }

    /// One pixel per bin, one row per line (newest at the top). Bins past the
    /// end of a short line use the floor color.
    private static func waterfallImage(
        lines: ArraySlice<[Float]>,
        startBin: Int,
        width: Int
    ) -> CGImage? {
        let height = lines.count
        var pixels = [UInt32](repeating: waterfallPalette[0], count: width * height)
        for (row, line) in lines.enumerated() {
            let rowStart = row * width
            let available = min(width, max(0, line.count - startBin))
            for col in 0 ..< available {
                let value = min(1, max(0, line[startBin + col]))
                pixels[rowStart + col] = waterfallPalette[Int(value * 255)]
            }
        }
        let data = pixels.withUnsafeBufferPointer { Data(buffer: $0) }
        guard let provider = CGDataProvider(data: data as CFData) else {
            return nil
        }
        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue)
                .union(.byteOrder32Big),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )
    }

    /// Draw small tick marks at the top of the waterfall for each visible spot
    private func drawSpotTickMarks(
        context: GraphicsContext, canvasSize: CGSize
    ) {
        guard let range = visibleFrequencyRange else {
            return
        }
        let span = range.highMHz - range.lowMHz
        guard span > 0 else {
            return
        }

        for spot in visibleSpots {
            let frac = (spot.spot.frequencyMHz - range.lowMHz) / span
            let xPos = CGFloat(frac) * canvasSize.width
            let color = SpotColorScheme.markerColor(for: spot, mode: colorMode, isWorkedToday: false)
            let opacity = SpotAgeFactor.opacity(for: spot, maxAgeMinutes: maxAgeMinutes)

            var tick = Path()
            tick.move(to: CGPoint(x: xPos, y: 0))
            tick.addLine(to: CGPoint(x: xPos, y: 4))
            context.stroke(tick, with: .color(color.opacity(opacity * 0.8)), lineWidth: 1)
        }
    }

    private func drawVFOMarker(
        context: GraphicsContext, canvasSize: CGSize
    ) {
        let displayBins = endBin - startBin
        guard displayBins > 0 else {
            return
        }

        let vfoFrac = CGFloat(vfoBin - startBin) / CGFloat(displayBins)
        let vfoX = vfoFrac * canvasSize.width

        // Only draw if VFO position is within visible range
        guard vfoX >= 0, vfoX <= canvasSize.width else {
            return
        }

        var markerPath = Path()
        markerPath.move(to: CGPoint(x: vfoX, y: 0))
        markerPath.addLine(to: CGPoint(x: vfoX, y: canvasSize.height))
        context.stroke(
            markerPath, with: .color(.red.opacity(0.7)), lineWidth: 1
        )
    }
}

// MARK: - Interaction

extension WaterfallView {
    @MainActor
    private func handleTap(
        at location: NSPoint, canvasWidth: CGFloat
    ) {
        guard totalBins > 0, endBin > startBin else {
            return
        }

        let displayBins = endBin - startBin
        let clickedBin = startBin + Int(location.x / canvasWidth * CGFloat(displayBins))
        let binOffset = clickedBin - vfoBin
        let freqOffsetMHz = Double(binOffset) / Double(totalBins) * scopeSpanKHz / 1_000.0
        let newFreq = centerFrequencyMHz + freqOffsetMHz

        guard newFreq > 0.1, newFreq < 60.0 else {
            return
        }
        Task { await radioManager.tuneToFrequency(newFreq) }
    }
}

// MARK: - Helpers

extension WaterfallView {
    private var emptyState: some View {
        VStack {
            Spacer()
            Text("No scope data")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black)
    }

    private func formatFrequency(_ mhz: Double) -> String {
        String(format: "%.3f MHz", mhz)
    }

    /// Magnitude (0...1) -> RGB, the waterfall's color ramp.
    private static func waterfallRGB(for magnitude: Double) -> (Double, Double, Double) {
        let val = min(1.0, max(0.0, magnitude))
        if val < 0.05 {
            return (0, 0, 0.08)
        } else if val < 0.15 {
            let frac = (val - 0.05) / 0.1
            return (0, 0, 0.08 + frac * 0.25)
        } else if val < 0.35 {
            let frac = (val - 0.15) / 0.2
            return (0, frac * 0.4, 0.33 + frac * 0.3)
        } else if val < 0.55 {
            let frac = (val - 0.35) / 0.2
            return (0, 0.4 + frac * 0.6, 0.63 - frac * 0.3)
        } else if val < 0.75 {
            let frac = (val - 0.55) / 0.2
            return (frac * 0.8, 1.0, 0.33 - frac * 0.33)
        } else if val < 0.9 {
            let frac = (val - 0.75) / 0.15
            return (0.8 + frac * 0.2, 1.0 - frac * 0.5, 0)
        } else {
            let frac = (val - 0.9) / 0.1
            return (1.0, 0.5 - frac * 0.3, frac * 0.5)
        }
    }

    /// 256-step lookup of the ramp as big-endian RGBX pixels.
    private static let waterfallPalette: [UInt32] = (0 ... 255).map { step in
        let (red, green, blue) = waterfallRGB(for: Double(step) / 255)
        let byte = { (component: Double) in UInt32((component * 255).rounded()) }
        return (byte(red) << 24 | byte(green) << 16 | byte(blue) << 8 | 0xFF).bigEndian
    }
}
