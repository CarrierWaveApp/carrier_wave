import CarrierWaveCore
import CarrierWaveData
import SwiftData
import SwiftUI

// MARK: - ParkPinView

/// Compact pin for park locations on the map
struct ParkPinView: View {
    let park: POTAPark
    let hasBoundary: Bool
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 0) {
            Image(systemName: hasBoundary ? "tree.fill" : "tree")
                .font(.system(size: 14))
                .foregroundStyle(isSelected ? .white : .green)
                .padding(6)
                .background(
                    isSelected ? Color.green : Color(.systemBackground),
                    in: Circle()
                )
                .overlay(Circle().stroke(.green, lineWidth: 1.5))
                .shadow(radius: isSelected ? 4 : 2)
        }
    }
}

// MARK: - ParkCalloutView

/// Detail callout shown when a park is selected, with async park stats.
struct ParkCalloutView: View {
    // MARK: Internal

    let park: POTAPark
    let boundary: ParkBoundary?
    var onStartSession: ((POTAPark) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            parkHeader
            parkMetadata
            myActivitySection
            statsContent
            if onStartSession != nil {
                startSessionButton
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .task(id: park.reference) {
            await loadStats()
            loadMyActivity()
        }
    }

    // MARK: Private

    @Environment(\.modelContext) private var modelContext

    @State private var stats: ParkStatsResponse?
    @State private var isLoadingStats = false
    @State private var myActivationCount = 0
    @State private var myActivationQSOCount = 0
    @State private var myHuntCount = 0

    private let activitiesClient = ActivitiesClient()
}

// MARK: - Subviews

extension ParkCalloutView {
    private var parkHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(park.reference)
                    .font(.headline.monospaced())
                Spacer()
                if let matchQuality = boundary?.matchQuality {
                    Label(
                        matchQuality,
                        systemImage: "checkmark.circle.fill"
                    )
                    .font(.caption2)
                    .foregroundStyle(.green)
                }
                EnrichedShareButton(payload: sharePayload)
                    .accessibilityLabel("Share \(park.reference)")
            }

            Text(park.name)
                .font(.subheadline)
                .foregroundStyle(.primary)
        }
    }

    private var sharePayload: EnrichedLinkPayload {
        EnrichedLinkPayload.park(
            reference: park.reference,
            name: park.name,
            state: park.state,
            latitude: park.latitude,
            longitude: park.longitude,
            userActivations: myActivationCount > 0 ? myActivationCount : nil,
            userHunts: myHuntCount > 0 ? myHuntCount : nil
        )
    }

    private var parkMetadata: some View {
        HStack(spacing: 16) {
            if let state = park.state {
                Label(state, systemImage: "mappin")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let acreage = boundary?.acreage {
                Label(
                    formatAcreage(acreage),
                    systemImage: "square.dashed"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            if let designation = boundary?.designation {
                Text(designation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Color(.systemGray5),
                        in: RoundedRectangle(cornerRadius: 4)
                    )
            }
            if let grid = park.grid {
                Label(grid, systemImage: "grid")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var myActivitySection: some View {
        if myActivationCount > 0 || myHuntCount > 0 {
            VStack(alignment: .leading, spacing: 4) {
                Divider()
                Label("My Activity", systemImage: "person.fill")
                    .font(.caption.bold())
                    .foregroundStyle(.primary)
                HStack(spacing: 16) {
                    if myActivationCount > 0 {
                        statPill(
                            value: myActivationCount,
                            label: myActivationCount == 1 ? "activation" : "activations",
                            icon: "flag.fill"
                        )
                    }
                    if myActivationQSOCount > 0 {
                        statPill(
                            value: myActivationQSOCount,
                            label: "QSOs",
                            icon: "wave.3.right"
                        )
                    }
                    if myHuntCount > 0 {
                        statPill(
                            value: myHuntCount,
                            label: myHuntCount == 1 ? "hunt" : "hunts",
                            icon: "target"
                        )
                    }
                }
                kiloProgressBar
            }
        }
    }

    @ViewBuilder
    private var kiloProgressBar: some View {
        if myActivationQSOCount > 0 {
            let kiloTarget = 1_000
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text("Kilo Progress")
                        .font(.caption2.weight(.medium))
                    Spacer()
                    if myActivationQSOCount >= kiloTarget {
                        Label("Earned", systemImage: "checkmark.seal.fill")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.green)
                    } else {
                        Text("\(kiloTarget - myActivationQSOCount) to go")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                ProgressView(
                    value: min(
                        Double(myActivationQSOCount) / Double(kiloTarget),
                        1.0
                    )
                )
                .tint(myActivationQSOCount >= kiloTarget ? .green : .orange)
            }
        }
    }

    private var startSessionButton: some View {
        Button {
            onStartSession?(park)
        } label: {
            Label("Start POTA Session", systemImage: "play.fill")
                .font(.subheadline.weight(.medium))
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(.green)
    }

    @ViewBuilder
    private var statsContent: some View {
        if isLoadingStats {
            HStack {
                ProgressView()
                    .controlSize(.small)
                Text("Loading stats…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } else if let stats {
            parkStatsView(stats)
        }
    }

    private func parkStatsView(_ stats: ParkStatsResponse) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()

            statCountsRow(stats)

            if !stats.topActivators.isEmpty {
                leaderboardSection(
                    title: "Top Activators",
                    icon: "antenna.radiowaves.left.and.right",
                    entries: stats.topActivators
                )
            }

            if !stats.topHunters.isEmpty {
                leaderboardSection(
                    title: "Top Hunters",
                    icon: "target",
                    entries: stats.topHunters
                )
            }
        }
    }

    private func statCountsRow(
        _ stats: ParkStatsResponse
    ) -> some View {
        HStack(spacing: 16) {
            statPill(
                value: stats.totalActivations,
                label: "activations",
                icon: "flag.fill"
            )
            statPill(
                value: stats.totalQsos,
                label: "QSOs",
                icon: "wave.3.right"
            )
        }
    }

    private func statPill(
        value: Int,
        label: String,
        icon: String
    ) -> some View {
        Label {
            Text("\(value) \(label)")
        } icon: {
            Image(systemName: icon)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private func leaderboardSection(
        title: String,
        icon: String,
        entries: [RankedCallsign]
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: icon)
                .font(.caption.bold())
                .foregroundStyle(.primary)

            ForEach(
                Array(entries.prefix(5).enumerated()),
                id: \.element.callsign
            ) { rank, entry in
                HStack {
                    Text("\(rank + 1).")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.tertiary)
                        .frame(width: 16, alignment: .trailing)
                    Text(entry.callsign)
                        .font(.caption.monospaced())
                    Spacer()
                    Text("\(entry.count)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

// MARK: - Data Loading

extension ParkCalloutView {
    private func loadStats() async {
        isLoadingStats = true
        defer { isLoadingStats = false }

        do {
            stats = try await activitiesClient.fetchParkStats(
                reference: park.reference
            )
        } catch {
            // Stats are supplemental — fail silently
            stats = nil
        }
    }

    private func loadMyActivity() {
        let ref = park.reference
        // Count activations: unique UTC dates I was at this park
        let activationDesc = BoundedDescriptor<QSO>(
            predicate: #Predicate<QSO> { qso in
                qso.parkReference == ref && !qso.isHidden
            },
            limit: BoundedDescriptor<QSO>.maxLimit
        )
        let activationQSOs = (try? modelContext.boundedFetch(activationDesc)) ?? []
        let nonMetadataQSOs = activationQSOs.filter {
            !QSOMode.isMetadata($0.mode)
        }
        var utcCal = Calendar(identifier: .gregorian)
        utcCal.timeZone = TimeZone(identifier: "UTC")!
        let activationDates = Set(
            nonMetadataQSOs.map { utcCal.startOfDay(for: $0.timestamp) }
        )
        myActivationCount = activationDates.count
        myActivationQSOCount = nonMetadataQSOs.count

        // Count hunts: individual QSOs where they were at this park
        let huntDesc = BoundedDescriptor<QSO>(
            predicate: #Predicate<QSO> { qso in
                qso.theirParkReference == ref && !qso.isHidden
            },
            limit: BoundedDescriptor<QSO>.maxLimit
        )
        let huntQSOs = (try? modelContext.boundedFetch(huntDesc)) ?? []
        myHuntCount = huntQSOs.filter {
            !QSOMode.isMetadata($0.mode)
        }.count
    }

    private func formatAcreage(_ acres: Double) -> String {
        if acres >= 1_000_000 {
            String(format: "%.1fM acres", acres / 1_000_000)
        } else if acres >= 1_000 {
            String(format: "%.0fK acres", acres / 1_000)
        } else {
            String(format: "%.0f acres", acres)
        }
    }
}
