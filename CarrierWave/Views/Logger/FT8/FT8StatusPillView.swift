//
//  FT8StatusPillView.swift
//  CarrierWave
//

import SwiftUI

/// Compact status indicator showing audio health and decode count.
/// Replaces the always-visible debug panel; tapping expands the full panel.
struct FT8StatusPillView: View {
    // MARK: Internal

    let audioLevel: Float
    let decodeCount: Int
    let cyclesSinceLastDecode: Int

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(statusColor)
                .frame(width: 6, height: 6)

            Text(statusLabel)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("\u{00B7}")
                .foregroundStyle(.tertiary)

            Text("\(decodeCount)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Private

    /// Red: no signal for 4+ cycles or no audio.
    /// Orange: audio level too low or too high.
    /// Green: healthy.
    private var statusColor: Color {
        if cyclesSinceLastDecode >= 4 || audioLevel < 0.001 {
            return .red
        }
        if audioLevel < 0.01 || audioLevel > 0.8 {
            return .orange
        }
        return .green
    }

    private var statusLabel: String {
        if cyclesSinceLastDecode >= 4 || audioLevel < 0.001 {
            return "No Signal"
        }
        if audioLevel < 0.01 {
            return "Low"
        }
        if audioLevel > 0.8 {
            return "Hot"
        }
        return "OK"
    }
}
