// Selected Park Card
//
// Prominent, enriched display of a park the operator is about to
// activate. Once a park is chosen this replaces the compact chip +
// inline search box: it shows the reference and name large, makes it
// clear this is the park being activated, and pulls past-activation
// stats plus the activator leaderboard from the public POTA API
// (see POTAClient+ParkDetail.swift). Tapping opens the full
// ParkDetailSheet with the complete history.

import CarrierWaveCore
import CarrierWaveData
import SwiftUI

// MARK: - SelectedParkCard

/// Enriched "you're activating this park" card shown in the session wizard.
struct SelectedParkCard: View {
    // MARK: Internal

    let reference: String
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button {
                showDetail = true
            } label: {
                content
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            removeButton
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.green.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.green.opacity(0.3), lineWidth: 1)
        )
        .sheet(isPresented: $showDetail) {
            ParkDetailSheet(reference: reference)
        }
        .task { await loadData() }
    }

    // MARK: Private

    @State private var park: POTAPark?
    @State private var stats: POTAParkStatsResponse?
    @State private var leaderboard: POTAParkLeaderboardResponse?
    @State private var isLoading = true
    @State private var showDetail = false

    private var userCallsign: String {
        CallsignAliasService.shared.getCurrentCallsign()?.uppercased() ?? ""
    }

    // MARK: - Content

    private var content: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Image(systemName: "leaf.fill")
                    .font(.caption2)
                    .foregroundStyle(.green)
                Text(reference)
                    .font(.headline.monospaced())
                    .foregroundStyle(.green)
                if let name = park?.name {
                    Text(name)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .layoutPriority(-1)
                }
            }

            metricsLine
        }
    }

    /// Single quiet line of past-activation stats + the leaderboard leader.
    @ViewBuilder
    private var metricsLine: some View {
        if let stats {
            HStack(spacing: 6) {
                Text("\(formatNumber(stats.activations)) activations")
                Text("·")
                Text("\(formatNumber(stats.contacts)) contacts")
                if let top = leaderboard?.activations.first {
                    Text("·")
                    Image(systemName: "trophy.fill")
                        .foregroundStyle(.yellow)
                    Text(top.callsign)
                        .foregroundStyle(
                            top.callsign.uppercased() == userCallsign ? .blue : .secondary
                        )
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        } else if isLoading {
            Text("Loading activation history…")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var removeButton: some View {
        Button(action: onRemove) {
            Image(systemName: "xmark.circle.fill")
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Remove \(reference)")
    }

    // MARK: - Data Loading

    private func loadData() async {
        park = POTAParksCache.shared.parkSync(for: reference)

        let loader = ParkDetailLoader()
        async let statsResult = loader.fetchStats(reference: reference)
        async let leaderboardResult = loader.fetchLeaderboard(reference: reference)

        stats = try? await statsResult
        leaderboard = try? await leaderboardResult
        isLoading = false
    }

    private func formatNumber(_ value: Int) -> String {
        if value >= 1_000 {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
        }
        return "\(value)"
    }
}

// MARK: - Preview

#Preview {
    VStack {
        SelectedParkCard(reference: "US-0189", onRemove: {})
    }
    .padding()
}
