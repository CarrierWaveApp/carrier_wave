import SwiftUI

// MARK: - ScopeScrollCommand

/// A one-shot request to scroll the scope to a frequency. The `nonce` makes
/// repeat requests to the same Hz distinct so `onChange` still fires.
struct ScopeScrollCommand: Equatable {
    let hz: Int
    let animated: Bool
    let nonce: Int
}

// MARK: - FrequencyScopeList

/// The scrolling band scope: a Hz ruler with spot rows, hatched off-plan zones,
/// segment labels, and a fixed centered reticle. Rows are precomputed by the
/// field and passed in.
///
/// The centered frequency is *read* from the rows themselves: each on-screen row
/// checks whether its rendered frame sits under the reticle. Never derive it by
/// dividing the scroll offset by the row height — a `LazyVStack` gives rows it
/// hasn't rendered yet an estimated height, so after any jump the offset stops
/// mapping to a row and the readout drifts off the reticle (CAR-346). The read
/// is never fed back as a scroll target, so a fast flick keeps full native
/// momentum. Deliberate jumps (open / find / band / set) go through
/// `scrollCommand` and `rowsVersion`.
struct FrequencyScopeList: View {
    // MARK: Internal

    nonisolated static let rowHeight: CGFloat = 34
    nonisolated static let scopeHeight: CGFloat = 260

    let rows: [ScopeRowInfo]
    let isGood: Bool
    let isDataMode: Bool
    /// Bumped by the field whenever `rows` is rebuilt, so the scope re-centers.
    let rowsVersion: Int
    let scrollCommand: ScopeScrollCommand?

    @Binding var centerHz: Int

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                LazyVStack(spacing: 0) {
                    ForEach(rows) { info in
                        ScopeFreqRow(info: info, isDataMode: isDataMode)
                            .frame(height: Self.rowHeight)
                            .id(info.hz)
                            .onGeometryChange(for: Bool.self) { geometry in
                                Self.isUnderReticle(geometry.frame(in: .named(Self.viewport)))
                            } action: { underReticle in
                                if underReticle {
                                    rowReachedReticle(info.hz)
                                }
                            }
                    }
                }
            }
            .coordinateSpace(.named(Self.viewport))
            // Half-viewport margins so the first and last rows can reach the reticle.
            .contentMargins(.vertical, Self.pad, for: .scrollContent)
            .scrollIndicators(.hidden)
            .onScrollPhaseChange { _, phase in
                switch phase {
                case .tracking,
                     .interacting,
                     .decelerating:
                    // A real drag wins over any jump still landing.
                    pendingJumpHz = nil
                default:
                    break
                }
            }
            // The field sets `expanded` and `scrollCommand` in the same update,
            // so `onChange(of: scrollCommand)` never sees that first command.
            .onAppear { center(proxy, on: scrollCommand?.hz ?? centerHz, animated: false) }
            .onChange(of: rowsVersion) { _, _ in center(proxy, on: centerHz, animated: false) }
            .onChange(of: scrollCommand) { _, command in
                guard let command else {
                    return
                }
                center(proxy, on: command.hz, animated: command.animated)
            }
            .overlay { reticle }
            .overlay(alignment: .top) { scrim(.top) }
            .overlay(alignment: .bottom) { scrim(.bottom) }
        }
        .frame(height: Self.scopeHeight)
        .clipped()
    }

    // MARK: Private

    nonisolated private static let viewport = "FrequencyScopeViewport"

    private static var pad: CGFloat {
        (scopeHeight - rowHeight) / 2
    }

    /// The row currently rendered under the reticle.
    @State private var reticleHz: Int?
    /// Target of a deliberate jump still landing. Rows reported before it
    /// arrives (the band edge on open, rows passed mid-glide) aren't the user's
    /// choice and must not overwrite `centerHz`.
    @State private var pendingJumpHz: Int?

    private var reticleColor: Color {
        isGood ? .green : .orange
    }

    private var reticle: some View {
        ZStack {
            VStack(spacing: 0) {
                Rectangle().fill(reticleColor).frame(height: 1.5)
                Spacer(minLength: 0)
                Rectangle().fill(reticleColor).frame(height: 1.5)
            }
            .frame(height: Self.rowHeight)
            HStack(spacing: 0) {
                Triangle().fill(reticleColor).frame(width: 6, height: 10)
                Spacer(minLength: 0)
            }
        }
        .allowsHitTesting(false)
    }

    private func scrim(_ edge: VerticalEdge) -> some View {
        LinearGradient(
            colors: edge == .top
                ? [Color(.secondarySystemGroupedBackground), .clear]
                : [.clear, Color(.secondarySystemGroupedBackground)],
            startPoint: .top, endPoint: .bottom
        )
        .frame(height: 52)
        .allowsHitTesting(false)
    }

    /// True when a row's rendered frame (in viewport coordinates) contains the
    /// reticle's center line.
    nonisolated private static func isUnderReticle(_ frame: CGRect) -> Bool {
        let reticleY = scopeHeight / 2
        return frame.minY <= reticleY && reticleY < frame.maxY
    }

    /// Adopt the row under the reticle as the selection — unless a deliberate
    /// jump is still landing, in which case wait for it to arrive.
    private func rowReachedReticle(_ hz: Int) {
        reticleHz = hz
        if let pending = pendingJumpHz {
            if hz == pending {
                pendingJumpHz = nil
            }
            return
        }
        if hz != centerHz {
            centerHz = hz
        }
    }

    private func center(_ proxy: ScrollViewProxy, on hz: Int, animated: Bool) {
        guard rows.contains(where: { $0.hz == hz }) else {
            return
        }
        // Mark the jump before it starts, so the band-edge position reported on
        // first layout can't be adopted ahead of it.
        pendingJumpHz = reticleHz == hz ? nil : hz
        DispatchQueue.main.async {
            if animated {
                withAnimation(.easeInOut(duration: 0.45)) { proxy.scrollTo(hz, anchor: .center) }
            } else {
                proxy.scrollTo(hz, anchor: .center)
            }
        }
    }
}

// MARK: - ScopeFreqRow

/// One ruler row, rendered from precomputed `ScopeRowInfo`. No band-plan work
/// and no dependency on the centered frequency — the `ScopeRow` vocabulary
/// (freq column, tier dot, mono call, age) plus hatch / segment label / hole.
struct ScopeFreqRow: View {
    // MARK: Internal

    let info: ScopeRowInfo
    let isDataMode: Bool

    var body: some View {
        HStack(spacing: 8) {
            Text(info.freqText)
                .font(.caption.monospaced())
                .foregroundStyle(info.freqText.isEmpty ? Color(.quaternaryLabel) : .secondary)
                .frame(width: 62, alignment: .leading)

            if let spot = info.spot {
                spotContent(spot)
            } else if let hole = info.hole {
                holePill(hole)
                tickline
            } else {
                tickline
            }
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(hatchBackground)
        .overlay(alignment: .topLeading) { segmentLabel }
        .overlay(alignment: .topTrailing) { hardBlockLabel }
    }

    // MARK: Private

    private var tickline: some View {
        Rectangle().fill(Color(.separator)).frame(height: 0.5).frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var hatchBackground: some View {
        if info.hatched {
            ZStack {
                Color.orange.opacity(0.06)
                DiagonalHatch().stroke(Color.orange.opacity(0.35), lineWidth: 1).clipped()
            }
        }
    }

    @ViewBuilder
    private var segmentLabel: some View {
        if let label = info.segLabel {
            Text(label)
                .font(.system(size: 9.5, weight: .bold))
                .kerning(0.5)
                .textCase(.uppercase)
                .foregroundStyle(.tertiary)
                .padding(.leading, 14).padding(.top, 2)
        }
    }

    @ViewBuilder
    private var hardBlockLabel: some View {
        if let label = info.blockLabel {
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.orange)
                .padding(.horizontal, 7).padding(.vertical, 2)
                .background(Color.orange.opacity(0.18), in: Capsule())
                .padding(.trailing, 12).padding(.top, 3)
        }
    }

    @ViewBuilder
    private func spotContent(_ spot: ScopeSpot) -> some View {
        Circle()
            .fill(BandScopeTheme.color(for: spot.tier))
            .frame(width: 6, height: 6)
            .shadow(
                color: BandScopeTheme.glows(spot.tier) ? BandScopeTheme.amber.opacity(0.6) : .clear,
                radius: 4
            )
        Text(spot.callsign)
            .font(.subheadline.weight(.semibold).monospaced())
            .foregroundStyle(spot.tier == .rbn ? Color.secondary : Color.primary)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
        if info.pileupCount > 0 {
            Text("+\(info.pileupCount)")
                .font(.caption2.weight(.bold))
                .foregroundStyle(BandScopeTheme.color(for: spot.tier))
        }
        if isDataMode, let wpm = spot.wpm {
            Text("\(wpm) wpm").font(.caption2.monospaced()).foregroundStyle(.secondary)
        }
        if let chip = spot.chip {
            Text(chip)
                .font(.caption2.weight(.medium))
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(BandScopeTheme.color(for: spot.tier).opacity(0.2), in: Capsule())
                .foregroundStyle(BandScopeTheme.color(for: spot.tier))
        }
        Spacer(minLength: 4)
        Text(spot.ageText).font(.caption2.monospaced()).foregroundStyle(.tertiary)
    }

    private func holePill(_ hole: String) -> some View {
        Text(hole)
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 6).padding(.vertical, 1)
            .background(Color(.systemGray).opacity(0.22), in: Capsule())
            .foregroundStyle(Color(.systemGray))
    }
}

// MARK: - DiagonalHatch

/// Diagonal hatch fill for off-plan zones.
nonisolated struct DiagonalHatch: Shape {
    var spacing: CGFloat = 6

    func path(in rect: CGRect) -> Path {
        var path = Path()
        var x = -rect.height
        while x < rect.width {
            path.move(to: CGPoint(x: x, y: rect.height))
            path.addLine(to: CGPoint(x: x + rect.height, y: 0))
            x += spacing
        }
        return path
    }
}

// MARK: - Triangle

/// Left-pointing reticle marker.
nonisolated struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX, y: 0))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
