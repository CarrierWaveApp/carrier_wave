// Session Detail View — TOTA section.
//
// Renders the TOTA-specific enrichment for a completed (or in-progress)
// session: tile name, four-tier score ledger, path map, bonus chips,
// T3 candidate list, PEF badge, and a refresh-spots button.
//
// Per docs/features/tota-scoring.md, this is the primary surface — the brag
// sheet card and end-flow summary render condensed versions driven from
// the same `TOTAScoringInputs`.

import CarrierWaveCore
import CarrierWaveData
import SwiftUI
import UniformTypeIdentifiers

extension SessionDetailView {
    @ViewBuilder
    var totaSection: some View {
        if let session, session.activationType == .tota {
            Section {
                TOTASectionContent(
                    session: session,
                    qsos: displayQSOs,
                    onRefreshSpots: { Task { await refreshT3Spots(for: session) } },
                    refreshingSpots: refreshingT3Spots
                )
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
            }
            .sheet(isPresented: $showTOTABragSheet) {
                TOTABragSheetSheet(
                    session: session,
                    qsos: displayQSOs,
                    onDismiss: { showTOTABragSheet = false }
                )
            }
        }
    }

    func refreshT3Spots(for session: LoggingSession) async {
        await MainActor.run { refreshingT3Spots = true }
        await TOTAEnrichmentService.refreshT3Snapshot(
            for: session,
            qsos: qsos,
            client: TOTAClient.shared
        )
        await MainActor.run { refreshingT3Spots = false }
    }
}

// MARK: - TOTASectionContent

struct TOTASectionContent: View {
    // MARK: Internal

    let session: LoggingSession
    let qsos: [QSO]
    let onRefreshSpots: () -> Void
    let refreshingSpots: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            headerRow
            if hasNoQSOs {
                noQSOsBanner
            } else {
                TOTAScoreLedger(session: session, qsos: qsos)
            }
            if let pef = session.personalEffortFactor, pef > 0 {
                pefBadge(pef: pef)
            }
            bonusChipRow
            if !session.tilesActivated.isEmpty {
                TOTAPathMap(session: session)
            } else if session.activationLatitude == nil {
                noActivationCoordCTA
            } else {
                noTrackNote
            }
            if !session.totaT3Candidates.isEmpty {
                TOTAT3CandidatesList(candidates: session.totaT3Candidates)
            }
            footerRow
        }
    }

    // MARK: Private

    private var inputs: TOTAScoringInputs {
        TOTAEnrichmentService.makeScoringInputs(for: session, qsos: qsos)
    }

    private var hasNoQSOs: Bool {
        qsos.isEmpty
    }

    private var bonusChips: [TOTABonusChip] {
        var chips: [TOTABonusChip] = []
        if session.totaCategory == .mobile {
            chips.append(.init(icon: "car.fill", label: "Mobile"))
        }
        if session.qrpActivation {
            chips.append(.init(icon: "leaf", label: "QRP ×2"))
        }
        let isWinter = session.winterActivationOverride
            ?? TOTAWinterDetector.isWinter(
                latitude: session.activationLatitude,
                date: session.startedAt
            )
        if session.totaCategory == .standard, isWinter {
            chips.append(.init(icon: "snowflake", label: "Winter +20%"))
        }
        if session.totaCategory == .standard {
            if let ruck = session.ruckWeightPounds, ruck >= 5 {
                let pct = Int(floor(ruck / 5)) * 5
                chips.append(.init(icon: "backpack", label: "Ruck +\(pct)%"))
            }
            if let elev = session.activationElevationGainFeet, elev >= 200 {
                let pct = Int(floor(elev / 200)) * 2
                chips.append(.init(icon: "mountain.2", label: "Elev +\(pct)%"))
            }
            if session.withPets {
                chips.append(.init(icon: "pawprint", label: "Pets +15%"))
            }
            if session.withKids {
                chips.append(.init(icon: "figure.2.and.child.holdinghands", label: "Kids +20%"))
            }
        }
        if session.winlinkSent {
            chips.append(.init(icon: "envelope", label: "Winlink +5"))
        }
        if session.aprsSent {
            chips.append(.init(icon: "antenna.radiowaves.left.and.right", label: "APRS +5"))
        }
        if session.varacSent {
            chips.append(.init(icon: "envelope.badge", label: "VarAC +5"))
        }
        if session.adaptiveSport {
            chips.append(.init(icon: "figure.roll", label: "Adaptive"))
        }
        return chips
    }

    private var headerRow: some View {
        HStack(alignment: .firstTextBaseline) {
            Image(systemName: "square.grid.3x3.fill")
                .foregroundStyle(.purple)
            Text("TOTA")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.purple)
            if !session.tilesActivated.isEmpty {
                Text(session.tilesActivated.joined(separator: ", "))
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
            Spacer()
            scoreHeadline
        }
    }

    @ViewBuilder
    private var scoreHeadline: some View {
        if let official = session.totaOfficialPoints {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(String(format: "%.1f", official))
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.green)
                Text("pts")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } else if !hasNoQSOs {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(String(format: "%.1f", inputs.totalEstimate))
                    .font(.title3.weight(.bold))
                Text("est.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var noQSOsBanner: some View {
        Label(
            "Activation requires ≥1 QSO. Score: 0.",
            systemImage: "exclamationmark.triangle"
        )
        .font(.caption)
        .foregroundStyle(.orange)
    }

    private var noActivationCoordCTA: some View {
        Label(
            "Set the activation coordinate to map your tile and enable scoring.",
            systemImage: "mappin.slash"
        )
        .font(.caption)
        .foregroundStyle(.orange)
    }

    private var noTrackNote: some View {
        Label(
            "No track recorded. Distance is from manual entry.",
            systemImage: "map"
        )
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private var bonusChipRow: some View {
        let chips = bonusChips
        if !chips.isEmpty {
            FlowLayout(spacing: 6) {
                ForEach(chips, id: \.id) { chip in
                    bonusChip(chip)
                }
            }
        }
    }

    private var footerRow: some View {
        HStack {
            if let snapshotAt = session.totaT3SnapshotAt {
                Text("Spots: \(snapshotAt, format: .relative(presentation: .named))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                Text("Spots: not yet refreshed")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                onRefreshSpots()
            } label: {
                if refreshingSpots {
                    ProgressView().controlSize(.small)
                } else {
                    Label("Refresh spots", systemImage: "arrow.clockwise")
                        .font(.caption)
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(refreshingSpots)
        }
    }

    private func bonusChip(_ chip: TOTABonusChip) -> some View {
        HStack(spacing: 3) {
            Image(systemName: chip.icon)
                .font(.caption2)
            Text(chip.label)
                .font(.caption2)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.purple.opacity(0.15))
        .foregroundStyle(.purple)
        .clipShape(Capsule())
    }

    private func pefBadge(pef: Int) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "figure.walk.motion")
            Text("PEF \(pef)")
                .font(.caption.weight(.semibold))
            Text("· Personal Effort leaderboard only")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - TOTABonusChip

struct TOTABonusChip: Identifiable {
    let id = UUID()
    let icon: String
    let label: String
}

// MARK: - Scoring helpers

private extension TOTAScoringInputs {
    /// Pre-upload pessimistic total (Confirmed + Estimated + Asserted).
    var totalEstimate: Double {
        TOTAScoringEngine.score(self).total
    }
}
