import CarrierWaveCore
import SwiftUI

// MARK: - FlowLayout

/// Simple flow layout for token pills
struct FlowLayout: Layout {
    // MARK: Internal

    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) -> CGSize {
        let result = arrangeSubviews(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache _: inout ()
    ) {
        let result = arrangeSubviews(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                proposal: .unspecified
            )
        }
    }

    // MARK: Private

    private struct ArrangementResult {
        var positions: [CGPoint]
        var size: CGSize
    }

    private func arrangeSubviews(
        proposal: ProposedViewSize,
        subviews: Subviews
    ) -> ArrangementResult {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxX: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > maxWidth, currentX > 0 {
                currentX = 0
                currentY += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: currentX, y: currentY))
            currentX += size.width + spacing
            maxX = max(maxX, currentX - spacing)
            rowHeight = max(rowHeight, size.height)
        }

        return ArrangementResult(
            positions: positions,
            size: CGSize(width: maxX, height: currentY + rowHeight)
        )
    }
}

// MARK: - TokenKind Icon Extension

extension TokenKind {
    var icon: String {
        switch self {
        case .frequency: "antenna.radiowaves.left.and.right"
        case .mode: "waveform"
        case .band: "dial.low"
        case .split: "arrow.up.arrow.down"
        case .unknown: "questionmark.circle"
        }
    }
}

// MARK: - ValidationState Color Extension

extension ValidationState {
    var color: Color {
        switch self {
        case .valid: .green
        case .warning: .yellow
        case .error: .red
        }
    }
}

// MARK: - SplitDirective + CustomStringConvertible

extension SplitDirective: CustomStringConvertible {
    public var description: String {
        switch self {
        case let .up(kHz): "TX +\(kHz == kHz.rounded() ? String(Int(kHz)) : String(format: "%.1f", kHz)) kHz"
        case let .down(kHz): "TX -\(kHz == kHz.rounded() ? String(Int(kHz)) : String(format: "%.1f", kHz)) kHz"
        case let .explicitFrequency(kHz): "TX \(FrequencyFormatter.format(kHz / 1_000)) MHz"
        case .off: "Split OFF"
        }
    }
}
