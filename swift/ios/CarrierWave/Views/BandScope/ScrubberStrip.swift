import SwiftUI

// MARK: - ScrubberStrip

/// The horizontal position strip pinned below the header, Scope only
/// (spec §3): one tier-colored tick per spot at proportional x, a
/// light-bordered viewport window synced to the list scroll (debounced),
/// the anchor caret at trust opacity, and faint tick labels. Tap scrolls
/// the list to the nearest cluster.
struct ScrubberStrip: View {
    // MARK: Internal

    let model: BandScopeViewModel

    var body: some View {
        TimelineView(.periodic(from: .now, by: 10)) { timeline in
            VStack(spacing: 2) {
                canvas(now: timeline.date)
                tickLabels
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 6)
        }
        .onChange(of: visibleRangeKey) {
            scheduleWindowSync()
        }
    }

    // MARK: Private

    /// Immutable per-render inputs, captured BEFORE the Canvas closure —
    /// Canvas bodies must not touch @Observable state per render.
    private struct RenderInputs {
        let clusters: [ScopeCluster]
        let profile: GoalProfile
        let isFiltering: Bool
        let passIDs: Set<String>
        let anchor: BandScopeAnchor?
        let range: ClosedRange<Double>
        let window: ClosedRange<Double>?
        let now: Date

        func xPos(_ freq: Double, width: CGFloat) -> CGFloat {
            let span = range.upperBound - range.lowerBound
            return CGFloat((freq - range.lowerBound) / span) * width
        }
    }

    @State private var window: ClosedRange<Double>?
    @State private var syncTask: Task<Void, Never>?
    @State private var stripWidth: CGFloat = 0

    private var range: ClosedRange<Double>? {
        let clusters = model.scopeClusters
        guard let first = clusters.first, let last = clusters.last else {
            return nil
        }
        let pad = 1.0
        return (first.minFrequencyKHz - pad) ... (last.maxFrequencyKHz + pad)
    }

    /// Coalesced key so the debounce fires only when the visible set
    /// actually moves.
    private var visibleRangeKey: String {
        let freqs = model.visibleScopeFreqs.values
        guard let low = freqs.min(), let high = freqs.max() else {
            return ""
        }
        return "\(low)-\(high)"
    }

    private var tickLabels: some View {
        HStack {
            if let range {
                let span = range.upperBound - range.lowerBound
                ForEach(0 ..< 5, id: \.self) { index in
                    if index > 0 {
                        Spacer()
                    }
                    Text(String(
                        format: "%.3f",
                        (range.lowerBound + span * Double(index) / 4) / 1_000
                    ))
                    .font(.caption2.monospaced())
                    .foregroundStyle(BandScopeTheme.faint)
                }
            }
        }
    }

    private func canvas(now: Date) -> some View {
        let inputs = range.map { range in
            RenderInputs(
                clusters: model.scopeClusters,
                profile: model.activeProfile,
                isFiltering: model.filterService.isFiltering,
                passIDs: model.filterService.scopePassIDs,
                anchor: model.anchorStore.activeAnchor(band: model.activeBand, now: now),
                range: range,
                window: window,
                now: now
            )
        }

        return Canvas { context, size in
            guard let inputs, inputs.range.upperBound > inputs.range.lowerBound else {
                return
            }
            Self.drawMarks(inputs, context: &context, size: size)
            Self.drawViewportWindow(inputs, context: &context, size: size)
            Self.drawAnchorCaret(inputs, context: &context, size: size)
        }
        .frame(height: 36)
        .background(
            RoundedRectangle(cornerRadius: 8).fill(BandScopeTheme.surface2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8).strokeBorder(BandScopeTheme.line)
        )
        .contentShape(Rectangle())
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width
        } action: { width in
            stripWidth = width
        }
        .onTapGesture { location in
            guard let range else {
                return
            }
            tap(at: location, range: range)
        }
    }

    /// One tier-colored tick per spot (§3): width 2.5pt (4pt for
    /// `needed`), opacity = tier base × freshness × filter dim.
    private static func drawMarks(
        _ inputs: RenderInputs, context: inout GraphicsContext, size: CGSize
    ) {
        for cluster in inputs.clusters {
            for spot in cluster.spots {
                let tier = spot.tier(for: inputs.profile)
                let width: CGFloat = tier == .needed ? 4 : 2.5
                var opacity = tier == .rbn ? 0.45 : 1.0
                opacity *= FreshnessFade.opacity(
                    spotted: spot.spot.timestamp, now: inputs.now
                )
                if inputs.isFiltering, !inputs.passIDs.contains(spot.id) {
                    opacity = BandScopeTunables.filteredDimOpacity
                }
                let xPos = inputs.xPos(spot.spot.frequencyKHz, width: size.width)
                let rect = CGRect(
                    x: xPos - width / 2, y: 4, width: width, height: size.height - 8
                )
                context.fill(
                    Path(roundedRect: rect, cornerRadius: 1),
                    with: .color(BandScopeTheme.color(for: tier).opacity(opacity))
                )
            }
        }
    }

    /// Viewport window rect (§3) — the freq range of visible list rows.
    private static func drawViewportWindow(
        _ inputs: RenderInputs, context: inout GraphicsContext, size: CGSize
    ) {
        guard let window = inputs.window else {
            return
        }
        let minX = inputs.xPos(window.lowerBound, width: size.width)
        let maxX = inputs.xPos(window.upperBound, width: size.width)
        let rect = CGRect(
            x: minX - 2, y: 1,
            width: max(maxX - minX + 4, 8), height: size.height - 2
        )
        context.stroke(
            Path(roundedRect: rect, cornerRadius: 3),
            with: .color(BandScopeTheme.youLine.opacity(0.55)),
            lineWidth: 1
        )
    }

    /// Anchor caret: downward triangle + hairline at trust opacity (§3/§6).
    private static func drawAnchorCaret(
        _ inputs: RenderInputs, context: inout GraphicsContext, size: CGSize
    ) {
        guard let anchor = inputs.anchor else {
            return
        }
        let xPos = inputs.xPos(anchor.frequencyKHz, width: size.width)
        let trust = anchor.trust(at: inputs.now)
        var triangle = Path()
        triangle.move(to: CGPoint(x: xPos - 4, y: 0))
        triangle.addLine(to: CGPoint(x: xPos + 4, y: 0))
        triangle.addLine(to: CGPoint(x: xPos, y: 6))
        triangle.closeSubpath()
        context.fill(
            triangle, with: .color(BandScopeTheme.youLine.opacity(trust))
        )
        context.stroke(
            Path { path in
                path.move(to: CGPoint(x: xPos, y: 6))
                path.addLine(to: CGPoint(x: xPos, y: size.height))
            },
            with: .color(BandScopeTheme.youLine.opacity(trust * 0.7)),
            lineWidth: 1
        )
    }

    private func scheduleWindowSync() {
        syncTask?.cancel()
        let freqs = model.visibleScopeFreqs.values
        guard let low = freqs.min(), let high = freqs.max() else {
            return
        }
        syncTask = Task {
            try? await Task.sleep(
                for: .seconds(BandScopeTunables.scrubberSyncDebounce)
            )
            guard !Task.isCancelled else {
                return
            }
            window = low ... high
        }
    }

    private func tap(at location: CGPoint, range: ClosedRange<Double>) {
        let width = stripWidth
        guard width > 0 else {
            return
        }
        let fraction = min(max(location.x / width, 0), 1)
        let freq = range.lowerBound
            + (range.upperBound - range.lowerBound) * Double(fraction)
        model.requestScopeScroll(toFrequencyKHz: freq)
    }
}
