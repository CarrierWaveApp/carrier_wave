import SwiftUI

// MARK: - HeardRow

/// Heard row anatomy (spec §13): band badge → tier dot → callsign →
/// absolute freq (faint — needed to tune, no anchor deltas here in v1) →
/// WPM if skimmer → one chip → age + `N×`. Full opacity (no freshness
/// fade) except `rbn` dim text and the WPM-ceiling dim.
struct HeardRow: View {
    // MARK: Internal

    let station: HeardStation
    let profile: GoalProfile
    let isWPMDimmed: Bool
    let now: Date
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                bandBadge
                TierDot(tier: tier)
                Text(station.callsign)
                    .font(.subheadline.weight(.semibold).monospaced())
                    .foregroundStyle(
                        tier == .rbn ? BandScopeTheme.dim : BandScopeTheme.text
                    )
                    .lineLimit(1)
                Text(String(format: "%.4f", station.latest.spot.frequencyKHz / 1_000))
                    .font(.caption2.monospaced())
                    .foregroundStyle(BandScopeTheme.faint)
                wpmLabel
                chip
                Spacer(minLength: 4)
                if isWPMDimmed {
                    Image(systemName: "line.3.horizontal.decrease")
                        .font(.caption2)
                        .foregroundStyle(BandScopeTheme.faint)
                        .accessibilityLabel("Dimmed by WPM ceiling")
                }
                ageLabel
            }
            .padding(.horizontal, 16)
            .frame(height: BandScopeTunables.rowHeight)
        }
        .buttonStyle(.plain)
        .opacity(isWPMDimmed ? BandScopeTunables.filteredDimOpacity : 1)
    }

    // MARK: Private

    private var tier: SpotTier {
        station.latest.tier(for: profile)
    }

    private var bandBadge: some View {
        Text(station.latest.spot.band)
            .font(.caption2.weight(.medium).monospaced())
            .padding(.vertical, 2)
            .frame(minWidth: 34)
            .background(BandScopeTheme.blue.opacity(0.2), in: Capsule())
            .foregroundStyle(BandScopeTheme.text)
    }

    @ViewBuilder
    private var wpmLabel: some View {
        if station.latest.spot.source.isAutomated, let wpm = station.latest.spot.wpm {
            Text("\(wpm) wpm")
                .font(.caption2.monospaced())
                .foregroundStyle(BandScopeTheme.dim)
        }
    }

    @ViewBuilder
    private var chip: some View {
        if let need = station.latest.goalChip(for: profile) {
            GoalChip(label: need.label, tier: .needed)
        }
    }

    private var ageLabel: some View {
        HStack(spacing: 3) {
            Text(BandScopeAge.compact(station.latest.spot.timestamp, now: now))
            if station.heardCount > 1 {
                Text("· \(station.heardCount)×")
            }
        }
        .font(.caption2.monospaced())
        .foregroundStyle(BandScopeTheme.faint)
    }
}

// MARK: - NeedsShelf

/// Pinned horizontal strip of amber cards for every needed-tier station
/// in the feed (spec §13) — priority lives here, never in the sort.
struct NeedsShelf: View {
    let model: BandScopeViewModel

    @Binding var peekSpot: EnrichedSpot?

    var body: some View {
        let stations = model.needsShelfStations
        if !stations.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(stations) { station in
                        NeedsShelfCard(
                            station: station, profile: model.activeProfile
                        ) {
                            peekSpot = station.latest
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
            .padding(.vertical, 6)
        }
    }
}

// MARK: - NeedsShelfCard

private struct NeedsShelfCard: View {
    let station: HeardStation
    let profile: GoalProfile
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 3) {
                Text(station.callsign)
                    .font(.footnote.weight(.semibold).monospaced())
                    .foregroundStyle(BandScopeTheme.text)
                HStack(spacing: 5) {
                    if let need = station.latest.goalChip(for: profile) {
                        GoalChip(label: need.label, tier: .needed)
                    }
                    Text(station.latest.spot.band)
                        .font(.caption2.monospaced())
                        .foregroundStyle(BandScopeTheme.dim)
                    Text(BandScopeAge.compact(station.latest.spot.timestamp))
                        .font(.caption2.monospaced())
                        .foregroundStyle(BandScopeTheme.faint)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(BandScopeTheme.surface, in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(BandScopeTheme.amber.opacity(0.6))
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - BandFilterTiles

/// Per-band mini density strips (spec §13): tier-colored marks positioned
/// within the band's spot range; tap toggles the band in/out of the feed.
/// At least one band stays on (an all-off selection reads as all-on).
struct BandFilterTiles: View {
    // MARK: Internal

    let model: BandScopeViewModel

    var body: some View {
        let bands = model.heardBands
        if bands.count > 1 {
            HStack(spacing: 8) {
                ForEach(bands, id: \.self) { band in
                    tile(for: band)
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
        }
    }

    // MARK: Private

    private func tile(for band: String) -> some View {
        let enabled = !model.disabledHeardBands.contains(band)
        return Button {
            if enabled {
                // ≥1 band always on (§13): refuse to disable the last one.
                let enabledCount = model.heardBands
                    .count { !model.disabledHeardBands.contains($0) }
                if enabledCount > 1 {
                    model.disabledHeardBands.insert(band)
                }
            } else {
                model.disabledHeardBands.remove(band)
            }
        } label: {
            VStack(spacing: 3) {
                Text(band)
                    .font(.caption2.weight(.semibold).monospaced())
                    .foregroundStyle(enabled ? BandScopeTheme.text : BandScopeTheme.faint)
                densityStrip(for: band)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(BandScopeTheme.surface, in: RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(enabled ? BandScopeTheme.line : BandScopeTheme.line.opacity(0.4))
            )
            .opacity(enabled ? 1 : 0.5)
        }
        .buttonStyle(.plain)
    }

    private func densityStrip(for band: String) -> some View {
        let spots = model.allSpots.filter { $0.spot.band == band }
        let profile = model.activeProfile
        let freqs = spots.map(\.spot.frequencyKHz)
        let low = freqs.min() ?? 0
        let span = max((freqs.max() ?? 0) - low, 0.001)
        return Canvas { context, size in
            for spot in spots {
                let xPos = CGFloat((spot.spot.frequencyKHz - low) / span) * size.width
                let tier = spot.tier(for: profile)
                context.fill(
                    Path(CGRect(x: xPos - 0.75, y: 0, width: 1.5, height: size.height)),
                    with: .color(
                        BandScopeTheme.color(for: tier)
                            .opacity(tier == .rbn ? 0.45 : 0.9)
                    )
                )
            }
        }
        .frame(width: 44, height: 8)
    }
}
