//
//  FT8AudioLevelBar.swift
//  CarrierWave
//

import SwiftUI

/// Compact EQ-style audio level meter. Each pip lights up as RMS climbs;
/// pips shift green → yellow → red so over-driven audio is obvious at a glance.
/// A small peak indicator dot sits above the bar when the live peak magnitude
/// is near full-scale, signalling real digital clipping (independent of RMS).
struct FT8AudioLevelBar: View {
    // MARK: Internal

    /// Band-limited (200–2900 Hz) RMS of the most recent buffer, in [0, ~1].
    /// Measured on the FT8 passband only so out-of-band carriers don't
    /// drive the meter on top of legitimately healthy FT8 audio.
    let rms: Float
    /// Band-limited peak sample magnitude in the most recent buffer, in [0, 1].
    let peak: Float
    /// FT8 cycles since the last successful decode. After several quiet
    /// cycles we paint the meter dim grey to communicate "no signal" the
    /// way the old pill did.
    let cyclesSinceLastDecode: Int
    /// Decode count for the current cycle, shown next to the meter.
    let decodeCount: Int

    var body: some View {
        HStack(spacing: 6) {
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(0 ..< Self.pipCount, id: \.self) { idx in
                    Capsule()
                        .fill(pipFill(at: idx))
                        .frame(width: 3, height: pipHeight(at: idx))
                }
            }
            .overlay(alignment: .top) {
                if !isSilent, rmsDBFS >= Self.warnDBFS {
                    Circle()
                        .fill(rmsDBFS >= Self.clipDBFS ? Color.red : Color.orange)
                        .frame(width: 4, height: 4)
                        .offset(y: -3)
                        .accessibilityHidden(true)
                }
            }
            .frame(height: 14, alignment: .bottom)

            Text("\u{00B7}")
                .foregroundStyle(.tertiary)

            Text("\(decodeCount)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    // MARK: Private

    private static let pipCount = 8
    /// dBFS spanned by the meter. Each of the 8 pips covers ~7.5 dB, so
    /// the lowest pip lights at ~-60 dBFS and the top pip at ~0 dBFS.
    /// The wider span keeps the meter from looking binary on iPhones
    /// where the AGC pins typical input near full-scale; true silence
    /// still falls below the floor and goes dark.
    private static let minDBFS: Float = -60
    /// Yellow warn dot. WSJT-X's recommended FT8 input sits around
    /// -20 dBFS RMS in the passband; -10 dBFS is hot but still recoverable.
    private static let warnDBFS: Float = -10
    /// Red clip dot. Above -3 dBFS the GFSK crest factor has no headroom
    /// and instantaneous samples are pinning the ADC.
    private static let clipDBFS: Float = -3
    /// RMS below this is treated as no signal — keeps the meter dim
    /// when the rig is off so the user can tell silence apart from
    /// a low-but-real input. Below ~-66 dBFS.
    private static let silenceRMS: Float = 0.0005

    /// Silence is determined by the audio itself, not by decode history —
    /// a quiet band can produce real audio levels with no FT8 decodes,
    /// and the meter should still reflect the actual level. The decode
    /// counter is shown alongside the meter for that information.
    private var isSilent: Bool {
        rms < Self.silenceRMS
    }

    /// Convert RMS to dBFS, clamped to `[minDBFS, 0]`. Values below
    /// `minDBFS` are treated as silent (returns minDBFS); above 0 are
    /// clamped to 0 (clipping is signaled separately by the peak dot).
    private var rmsDBFS: Float {
        guard rms > 0 else {
            return Self.minDBFS
        }
        let dbfs = 20 * log10(rms)
        return min(0, max(Self.minDBFS, dbfs))
    }

    private var litPipCount: Int {
        guard !isSilent else {
            return 0
        }
        // Map [minDBFS, 0] → [0, 1], then scale to pip count.
        let normalized = (rmsDBFS - Self.minDBFS) / (-Self.minDBFS)
        let pips = Float(Self.pipCount) * normalized
        return max(1, min(Self.pipCount, Int(pips.rounded(.up))))
    }

    private var accessibilityLabel: String {
        if isSilent {
            return "No audio signal, \(decodeCount) decodes this cycle"
        }
        let dbfs = Int(rmsDBFS.rounded())
        let clip = rmsDBFS >= Self.clipDBFS ? ", clipping" : ""
        return "Audio level \(dbfs) decibels full scale\(clip), " +
            "\(decodeCount) decodes this cycle"
    }

    private func pipHeight(at idx: Int) -> CGFloat {
        // Ascending heights: 4pt at the bottom, 14pt at the top.
        let minH: CGFloat = 4
        let maxH: CGFloat = 14
        let fraction = CGFloat(idx) / CGFloat(Self.pipCount - 1)
        return minH + (maxH - minH) * fraction
    }

    private func pipFill(at idx: Int) -> Color {
        guard idx < litPipCount else {
            return Color(.systemGray5)
        }
        // Green for the bottom 5 pips, yellow for the next two, red for the top.
        if idx >= Self.pipCount - 1 {
            return .red
        }
        if idx >= Self.pipCount - 3 {
            return .yellow
        }
        return .green
    }
}
