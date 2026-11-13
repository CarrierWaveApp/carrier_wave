import SwiftUI

// MARK: - ScopeGapDivider

/// Clear spectrum as an affordance (spec §4). Gaps under the threshold
/// render a plain hairline; larger ones become a tappable QSY row whose
/// height scales mildly with the gap, hard-capped at 44pt. Gap math runs
/// on unfiltered data — the divider never lies.
struct ScopeGapDivider: View {
    // MARK: Internal

    let gap: ScopeGap
    let onQSY: () -> Void

    var body: some View {
        if gap.isQSYAffordance {
            Button(action: onQSY) {
                HStack(spacing: 8) {
                    dashedLine
                    Text(label)
                        .font(.caption2.monospaced())
                        .foregroundStyle(BandScopeTheme.dim)
                        .fixedSize()
                    dashedLine
                }
                .padding(.horizontal, 16)
                .frame(height: rowHeight)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } else {
            Rectangle()
                .fill(BandScopeTheme.line)
                .frame(height: 1)
                .padding(.leading, 72)
        }
    }

    // MARK: Private

    private var label: String {
        String(format: "%.1f kHz clear · QSY", gap.gapKHz)
    }

    /// Mild scale with gap size, capped (§4).
    private var rowHeight: CGFloat {
        let base: CGFloat = 24
        let scaled = base + CGFloat(gap.gapKHz - BandScopeTunables.gapAffordanceKHz) * 4
        return min(scaled, BandScopeTunables.gapRowMaxHeight)
    }

    private var dashedLine: some View {
        Line()
            .stroke(
                BandScopeTheme.line,
                style: StrokeStyle(lineWidth: 1, dash: [4, 3])
            )
            .frame(height: 1)
    }
}

// MARK: - Line

nonisolated private struct Line: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return path
    }
}

// MARK: - QSYSheet

/// The gap tap action (§4): midpoint frequency pre-filled, Tune available.
struct QSYSheet: View {
    // MARK: Internal

    let gap: ScopeGap
    let band: String
    let model: BandScopeViewModel

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Text(String(format: "%.4f MHz", gap.midpointKHz / 1_000))
                    .font(.title2.weight(.bold).monospaced())
                    .foregroundStyle(BandScopeTheme.text)
                Text(String(format: "%.1f kHz of clear spectrum", gap.gapKHz))
                    .font(.subheadline)
                    .foregroundStyle(BandScopeTheme.dim)

                Button {
                    tune()
                } label: {
                    Label(
                        String(format: "Tune %.4f", gap.midpointKHz / 1_000),
                        systemImage: "dot.radiowaves.left.and.right"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(!RadioService.shared.isConnected)

                if !RadioService.shared.isConnected {
                    Text("Radio not connected — anchor will still be set.")
                        .font(.caption)
                        .foregroundStyle(BandScopeTheme.faint)
                }

                Button("Set anchor only") {
                    model.declareAnchor(frequencyKHz: gap.midpointKHz, band: band)
                    dismiss()
                }
                .font(.subheadline)

                Spacer()
            }
            .padding(24)
            .background(BandScopeTheme.background)
            .navigationTitle("QSY")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }

    // MARK: Private

    @Environment(\.dismiss) private var dismiss

    private func tune() {
        let radio = RadioService.shared
        if radio.isConnected {
            radio.setFrequency(gap.midpointKHz / 1_000)
        }
        model.declareAnchor(frequencyKHz: gap.midpointKHz, band: band)
        dismiss()
    }
}
