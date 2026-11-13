import CarrierWaveCore
import SwiftUI

// MARK: - RemoteSweepWaterfallView

//
// Live waterfall mirror. Each received line is pre-rendered to a 1px-tall
// image and registered to the center/span it was captured at; the canvas
// blits every line into the current display window, so pans, pinches, and
// server re-spans all slide smoothly instead of lurching. Pinch zoom asks
// k3fall servers to re-span the stream server-side (full FFT resolution);
// against classic Sweep the same gesture falls back to client-side scaling.
//

struct RemoteSweepWaterfallView: View {
    // MARK: Internal

    @Environment(RemoteSweepCoordinator.self) var coordinator

    var body: some View {
        VStack(spacing: 0) {
            header
            if coordinator.waterfallLines.isEmpty {
                emptyState
            } else {
                spectrumCanvas
            }
        }
        .task {
            await coordinator.subscribeWaterfall()
        }
        .onDisappear {
            Task { await coordinator.unsubscribeWaterfall() }
        }
    }

    // MARK: Private

    private static let liveTuneInterval: Duration = .milliseconds(150)
    private static let minSpanHz: Double = 1_000
    private static let maxSpanHz: Double = 1_000_000

    @State private var dragOffsetX: CGFloat = 0
    @State private var dragAnchorFreqHz: UInt64?
    @State private var lastTuneSentAt: ContinuousClock.Instant?
    @State private var lastTuneSentTarget: UInt64?
    @State private var trailingTuneTask: Task<Void, Never>?
    @State private var canvasSize: CGSize = .zero
    /// Span the user wants on screen (nil = follow the stream's span).
    @State private var targetSpanHz: Double?
    /// Display span captured when the current pinch began.
    @State private var pinchBaseSpanHz: Double?
    @State private var isPinching = false

    /// Span currently rendered. The stream's own span is the fallback, so
    /// server-side re-spans take over seamlessly once they arrive.
    private var displaySpanHz: Double {
        targetSpanHz ?? max(coordinator.waterfallSpanKHz * 1_000, 1)
    }

    /// Center currently rendered: mid-drag it tracks the finger so history
    /// slides continuously; otherwise it follows the radio.
    private var displayCenterHz: Double {
        if let anchor = dragAnchorFreqHz, canvasSize.width > 0 {
            return Double(anchor) - Double(dragOffsetX) / Double(canvasSize.width) * displaySpanHz
        }
        return coordinator.waterfallCenterMHz * 1_000_000
    }

    private var magnifyGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                isPinching = true
                if pinchBaseSpanHz == nil {
                    pinchBaseSpanHz = displaySpanHz
                }
                if let base = pinchBaseSpanHz {
                    targetSpanHz = min(Self.maxSpanHz, max(Self.minSpanHz, base / Double(value)))
                }
            }
            .onEnded { _ in
                pinchBaseSpanHz = nil
                isPinching = false
                if let span = targetSpanHz {
                    Task { await coordinator.requestWaterfallSpan(hz: UInt64(span)) }
                }
            }
    }

    private var panGesture: some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                guard !isPinching else {
                    return
                }
                if dragAnchorFreqHz == nil {
                    dragAnchorFreqHz = UInt64(coordinator.waterfallCenterMHz * 1_000_000)
                }
                dragOffsetX = value.translation.width
                scheduleLiveTune()
            }
            .onEnded { value in
                let finalTarget = panTarget(
                    anchorFreqHz: dragAnchorFreqHz,
                    dragPixels: value.translation.width
                )
                trailingTuneTask?.cancel()
                trailingTuneTask = nil
                if let finalTarget, finalTarget != lastTuneSentTarget {
                    Task { await coordinator.tune(freqHz: finalTarget) }
                }
                dragOffsetX = 0
                dragAnchorFreqHz = nil
                lastTuneSentAt = nil
                lastTuneSentTarget = nil
            }
    }

    private var pendingPanTargetHz: UInt64? {
        guard dragOffsetX != 0 else {
            return nil
        }
        return panTarget(anchorFreqHz: dragAnchorFreqHz, dragPixels: dragOffsetX)
    }

    private var headerTitle: String {
        if coordinator.waterfallCenterMHz <= 0 {
            return "Waterfall"
        }
        if let preview = pendingPanTargetHz {
            return String(format: "→ %.3f MHz · %.1f kHz",
                          Double(preview) / 1_000_000,
                          displaySpanHz / 1_000)
        }
        return String(format: "%.3f MHz · %.1f kHz",
                      coordinator.waterfallCenterMHz,
                      displaySpanHz / 1_000)
    }

    private var emptyMessage: String {
        if coordinator.connectionState == .connected {
            "Waiting for spectrum from Sweep.\nConnect a SCU-LAN10 or SmartSDR radio there."
        } else {
            "Connect to a CW Sweep server first."
        }
    }

    private var spectrumCanvas: some View {
        Canvas { context, size in
            drawSpectrum(context: context, size: size)
            drawVFOMarker(context: context, size: size)
        }
        .background(.black)
        .contentShape(Rectangle())
        .onGeometryChange(for: CGSize.self, of: \.size) { newSize in
            canvasSize = newSize
        }
        .gesture(panGesture)
        .simultaneousGesture(magnifyGesture)
        .onTapGesture(count: 2) {
            withAnimation(.easeOut(duration: 0.2)) {
                targetSpanHz = nil
            }
            Task { await coordinator.requestWaterfallSpan(hz: nil) }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "waveform.path.ecg.rectangle")
                .foregroundStyle(.secondary)
            Text(headerTitle)
                .font(.subheadline)
                .fontDesign(.monospaced)
            Spacer()
            if !coordinator.waterfallSourceLabel.isEmpty,
               coordinator.waterfallSourceLabel != "None"
            {
                Text(coordinator.waterfallSourceLabel)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            ProgressView()
            Text(emptyMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black)
    }

    private func scheduleLiveTune() {
        guard let target = panTarget(
            anchorFreqHz: dragAnchorFreqHz,
            dragPixels: dragOffsetX
        ) else {
            return
        }
        let now = ContinuousClock.now
        let elapsed: Duration = lastTuneSentAt.map { now - $0 } ?? Self.liveTuneInterval
        if elapsed >= Self.liveTuneInterval {
            sendLiveTune(target: target, at: now)
            return
        }
        trailingTuneTask?.cancel()
        let remaining = Self.liveTuneInterval - elapsed
        trailingTuneTask = Task { @MainActor in
            try? await Task.sleep(for: remaining)
            guard !Task.isCancelled else {
                return
            }
            guard let trailingTarget = panTarget(
                anchorFreqHz: dragAnchorFreqHz,
                dragPixels: dragOffsetX
            ) else {
                return
            }
            sendLiveTune(target: trailingTarget, at: .now)
        }
    }

    private func sendLiveTune(target: UInt64, at instant: ContinuousClock.Instant) {
        guard target != lastTuneSentTarget else {
            return
        }
        lastTuneSentTarget = target
        lastTuneSentAt = instant
        Task { await coordinator.tune(freqHz: target) }
    }

    /// Right-drag → lower frequency (spectrum slides right as lower
    /// frequencies come into view at center).
    private func panTarget(anchorFreqHz: UInt64?, dragPixels: CGFloat) -> UInt64? {
        guard let anchor = anchorFreqHz, canvasSize.width > 0 else {
            return nil
        }
        let deltaHz = -(Double(dragPixels) / Double(canvasSize.width)) * displaySpanHz
        let target = Double(anchor) + deltaHz
        guard target > 100_000 else {
            return nil
        }
        return UInt64(target.rounded())
    }

    /// Blit each registered line into the current display window. A line's
    /// horizontal placement comes from its own center/span, so history from
    /// different tunings and spans renders where it truly belongs.
    private func drawSpectrum(context: GraphicsContext, size: CGSize) {
        let center = displayCenterHz
        let span = displaySpanHz
        guard span > 0 else {
            return
        }
        for (lineIdx, line) in coordinator.waterfallLines.enumerated() {
            let yPos = CGFloat(lineIdx)
            guard yPos < size.height else {
                break
            }
            guard let image = line.image else {
                continue
            }
            let widthScale = CGFloat(line.spanHz / span)
            let lineWidth = size.width * widthScale
            let relCenter = CGFloat((line.centerHz - center) / span)
            let xPos = size.width / 2 + relCenter * size.width - lineWidth / 2
            guard xPos < size.width, xPos + lineWidth > 0 else {
                continue
            }
            let rect = CGRect(x: xPos, y: yPos, width: lineWidth, height: 1)
            context.draw(Image(decorative: image, scale: 1), in: rect)
        }
    }

    /// Marker at the radio's actual displayed-center frequency. During a
    /// drag it trails the finger until the rig catches up, which doubles as
    /// visual feedback for in-flight tunes.
    private func drawVFOMarker(context: GraphicsContext, size: CGSize) {
        let radioCenterHz = coordinator.waterfallCenterMHz * 1_000_000
        guard radioCenterHz > 0, displaySpanHz > 0 else {
            return
        }
        let rel = CGFloat((radioCenterHz - displayCenterHz) / displaySpanHz)
        let xPos = size.width / 2 + rel * size.width
        guard xPos >= 0, xPos <= size.width else {
            return
        }
        var path = Path()
        path.move(to: CGPoint(x: xPos, y: 0))
        path.addLine(to: CGPoint(x: xPos, y: size.height))
        context.stroke(path, with: .color(.red.opacity(0.7)), lineWidth: 1)
    }
}
