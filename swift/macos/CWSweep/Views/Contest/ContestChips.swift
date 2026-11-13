import SwiftUI

// MARK: - ContestChip

/// Compact pill-style chip for contest metadata (mode, band, duration).
struct ContestChip: View {
    let text: String
    var color: Color = .secondary
    var systemImage: String?

    var body: some View {
        HStack(spacing: 3) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 9, weight: .medium))
                    .accessibilityHidden(true)
            }
            Text(text)
                .font(.caption2.weight(.medium))
                .lineLimit(1)
        }
        .foregroundStyle(color)
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(color.opacity(0.15), in: RoundedRectangle(cornerRadius: 4))
    }
}

// MARK: - ContestModeChips

/// Horizontal strip of mode chips from a contest definition.
struct ContestModeChips: View {
    // MARK: Internal

    let modes: [String]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(modes, id: \.self) { mode in
                ContestChip(
                    text: mode,
                    color: modeColor(mode),
                    systemImage: "waveform"
                )
            }
        }
    }

    // MARK: Private

    private func modeColor(_ mode: String) -> Color {
        switch mode.uppercased() {
        case "CW": .cyan
        case "SSB",
             "PHONE": .pink
        case "RTTY",
             "FT8",
             "FT4",
             "JTTY",
             "DIGITAL",
             "PSK": .indigo
        case "MIXED": .purple
        default: .gray
        }
    }
}

// MARK: - ContestBandChips

/// Compact band display — shows individual chips if <= 4, otherwise summary.
struct ContestBandChips: View {
    let bands: [String]

    var body: some View {
        if bands.count > 4 {
            ContestChip(
                text: "\(bands.count) bands",
                color: .blue,
                systemImage: "antenna.radiowaves.left.and.right"
            )
        } else {
            HStack(spacing: 4) {
                ForEach(bands, id: \.self) { band in
                    ContestChip(text: band, color: .blue)
                }
            }
        }
    }
}
