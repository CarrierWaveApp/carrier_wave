import CarrierWaveData
import SwiftUI

// MARK: - WebSDRReceiverRow

/// Enriched receiver row shared between picker and favorites settings.
struct WebSDRReceiverRow: View {
    // MARK: Internal

    let receiver: KiwiSDRReceiver
    let enrichment: KiwiSDRStatusFetcher.ReceiverStatus?
    let isFavorite: Bool
    let operatingBand: String?
    let onToggleFavorite: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            favoriteButton
            receiverContent
        }
        .contentShape(Rectangle())
        .opacity(receiver.isAvailable ? 1.0 : 0.5)
    }

    // MARK: Private

    // MARK: - Favorite Button

    private var favoriteButton: some View {
        Button(action: onToggleFavorite) {
            Image(systemName: isFavorite ? "star.fill" : "star")
                .foregroundStyle(isFavorite ? .yellow : .secondary)
                .font(.body)
        }
        .buttonStyle(.borderless)
        .frame(minWidth: 44, minHeight: 44)
        .accessibilityLabel(
            isFavorite ? "Remove from favorites" : "Add to favorites"
        )
    }

    // MARK: - Content

    private var receiverContent: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Row 1: Name + distance
            topRow

            // Row 2: Location + grid
            locationRow

            // Row 3: Antenna badges + SNR
            antennaSNRRow

            // Row 4: Band coverage + availability
            coverageRow

            // Row 5: Band match (only during activation)
            bandMatchBadge
        }
    }

    private var topRow: some View {
        HStack {
            Text(receiver.name)
                .font(.subheadline)
                .fontWeight(.medium)
                .lineLimit(1)

            Spacer()

            if let dist = receiver.formattedDistance {
                Text(dist)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var locationRow: some View {
        HStack(spacing: 4) {
            Text(receiver.location)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            if let grid = enrichment?.grid ?? receiver.grid {
                Text("·")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Text(grid)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var antennaSNRRow: some View {
        let parsed = enrichment?.parsedAntenna ?? receiver.parsedAntenna
        HStack(spacing: 6) {
            // Antenna badges
            if let parsed {
                antennaBadges(parsed)
            }

            Spacer()

            // SNR gauge or shimmer
            if let snr = enrichment?.snrHF ?? enrichment?.snrAll {
                snrGauge(snr)
            } else if enrichment == nil {
                // Shimmer placeholder
                shimmerBar
            }
        }
    }

    private var coverageRow: some View {
        HStack(spacing: 8) {
            Label(receiver.bands, systemImage: "waveform")
                .font(.caption2)
                .foregroundStyle(.secondary)

            if let enrichment {
                antConnectedBadge(enrichment.antConnected)
            }

            availabilityBadge
        }
    }

    // MARK: - Availability

    private var availabilityBadge: some View {
        let usersNow = enrichment?.users ?? receiver.users
        let usersMax = enrichment?.usersMax ?? receiver.maxUsers
        return HStack(spacing: 4) {
            Circle()
                .fill(receiver.isAvailable ? .green : .red)
                .frame(width: 6, height: 6)
            Text("\(usersNow)/\(usersMax)")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Band Match Badge

    @ViewBuilder
    private var bandMatchBadge: some View {
        if let band = operatingBand,
           let parsed = enrichment?.parsedAntenna ?? receiver.parsedAntenna,
           parsed.bands.contains(band)
        {
            Text("Good for \(band)")
                .font(.caption2.weight(.medium))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.green.opacity(0.2))
                .clipShape(Capsule())
        }
    }

    // MARK: - Shimmer Placeholder

    private var shimmerBar: some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(Color(.systemGray5))
            .frame(width: 50, height: 6)
            .opacity(0.6)
    }

    // MARK: - Antenna Badges

    private func antennaBadges(_ parsed: ParsedAntenna) -> some View {
        HStack(spacing: 4) {
            if let type = parsed.type {
                capsuleBadge(type.rawValue, color: .blue)
            }

            ForEach(parsed.bands.prefix(3), id: \.self) { band in
                capsuleBadge(band, color: .green)
            }
            if parsed.bands.count > 3 {
                capsuleBadge("+\(parsed.bands.count - 3)", color: .green)
            }

            if let dir = parsed.directionality {
                capsuleBadge(dir, color: .secondary)
            }
        }
    }

    private func capsuleBadge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(color.opacity(0.2))
            .clipShape(Capsule())
    }

    // MARK: - SNR Gauge

    private func snrGauge(_ snr: Int) -> some View {
        HStack(spacing: 4) {
            Text("SNR")
                .font(.caption2)
                .foregroundStyle(.secondary)
            snrBar(snr)
            Text("\(snr)")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }

    private func snrBar(_ snr: Int) -> some View {
        let fill = min(Double(snr) / 40.0, 1.0)
        let color: Color = snr < 15 ? .red : snr < 25 ? .yellow : .green

        return GeometryReader { _ in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color(.systemGray5))
                RoundedRectangle(cornerRadius: 2)
                    .fill(color)
                    .frame(width: max(2, 40 * fill))
            }
        }
        .frame(width: 40, height: 6)
    }

    // MARK: - Ant Connected

    private func antConnectedBadge(_ connected: Bool) -> some View {
        HStack(spacing: 2) {
            Image(systemName: connected ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.caption2)
                .foregroundStyle(connected ? .green : .red)
            Text(connected ? "Ant OK" : "Ant Disc")
                .font(.caption2)
                .foregroundStyle(connected ? .green : .red)
        }
    }
}
