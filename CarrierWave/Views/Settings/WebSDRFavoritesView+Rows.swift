import CarrierWaveData
import SwiftUI

// MARK: - Compact Row Rendering

extension WebSDRFavoritesView {
    func compactRow(_ receiver: KiwiSDRReceiver) -> some View {
        let enrichment = enrichments[receiver.id]
        let parsed = enrichment?.parsedAntenna ?? receiver.parsedAntenna
        return Button {
            selectedReceiver = receiver
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                // Row 1: Name + distance + chevron
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

                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                }

                // Row 2: Location
                Text(receiver.location)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                // Row 3: Pills + SNR + availability
                detailRow(
                    parsed: parsed,
                    receiver: receiver,
                    enrichment: enrichment
                )
            }
            .padding(.vertical, 2)
        }
        .tint(.primary)
    }

    func compactFavoriteRow(
        _ favorite: WebSDRFavorite
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(favorite.displayName)
                .font(.subheadline)
                .fontWeight(.medium)
                .lineLimit(1)
            Text(favorite.location)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.vertical, 2)
    }

    func detailRow(
        parsed: ParsedAntenna?,
        receiver: KiwiSDRReceiver,
        enrichment: KiwiSDRStatusFetcher.ReceiverStatus?
    ) -> some View {
        HStack(spacing: 4) {
            if let parsed {
                if let type = parsed.type {
                    capsuleBadge(type.rawValue, color: .blue)
                }
                ForEach(parsed.bands.prefix(3), id: \.self) { band in
                    capsuleBadge(band, color: .green)
                }
                if parsed.bands.count > 3 {
                    capsuleBadge(
                        "+\(parsed.bands.count - 3)",
                        color: .green
                    )
                }
                if let dir = parsed.directionality {
                    capsuleBadge(dir, color: .secondary)
                }
            }

            Spacer()

            if let snr = enrichment?.snrHF ?? enrichment?.snrAll {
                snrDot(snr)
            }

            availabilityDot(
                receiver: receiver, enrichment: enrichment
            )
        }
    }

    func capsuleBadge(
        _ text: String, color: Color
    ) -> some View {
        Text(text)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(color.opacity(0.2))
            .clipShape(Capsule())
    }

    func snrDot(_ snr: Int) -> some View {
        let color: Color = snr < 15 ? .red : snr < 25 ? .yellow : .green
        return HStack(spacing: 2) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text("\(snr)")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }

    func availabilityDot(
        receiver: KiwiSDRReceiver,
        enrichment: KiwiSDRStatusFetcher.ReceiverStatus?
    ) -> some View {
        let usersNow = enrichment?.users ?? receiver.users
        let usersMax = enrichment?.usersMax ?? receiver.maxUsers
        return HStack(spacing: 3) {
            Circle()
                .fill(receiver.isAvailable ? .green : .red)
                .frame(width: 6, height: 6)
            Text("\(usersNow)/\(usersMax)")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}
