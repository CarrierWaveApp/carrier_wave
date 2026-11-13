import CarrierWaveData
import SwiftData
import SwiftUI

// MARK: - ContestScorePanel

/// Score header + category/power/overlay pickers + off-time / band-change
/// readouts. Pulls everything from the live `ContestManager`. Designed to
/// occupy a slim slot at the top of a contest layout but it sizes to fit
/// whatever the slot gives it.
struct ContestScorePanel: View {
    // MARK: Internal

    let manager: ContestManager
    let definition: ContestDefinition

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            header
            categoryRow
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: Private

    private var mode: String {
        definition.modes.first ?? "CW"
    }

    private var powerClasses: [String] {
        definition.categories.first { $0.id == manager.categoryID }?.powerClasses ?? []
    }

    private var categoryBinding: Binding<String?> {
        Binding(get: { manager.categoryID }, set: { manager.setCategory($0) })
    }

    private var powerBinding: Binding<String?> {
        Binding(get: { manager.powerClass }, set: { manager.setPowerClass($0) })
    }

    private var overlayBinding: Binding<String?> {
        Binding(get: { manager.overlayCategoryID }, set: { manager.setOverlay($0) })
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(definition.displayName)
                    .font(.headline)
                Text("Sending #\(String(format: "%03d", manager.currentSerial)) · \(mode)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            scoreStat("QSOs", manager.score.totalQSOs)
            scoreStat("Pts", manager.score.totalPoints)
            scoreStat("Mults", manager.score.multiplierCount)
            scoreStat("Score", manager.score.finalScore, emphasized: true)
        }
    }

    private var categoryRow: some View {
        HStack(spacing: 12) {
            Picker("Category", selection: categoryBinding) {
                Text("—").tag(String?.none)
                ForEach(definition.categories) { category in
                    Text(category.label).tag(String?.some(category.id))
                }
            }
            .frame(maxWidth: 240)

            if !powerClasses.isEmpty {
                Picker("Power", selection: powerBinding) {
                    Text("—").tag(String?.none)
                    ForEach(powerClasses, id: \.self) { power in
                        Text(power).tag(String?.some(power))
                    }
                }
                .frame(maxWidth: 150)
            }

            if !definition.overlayCategories.isEmpty {
                Picker("Overlay", selection: overlayBinding) {
                    Text("None").tag(String?.none)
                    ForEach(definition.overlayCategories, id: \.id) { overlay in
                        Text(overlay.label).tag(String?.some(overlay.id))
                    }
                }
                .frame(maxWidth: 170)
            }

            Spacer()
            bandChangeLabel
            offTimeLabel
        }
    }

    @ViewBuilder
    private var bandChangeLabel: some View {
        let changes = manager.bandChangeSummary.totalChanges
        if changes > 0 {
            let violations = manager.bandChangeSummary.violations.count
            HStack(spacing: 4) {
                Image(systemName: "arrow.left.arrow.right")
                Text("\(changes) band chg")
                if violations > 0 {
                    Text("· \(violations)!").foregroundStyle(.red)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var offTimeLabel: some View {
        let onAir = Int(manager.offTimeSummary.totalOnAirSeconds)
        if onAir > 0 {
            HStack(spacing: 4) {
                Image(systemName: "clock")
                Text("On \(onAir / 3_600)h \(onAir % 3_600 / 60)m")
                if let remaining = manager.offTimeSummary.remainingOnAirSeconds {
                    Text("· \(Int(remaining) / 3_600)h left")
                        .foregroundStyle(remaining > 0
                            ? AnyShapeStyle(HierarchicalShapeStyle.secondary)
                            : AnyShapeStyle(Color.red))
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private func scoreStat(_ label: String, _ value: Int, emphasized: Bool = false) -> some View {
        VStack(spacing: 1) {
            Text(value.formatted())
                .font(emphasized ? .title3.bold().monospacedDigit() : .body.monospacedDigit())
                .foregroundStyle(emphasized ? Color.accentColor : .primary)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(minWidth: 56)
    }
}

// Note: the `.contestEntry` panel reuses `ParsedEntryView` directly via
// `PanelRegistry`; the old standalone `ContestEntryBar` was retired so the
// quick-entry bar is the single entry point for both casual and contest
// logging. Contest exchange parsing lives in `ParsedEntryView+Contest`.

// MARK: - ContestBandBreakdownPanel

/// Wraps the existing `ContestBandBreakdown` strip so it can be dropped into
/// any layout slot. Keeps the underlying view unchanged for reuse elsewhere.
struct ContestBandBreakdownPanel: View {
    let manager: ContestManager
    let definition: ContestDefinition

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ContestBandBreakdown(score: manager.score, bands: definition.bands)
                .padding(.vertical, 6)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - ContestRecentQSOsPanel

/// The recent-QSO list extracted from `ContestOperatingView`.
struct ContestRecentQSOsPanel: View {
    // MARK: Internal

    let manager: ContestManager

    var body: some View {
        Group {
            if manager.recentQSOs.isEmpty {
                ContentUnavailableView(
                    "No QSOs yet",
                    systemImage: "list.bullet",
                    description: Text("Logged contacts appear here with point and prefix detail.")
                )
            } else {
                List(manager.recentQSOs) { qso in
                    recentRow(qso)
                }
                .listStyle(.inset)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Private

    private func recentRow(_ qso: ContestLoggedQSO) -> some View {
        HStack(spacing: 10) {
            Text(qso.callsign)
                .font(.body.monospaced().weight(.medium))
                .frame(width: 110, alignment: .leading)
            Text(qso.band)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .frame(width: 44, alignment: .leading)
            Text(qso.prefix)
                .font(.caption.monospaced())
                .foregroundStyle(.orange)
                .frame(width: 56, alignment: .leading)
            if let serial = qso.serialSent {
                Text("#\(String(format: "%03d", serial))")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
            Spacer()
            recentBadge(qso.status)
        }
        .lineLimit(1)
        .truncationMode(.tail)
        .frame(height: QSOLogRowMetrics.rowHeight)
        .contextMenu {
            if let qsoID = qso.qsoID {
                Button("Delete QSO", systemImage: "trash", role: .destructive) {
                    Task { await manager.deleteQSO(qsoID) }
                }
            }
        }
    }

    @ViewBuilder
    private func recentBadge(_ status: ContestDupeStatus) -> some View {
        switch status {
        case .dupe:
            Text("DUPE").font(.caption2.bold()).foregroundStyle(.red)
        case .newMultiplier:
            Text("MULT").font(.caption2.bold()).foregroundStyle(.green)
        case .newStation:
            EmptyView()
        }
    }
}

// MARK: - ContestPanelPlaceholder

/// Shown for a contest panel when no contest session is active.
struct ContestPanelPlaceholder: View {
    let kind: PanelIdentifier

    var body: some View {
        ContentUnavailableView(
            kind.displayName,
            systemImage: kind.icon,
            description: Text("Start a contest session to populate this panel.")
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
