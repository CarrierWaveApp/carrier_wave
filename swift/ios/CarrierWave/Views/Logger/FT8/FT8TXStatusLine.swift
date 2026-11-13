//
//  FT8TXStatusLine.swift
//  CarrierWave
//

import SwiftUI

struct FT8TXStatusLine: View {
    // MARK: Internal

    let txState: FT8TXState

    var body: some View {
        HStack(spacing: 6) {
            statusDot
            statusText
        }
        .font(.caption)
    }

    // MARK: Private

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @ViewBuilder
    private var statusDot: some View {
        switch txState {
        case .idle:
            EmptyView()
        case .armed:
            Circle()
                .fill(Color.orange)
                .frame(width: 8, height: 8)
        case .transmitting:
            Circle()
                .fill(Color.orange)
                .frame(width: 8, height: 8)
                .opacity(reduceMotion ? 1.0 : 1.0)
                .animation(
                    reduceMotion
                        ? nil
                        : .easeInOut(duration: 0.8).repeatForever(autoreverses: true),
                    value: txState
                )
        case .halted:
            Circle()
                .strokeBorder(Color.orange, lineWidth: 1.5)
                .frame(width: 8, height: 8)
        }
    }

    @ViewBuilder
    private var statusText: some View {
        switch txState {
        case .idle:
            EmptyView()
        case let .armed(callsign):
            Text("TX armed \u{00B7} \(callsign)")
                .foregroundStyle(.secondary)
        case let .transmitting(message):
            Text("TX \u{00B7} \(message)")
                .font(.caption.monospaced())
                .foregroundStyle(.orange)
                .lineLimit(1)
        case let .halted(callsign):
            Text("TX halted \u{00B7} \(callsign)")
                .foregroundStyle(.secondary)
        }
    }
}
