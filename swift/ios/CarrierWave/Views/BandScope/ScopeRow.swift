import SwiftUI

// MARK: - ScopeRow

/// One Scope list row (spec §8): freq column · tier dot · callsign ·
/// WPM (RBN only) · ONE chip max · age. Pileup clusters render one row
/// with member dots and `+N on freq` (§10). Explicitly NOT here: dB,
/// source labels, park refs, club identity strings (§8/§14).
struct ScopeRow: View {
    // MARK: Internal

    let cluster: ScopeCluster
    let profile: GoalProfile
    let anchor: BandScopeAnchor?
    let now: Date
    let opacity: Double
    let isExpanded: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                FrequencyColumn(
                    frequencyKHz: cluster.minFrequencyKHz,
                    anchor: anchor,
                    now: now
                )
                tierDots
                Text(cluster.lead.spot.callsign)
                    .font(.subheadline.weight(.semibold).monospaced())
                    .foregroundStyle(
                        leadTier == .rbn ? BandScopeTheme.dim : BandScopeTheme.text
                    )
                    .lineLimit(1)
                if cluster.isPileup {
                    Text("+\(cluster.spots.count - 1) on freq")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(BandScopeTheme.color(for: clusterTier))
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(BandScopeTheme.faint)
                } else {
                    wpmLabel
                    chip
                }
                Spacer(minLength: 4)
                Text(BandScopeAge.compact(cluster.lead.spot.timestamp, now: now))
                    .font(.caption2.monospaced())
                    .foregroundStyle(BandScopeTheme.faint)
            }
            .padding(.horizontal, 16)
            .frame(height: BandScopeTunables.rowHeight)
            .fontWeight(isNearAnchor ? .bold : nil)
        }
        .buttonStyle(.plain)
        .opacity(opacity)
    }

    // MARK: Private

    private var leadTier: SpotTier {
        cluster.lead.tier(for: profile)
    }

    /// Cluster tier = max tier of members (§10).
    private var clusterTier: SpotTier {
        cluster.spots.map { $0.tier(for: profile) }.max() ?? .rbn
    }

    /// Rows within ±1 kHz of the anchor render bold/bright (§6).
    private var isNearAnchor: Bool {
        guard let anchor else {
            return false
        }
        return abs(cluster.minFrequencyKHz - anchor.frequencyKHz)
            <= BandScopeTunables.nearAnchorBoldKHz
    }

    /// One dot per member (capped so a monster pileup doesn't eat the row).
    private var tierDots: some View {
        HStack(spacing: 3) {
            ForEach(Array(cluster.spots.prefix(4).enumerated()), id: \.offset) { _, spot in
                TierDot(tier: spot.tier(for: profile))
            }
        }
    }

    @ViewBuilder
    private var wpmLabel: some View {
        // Promoted for skimmer spots — CW hunters triage by speed (§8).
        if cluster.lead.spot.source.isAutomated, let wpm = cluster.lead.spot.wpm {
            Text("\(wpm) wpm")
                .font(.caption2.monospaced())
                .foregroundStyle(BandScopeTheme.dim)
        }
    }

    @ViewBuilder
    private var chip: some View {
        if let need = cluster.lead.goalChip(for: profile) {
            GoalChip(label: need.label, tier: .needed)
        }
    }
}

// MARK: - ScopeSubRow

/// Expanded pileup member (§10): indented, freq column omitted; suspect
/// busted copies badged, never deleted.
struct ScopeSubRow: View {
    let spot: EnrichedSpot
    let profile: GoalProfile
    let isBustedSuspect: Bool
    let opacity: Double
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                Spacer().frame(width: 66)
                TierDot(tier: spot.tier(for: profile))
                Text(spot.spot.callsign)
                    .font(.footnote.weight(.semibold).monospaced())
                    .foregroundStyle(
                        spot.tier(for: profile) == .rbn
                            ? BandScopeTheme.dim : BandScopeTheme.text
                    )
                if isBustedSuspect {
                    Text("likely busted")
                        .font(.caption2.weight(.medium))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            BandScopeTheme.gray.opacity(0.2), in: Capsule()
                        )
                        .foregroundStyle(BandScopeTheme.dim)
                }
                if let need = spot.goalChip(for: profile) {
                    GoalChip(label: need.label, tier: .needed)
                }
                Spacer(minLength: 4)
            }
            .padding(.horizontal, 16)
            .frame(height: 34)
        }
        .buttonStyle(.plain)
        .opacity(opacity)
    }
}

// MARK: - FrequencyColumn

/// 58pt fixed column (§8): absolute `14.0625`, or signed Δ kHz when an
/// anchor is live — delta ink decays with anchor trust (§6).
struct FrequencyColumn: View {
    let frequencyKHz: Double
    let anchor: BandScopeAnchor?
    let now: Date

    var body: some View {
        Group {
            if let anchor {
                let delta = frequencyKHz - anchor.frequencyKHz
                Text(String(format: "%+.1f", delta))
                    .foregroundStyle(BandScopeTheme.text)
                    .opacity(anchor.trust(at: now))
            } else {
                Text(String(format: "%.4f", frequencyKHz / 1_000))
                    .foregroundStyle(BandScopeTheme.dim)
            }
        }
        .font(.caption.monospaced())
        .frame(width: 58, alignment: .leading)
    }
}

// MARK: - TierDot

struct TierDot: View {
    let tier: SpotTier

    var body: some View {
        Circle()
            .fill(BandScopeTheme.color(for: tier))
            .frame(width: 6, height: 6)
            .shadow(
                color: BandScopeTheme.glows(tier)
                    ? BandScopeTheme.amber.opacity(0.6) : .clear,
                radius: 4
            )
    }
}

// MARK: - GoalChip

/// A chip says why the user cares, never what the spot is (§9).
struct GoalChip: View {
    let label: String
    let tier: SpotTier

    var body: some View {
        Text(label)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                BandScopeTheme.color(for: tier)
                    .opacity(BandScopeTheme.chipBackgroundAlpha),
                in: Capsule()
            )
            .foregroundStyle(BandScopeTheme.color(for: tier))
            .lineLimit(1)
    }
}

// MARK: - BandScopeAge

/// Compact age text (§7): `25s`, `11m`.
enum BandScopeAge {
    static func compact(_ spotted: Date, now: Date = Date()) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(spotted)))
        if seconds < 60 {
            return "\(seconds)s"
        }
        if seconds < 3_600 {
            return "\(seconds / 60)m"
        }
        return "\(seconds / 3_600)h"
    }
}
