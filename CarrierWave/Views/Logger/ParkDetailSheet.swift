// Park Detail Sheet
//
// Shows detailed POTA park information including stats,
// leaderboards (top activators and hunters), and recent
// activations. Data is fetched from the public POTA API.
// Models and loader are in POTAClient+ParkDetail.swift
// (separate file to avoid MainActor isolation on Decodable).

import CarrierWaveData
import SwiftUI

// MARK: - ParkDetailSheet

/// Shows detailed park info with stats, leaderboard, and recent activations
struct ParkDetailSheet: View {
    // MARK: Internal

    let reference: String

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    parkHeader
                    statsRow
                    leaderboardSection
                    recentActivationsSection
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(reference)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .landscapeAdaptiveDetents(portrait: [.medium, .large])
        .presentationDragIndicator(.visible)
        .task { await loadData() }
    }

    // MARK: Private

    @Environment(\.dismiss) private var dismiss

    @State private var park: POTAPark?
    @State private var stats: POTAParkStatsResponse?
    @State private var leaderboard: POTAParkLeaderboardResponse?
    @State private var activations: [POTAParkActivationEntry] = []
    @State private var isLoading = true
    @State private var leaderboardTab = 0

    private var userCallsign: String {
        CallsignAliasService.shared.getCurrentCallsign()?.uppercased() ?? ""
    }

    // MARK: - Header

    private var parkHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let park {
                Text(park.name)
                    .font(.headline)

                HStack(spacing: 4) {
                    if let state = park.state {
                        Text(state)
                    }
                    if park.state != nil {
                        Text("·")
                    }
                    Text(park.locationDesc)
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                if let grid = park.grid {
                    Text(grid)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
            } else {
                Text(reference)
                    .font(.headline)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Stats Row

    @ViewBuilder
    private var statsRow: some View {
        if let stats {
            HStack(spacing: 8) {
                parkStatBox(
                    value: formatNumber(stats.activations),
                    label: "Activations",
                    icon: "leaf"
                )
                parkStatBox(
                    value: formatNumber(stats.contacts),
                    label: "Contacts",
                    icon: "antenna.radiowaves.left.and.right"
                )
                parkStatBox(
                    value: formatNumber(stats.attempts),
                    label: "Attempts",
                    icon: "figure.walk"
                )
            }
        } else if isLoading {
            HStack(spacing: 8) {
                parkStatBox(value: "--", label: "Activations", icon: "leaf")
                parkStatBox(value: "--", label: "Contacts", icon: "antenna.radiowaves.left.and.right")
                parkStatBox(value: "--", label: "Attempts", icon: "figure.walk")
            }
            .opacity(0.6)
        }
    }

    // MARK: - Leaderboard

    @ViewBuilder
    private var leaderboardSection: some View {
        if let leaderboard {
            VStack(alignment: .leading, spacing: 8) {
                Picker("Leaderboard", selection: $leaderboardTab) {
                    Text("Activators").tag(0)
                    Text("Hunters").tag(1)
                }
                .pickerStyle(.segmented)

                let entries = leaderboardTab == 0
                    ? leaderboard.activations
                    : leaderboard.hunterQsos
                let unit = leaderboardTab == 0 ? "activations" : "QSOs"

                if entries.isEmpty {
                    Text("No data available")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                            leaderboardRow(
                                rank: index + 1,
                                callsign: entry.callsign,
                                count: entry.count,
                                unit: unit
                            )
                            if index < entries.count - 1 {
                                Divider().padding(.leading, 32)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                    .background(Color(.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
        }
    }

    // MARK: - Recent Activations

    @ViewBuilder
    private var recentActivationsSection: some View {
        if !activations.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Recent Activations")
                    .font(.headline)

                VStack(spacing: 0) {
                    ForEach(Array(activations.enumerated()), id: \.element.id) { index, entry in
                        activationRow(entry)
                        if index < activations.count - 1 {
                            Divider().padding(.leading, 12)
                        }
                    }
                }
                .padding(.vertical, 4)
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    private func parkStatBox(value: String, label: String, icon: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.blue)
            Text(value)
                .font(.title3.monospacedDigit().weight(.semibold))
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Color(.systemGray5))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(value) \(label)")
    }

    private func leaderboardRow(
        rank: Int, callsign: String, count: Int, unit: String
    ) -> some View {
        let isUser = callsign.uppercased() == userCallsign
        return HStack(spacing: 8) {
            Text("\(rank)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 20, alignment: .trailing)

            Text(callsign)
                .font(.subheadline.monospaced().weight(.medium))
                .foregroundStyle(isUser ? .blue : .primary)

            Spacer()

            Text("\(formatNumber(count)) \(unit)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Rank \(rank), \(callsign), \(count) \(unit)")
    }

    private func activationRow(_ entry: POTAParkActivationEntry) -> some View {
        let isUser = entry.activeCallsign.uppercased() == userCallsign
        return HStack(spacing: 8) {
            Text(entry.activeCallsign)
                .font(.subheadline.monospaced().weight(.medium))
                .foregroundStyle(isUser ? .blue : .primary)

            Text(entry.formattedDate)
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            modeBadges(entry)

            if isUser {
                Image(systemName: "star.fill")
                    .font(.caption2)
                    .foregroundStyle(.blue)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(entry.activeCallsign), \(entry.formattedDate), \(entry.totalQSOs) QSOs"
        )
    }

    private func modeBadges(_ entry: POTAParkActivationEntry) -> some View {
        HStack(spacing: 4) {
            if entry.qsosCW > 0 {
                modeBadge("\(entry.qsosCW) CW", color: .green)
            }
            if entry.qsosDATA > 0 {
                modeBadge("\(entry.qsosDATA) DATA", color: .blue)
            }
            if entry.qsosPHONE > 0 {
                modeBadge("\(entry.qsosPHONE) PH", color: .orange)
            }
        }
    }

    private func modeBadge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption2.monospacedDigit())
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(color.opacity(0.2))
            .clipShape(Capsule())
    }

    // MARK: - Data Loading

    private func loadData() async {
        park = POTAParksCache.shared.parkSync(for: reference)

        let loader = ParkDetailLoader()
        async let statsResult = loader.fetchStats(reference: reference)
        async let leaderboardResult = loader.fetchLeaderboard(reference: reference)
        async let activationsResult = loader.fetchActivations(reference: reference)

        stats = try? await statsResult
        leaderboard = try? await leaderboardResult
        activations = await (try? activationsResult) ?? []
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
    Text("Tap to open")
        .sheet(isPresented: .constant(true)) {
            ParkDetailSheet(reference: "US-0189")
        }
}
