import CarrierWaveData
import SwiftUI

// MARK: - IdentityCard

/// Canonical operator identity card. Visually mirrors the
/// `RemoteSweepSpotDetailSheet` source-hero pattern: tinted accent
/// banner with icon + callsign + subtitle + trailing license pill,
/// followed by a stat-box grid for the rest of the metadata. Single
/// rendering implementation; surfaces vary only by the content they
/// hand in via `IdentityCardContent`.
struct IdentityCard: View {
    // MARK: Internal

    let content: IdentityCardContent

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            heroBanner
            if !content.factTiles.isEmpty {
                factsGrid
            }
            if !content.clubBadges.isEmpty {
                clubBadgePills
            }
            if let footnote = content.footnote {
                footnoteRow(footnote)
            }
        }
    }

    // MARK: Private

    // MARK: Hero banner (matches spot-source-hero pattern)

    private var heroBanner: some View {
        VStack(alignment: .leading, spacing: 12) {
            heroTopRow
            bottomStripContent
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.accentColor.opacity(0.15))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var heroTopRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.title)
                .foregroundStyle(Color.accentColor)
                .frame(width: 36)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                callsignLine
                if let subtitle = content.heroSubtitle {
                    Text(subtitle)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            heroTrailing
        }
    }

    private var callsignLine: some View {
        HStack(spacing: 6) {
            Text(content.callsign)
                .font(.title.weight(.bold).monospaced())
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .accessibilityLabel("Callsign \(content.callsign)")
            if let emoji = content.emoji, !emoji.isEmpty {
                Text(emoji)
                    .font(.title3)
                    .accessibilityHidden(true)
            }
        }
    }

    @ViewBuilder
    private var heroTrailing: some View {
        if let license = content.licenseClass {
            Text(license)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color(.systemBackground))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.accentColor)
                .clipShape(Capsule())
                .accessibilityLabel("\(license) license")
        } else if content.isLookingUp {
            ProgressView()
                .controlSize(.small)
        }
    }

    @ViewBuilder
    private var bottomStripContent: some View {
        if content.flag != nil || content.bottomStripText != nil {
            HStack(spacing: 6) {
                if let flag = content.flag {
                    Text(flag)
                        .font(.caption)
                        .accessibilityHidden(true)
                }
                if let text = content.bottomStripText {
                    Text(text)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
        }
    }

    // MARK: Stat-box grid (matches spot quick-facts pattern)

    private var factsGrid: some View {
        let columns = [
            GridItem(.flexible(), spacing: 8),
            GridItem(.flexible(), spacing: 8),
            GridItem(.flexible(), spacing: 8),
        ]
        return LazyVGrid(columns: columns, spacing: 8) {
            ForEach(content.factTiles) { fact in
                factTileView(fact)
            }
        }
    }

    private var clubBadgePills: some View {
        FlowLayout(spacing: 6) {
            ForEach(content.clubBadges, id: \.self) { badge in
                Text(badge)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color.accentColor)
                    .badgePill(Color.accentColor.opacity(0.18), horizontalPadding: 8, verticalPadding: 4)
            }
        }
    }

    private func factTileView(_ fact: IdentityCardContent.FactTile) -> some View {
        VStack(spacing: 4) {
            Image(systemName: fact.icon)
                .font(.title3)
                .foregroundStyle(fact.tint)
                .accessibilityHidden(true)
            Text(fact.value)
                .font(.subheadline.weight(.semibold).monospaced())
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(fact.label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Color(.systemGray5))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(fact.label): \(fact.value)")
    }

    private func footnoteRow(_ footnote: IdentityCardContent.Footnote) -> some View {
        HStack(spacing: 8) {
            Image(systemName: footnote.systemImage)
                .font(.caption)
                .foregroundStyle(footnote.color)
                .accessibilityHidden(true)
            Text(footnote.text)
                .font(.caption)
                .foregroundStyle(footnote.color)
        }
    }
}
