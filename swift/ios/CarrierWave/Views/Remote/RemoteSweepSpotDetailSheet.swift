import CarrierWaveCore
import CarrierWaveData
import SwiftData
import SwiftUI

// MARK: - RemoteSweepSpotDetailSheet

//
// Spot detail sheet that follows Carrier Wave's design language: grouped
// backgrounds, system semantic colors, monospaced callsigns/frequencies,
// stat-box pattern for the quick-facts grid, banner pattern for the source
// hero and the comment, `.borderedProminent` green Tune button. Wrapped in
// the standard NavigationStack with a Done dismiss button per the sheet
// pattern in `docs/design-language.md`.

struct RemoteSweepSpotDetailSheet: View {
    // MARK: Internal

    let spot: RemoteSpot

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    sourceHero
                    if !mergedClubs.isEmpty {
                        clubsRow
                    }
                    frequencyCard
                    quickFactsGrid
                    if let comment = spot.comment?.trimmingCharacters(in: .whitespacesAndNewlines),
                       !comment.isEmpty
                    {
                        commentBanner(comment)
                    }
                    tuneButton
                }
                .padding(16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Spot")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task(id: spot.callsign) {
                loadClubs()
            }
        }
    }

    // MARK: Private

    @Environment(RemoteSweepCoordinator.self) private var coordinator
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var fetchedClubs: [String] = []

    private var mergedClubs: [String] {
        var clubs = fetchedClubs
        var seen = Set(clubs.map { $0.uppercased() })
        if SKCCMembershipStore.shared.member(for: spot.callsign) != nil,
           !seen.contains("SKCC")
        {
            clubs.append("SKCC")
            seen.insert("SKCC")
        }
        return clubs
    }

    private var clubsRow: some View {
        FlowLayout(spacing: 6) {
            ForEach(mergedClubs, id: \.self) { club in
                Text(club)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color.accentColor)
                    .badgePill(
                        Color.accentColor.opacity(0.18),
                        horizontalPadding: 8,
                        verticalPadding: 4
                    )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityLabel("Club memberships: \(mergedClubs.joined(separator: ", "))")
    }

    // MARK: - Source hero (banner pattern)

    private var sourceHero: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: sourceIcon)
                    .font(.title)
                    .foregroundStyle(sourceColor)
                    .frame(width: 36)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(spot.callsign)
                        .font(.title.weight(.bold).monospaced())
                        .foregroundStyle(.primary)
                    if let subtitle = heroSubtitle {
                        Text(subtitle)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if spot.needed {
                    needBadge
                }
            }
            HStack(spacing: 6) {
                Text(spot.source.uppercased())
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(sourceColor.opacity(0.2))
                    .clipShape(Capsule())
                    .foregroundStyle(sourceColor)
                Text(ageString(for: spot.spottedAt))
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(sourceColor.opacity(0.15))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var needBadge: some View {
        Text("NEEDED")
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.orange)
            .foregroundStyle(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 3))
            .accessibilityLabel("Needed entity or band slot")
    }

    // MARK: - Frequency card

    private var frequencyCard: some View {
        VStack(spacing: 8) {
            Text(formatFrequency(spot.freqHz))
                .font(.system(size: 44, weight: .bold, design: .monospaced))
                .foregroundStyle(.blue)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
            Text("MHz")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            HStack(spacing: 6) {
                if let mode = spot.mode {
                    capsuleBadge(mode, tint: .blue)
                }
                if let band = spot.band {
                    capsuleBadge(band, tint: .blue)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(16)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Quick facts grid (stat-box pattern)

    private var quickFactsGrid: some View {
        let facts = factTiles
        let columns = [
            GridItem(.flexible(), spacing: 8),
            GridItem(.flexible(), spacing: 8),
            GridItem(.flexible(), spacing: 8),
        ]
        return LazyVGrid(columns: columns, spacing: 8) {
            ForEach(facts) { fact in
                statBox(fact)
            }
        }
    }

    // MARK: - Tune action

    private var tuneButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            Task {
                await coordinator.tune(freqHz: spot.freqHz, mode: spot.mode)
                dismiss()
            }
        } label: {
            Label("Tune Sweep", systemImage: "antenna.radiowaves.left.and.right")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
        }
        .buttonStyle(.borderedProminent)
        .tint(.green)
        .padding(.top, 4)
    }

    private func statBox(_ fact: Fact) -> some View {
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

    // MARK: - Comment banner

    private func commentBanner(_ comment: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "text.bubble.fill")
                .foregroundStyle(.blue)
                .font(.subheadline)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Comment")
                    .font(.subheadline.weight(.semibold))
                Text(comment)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding()
        .background(Color.blue.opacity(0.15))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Club memberships

    /// Club names for this spot's callsign, from the shared in-memory cache
    /// (rebuilt from the Rust store after every sync).
    private func loadClubs() {
        fetchedClubs = ClubsSyncService.shared.clubs(for: spot.callsign).sorted()
    }
}
