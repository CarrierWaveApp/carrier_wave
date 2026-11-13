import CarrierWaveCore
import CarrierWaveData
import SwiftUI

// MARK: - Notes, Activity Chips, Sync Chips, Metadata

extension QSODetailView {
    // MARK: - Activity chips

    /// POTA, SOTA, WWFF and AoA shown as coloured chips instead of a
    /// table of references. Only renders when at least one is set.
    @ViewBuilder
    var activityChipsSection: some View {
        if hasReferenceFields || qso.isContestQSO {
            Section {
                FlowingChips(chips: activityChips)
                    .padding(.vertical, 4)
            } header: {
                Text("Activity")
            }
        }
    }

    var activityChips: [ActivityChip] {
        var chips: [ActivityChip] = []
        if let park = qso.parkReference?.nonEmpty {
            let detail = myParkName.map { "\(park) — \($0)" } ?? park
            chips.append(ActivityChip(icon: "tree.fill", label: "POTA (mine)", detail: detail, color: .green))
        }
        if let park = qso.theirParkReference?.nonEmpty {
            let detail = theirParkName.map { "\(park) — \($0)" } ?? park
            chips.append(ActivityChip(icon: "tree", label: "POTA (theirs)", detail: detail, color: .green))
        }
        if let sota = qso.sotaRef?.nonEmpty {
            chips.append(ActivityChip(icon: "mountain.2.fill", label: "SOTA", detail: sota, color: .brown))
        }
        if let wwff = qso.wwffRef?.nonEmpty {
            chips.append(ActivityChip(icon: "leaf.fill", label: "WWFF", detail: wwff, color: .mint))
        }
        if let aoa = qso.aoaCode?.nonEmpty {
            chips.append(ActivityChip(icon: "eye.fill", label: "AoA", detail: aoa, color: .indigo))
        }
        return chips
    }

    // MARK: - Notes as quote card

    @ViewBuilder
    var notesQuoteSection: some View {
        if let notes = qso.notes?.nonEmpty {
            Section {
                HStack(alignment: .top, spacing: 10) {
                    Rectangle()
                        .fill(Color.accentColor.opacity(0.5))
                        .frame(width: 3)
                    Text(notes)
                        .font(.body.italic())
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.vertical, 4)
            } header: {
                Label("Notes", systemImage: "quote.opening")
            }
        }
    }

    // MARK: - Club chips

    @ViewBuilder
    var clubChipsSection: some View {
        let matchingClubs = ClubsSyncService.shared.clubs(for: qso.callsign)
        if !matchingClubs.isEmpty {
            Section {
                FlowingChips(
                    chips: matchingClubs.map { name in
                        ActivityChip(
                            icon: "person.3.fill",
                            label: "Club",
                            detail: name,
                            color: .pink
                        )
                    }
                )
                .padding(.vertical, 4)
            } header: {
                Text("Affiliations")
            }
        }
    }

    // MARK: - Sync status (rich per-service detail)

    @ViewBuilder
    var syncChipsSection: some View {
        if !qso.servicePresence.isEmpty || qso.lotwConfirmed || qso.qrzConfirmed {
            Section {
                ForEach(sortedPresence) { presence in
                    syncStatusRow(presence)
                }
                // Show per-park POTA presences that aren't in the collapsed view
                ForEach(potaParkPresences) { presence in
                    syncStatusRow(presence)
                }
                if qso.lotwConfirmed {
                    HStack(spacing: 4) {
                        Image(systemName: "star.fill").foregroundStyle(.yellow)
                        Text("LoTW Confirmed").font(.caption)
                    }
                }
                if qso.qrzConfirmed {
                    HStack(spacing: 4) {
                        Image(systemName: "star.fill").foregroundStyle(.yellow)
                        Text("QRZ QSL Confirmed").font(.caption)
                    }
                }
            } header: {
                Text("Sync Status")
            }
        }
    }

    /// Per-park POTA presences not shown in the collapsed `sortedPresence`.
    /// Shows additional parks when a QSO has two-fer or multi-park references.
    private var potaParkPresences: [ServicePresence] {
        let potaPresences = qso.servicePresence
            .filter { $0.serviceType == .pota && $0.parkReference != nil }
        // If there's only one, sortedPresence already shows it
        guard potaPresences.count > 1 else {
            return []
        }
        // sortedPresence picks the "best" one; show the rest
        let shownID = sortedPresence
            .first { $0.serviceType == .pota }?.id
        return potaPresences
            .filter { $0.id != shownID }
            .sorted { ($0.parkReference ?? "") < ($1.parkReference ?? "") }
    }

    private func syncStatusRow(_ presence: ServicePresence) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            // Top row: badge + status
            HStack {
                ServicePresenceBadge(
                    presence: presence, qso: qso,
                    isServiceConfigured: serviceConfig
                        .isConfigured(presence.serviceType)
                )
                Spacer()
                Text(presenceStatusText(presence))
                    .font(.caption)
                    .foregroundStyle(presence.uploadRejected ? .red : .secondary)
            }

            // Park reference for POTA per-park presences
            if presence.serviceType == .pota,
               let park = presence.parkReference
            {
                Text(park)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Rejection detail: re-run validator to reconstruct reason
            if presence.uploadRejected {
                rejectionDetail(presence)
            }

            // Confirmation timestamp
            if presence.isPresent, let confirmedAt = presence.lastConfirmedAt {
                Text("Confirmed \(Self.dateFormatter.string(from: confirmedAt))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func rejectionDetail(_ presence: ServicePresence) -> some View {
        let violations = ADIFFieldValidator.validateForUpload(
            callsign: qso.callsign, band: qso.band,
            mode: ModeEquivalence.normalizeForStrictADIF(qso.mode).mode,
            submode: ModeEquivalence.normalizeForStrictADIF(qso.mode).submode,
            freqMHz: qso.frequency
        )
        if !violations.isEmpty {
            ForEach(violations, id: \.reason) { vio in
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption2)
                        .foregroundStyle(.red)
                    Text(vio.reason)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        } else {
            HStack(spacing: 4) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption2)
                    .foregroundStyle(.red)
                Text("Rejected by service")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        if let build = presence.rejectedAtBuild {
            Text("Rejected in build \(build) — will retry on next update")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Metadata (collapsible)

    /// Source / import metadata collapsed by default — these are rarely
    /// useful on the primary viewing path but still need to be accessible.
    var metadataSection: some View {
        Section {
            DisclosureGroup("Import & Source") {
                detailRow("Import Source", importSourceLabel(qso.importSource))
                detailRow("Imported", Self.dateFormatter.string(from: qso.importedAt) + "Z")
                if let qrzId = qso.qrzLogId {
                    detailRow("QRZ Log ID", qrzId, monospaced: true)
                }
                if let adif = qso.rawADIF, !adif.isEmpty {
                    let extras = unmappedADIFFields(in: adif)
                    if !extras.isEmpty {
                        DisclosureGroup("Other ADIF Fields") {
                            ForEach(extras, id: \.name) { entry in
                                detailRow(adifLabel(entry.name), entry.value, monospaced: true)
                            }
                        }
                    }
                    DisclosureGroup("Raw ADIF") {
                        Text(adif)
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
            }
        }
    }
}

// MARK: - ActivityChip

struct ActivityChip: Identifiable {
    let id = UUID()
    let icon: String
    let label: String
    let detail: String
    let color: Color
}

// MARK: - FlowingChips

/// Simple wrap layout for a row of chips. Uses `Layout` so chips flow to
/// multiple lines naturally at narrow widths.
struct FlowingChips: View {
    let chips: [ActivityChip]

    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(chips) { chip in
                HStack(spacing: 4) {
                    Image(systemName: chip.icon)
                        .font(.caption2)
                    Text(chip.detail)
                        .font(.caption.weight(.medium))
                        .lineLimit(1)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(chip.color.opacity(0.2))
                .foregroundStyle(chip.color)
                .clipShape(Capsule())
            }
        }
    }
}
