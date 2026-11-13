import SwiftUI

// MARK: - StackedBandScopeView

/// N1MM-inspired stacked band scope (Variant 2).
/// Shows multiple band columns side by side, each displaying spot text at
/// frequency position. Active band has a green outline. Click any spot in
/// any column to QSY both band and frequency.
struct StackedBandScopeView: View {
    // MARK: Internal

    @Environment(SpotAggregator.self) var spotAggregator
    @Environment(RadioManager.self) var radioManager
    @Environment(SelectionState.self) var selectionState
    @Environment(BandScopeQueryRunner.self) var queryRunner

    @AppStorage("bandScopeMaxAgeMinutes") var maxAgeMinutes: Int = 30
    @AppStorage("bandScopeFilterMode") var filterMode: BandScopeFilterMode = .widgets
    @AppStorage("autoXITEnabled") var autoXITEnabled = false
    @AppStorage("autoXITOffsetHz") var autoXITOffsetHz = 0

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            HStack(spacing: 0) {
                ForEach(Array(visibleBands.enumerated()), id: \.element) { index, bandId in
                    if index > 0 {
                        Divider()
                    }
                    bandColumn(bandId: bandId, isActive: index == activeColumnIndex)
                }
            }
            Divider()
            bottomBar
        }
        .focusable()
        .onKeyPress(phases: .down) { keyPress in
            handleKeyPress(keyPress)
        }
        .onChange(of: radioManager.frequency) { _, newFreq in
            autoSwitchColumn(frequency: newFreq)
        }
    }

    // MARK: Private

    @State private var visibleBands: [String] = ["80m", "40m", "20m", "15m", "10m"]
    @State private var activeColumnIndex: Int = 2

    private var toolbar: some View {
        HStack(spacing: 6) {
            Text("Stacked")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)

            Spacer()

            Text(String(format: "%.1f", radioManager.frequency * 1_000))
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(Color(nsColor: .systemRed))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }

    private var bottomBar: some View {
        HStack(spacing: 10) {
            Group {
                Text("←→ col")
                Text("↑↓ spot")
                Text("⏎ tune")
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)

            Spacer()

            let totalSpots = visibleBands.reduce(0) { $0 + spotsForBand($1).count }
            let totalMults = visibleBands.reduce(0) { $0 + multCount(for: $1) }
            Text("\(totalSpots) spots · \(totalMults) mults · \(visibleBands.count) bands")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
    }
}

// MARK: - Column

extension StackedBandScopeView {
    private func bandColumn(bandId: String, isActive: Bool) -> some View {
        let spots = spotsForBand(bandId)
        let mults = multCount(for: bandId)

        return VStack(spacing: 0) {
            columnHeader(bandId: bandId, spotCount: spots.count, multCount: mults, isActive: isActive)
            Divider()
            spotList(spots: spots)
            Divider()
            columnFooter(spots: spots, isActive: isActive)
        }
        .background(isActive ? Color(nsColor: .systemGreen).opacity(0.03) : .clear)
        .overlay {
            if isActive {
                RoundedRectangle(cornerRadius: 0)
                    .stroke(Color(nsColor: .systemGreen), lineWidth: 2)
            }
        }
    }

    private func columnHeader(bandId: String, spotCount: Int, multCount: Int, isActive: Bool) -> some View {
        HStack(spacing: 4) {
            Text(bandId)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(isActive ? Color(nsColor: .systemGreen) : .primary)
            Spacer()
            Text("\(spotCount)")
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
            if multCount > 0 {
                Text("\(multCount)m")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color(nsColor: .systemGreen))
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(isActive
            ? Color(nsColor: .systemGreen).opacity(0.08)
            : Color(nsColor: .controlBackgroundColor).opacity(0.3))
    }

    private func spotList(spots: [EnrichedSpot]) -> some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(spots, id: \.id) { spot in
                    spotRow(spot: spot)
                }
            }
        }
        .frame(maxHeight: .infinity)
    }

    private func spotRow(spot: EnrichedSpot) -> some View {
        let isNeeded = spot.neededStatus == .newEntity || spot.neededStatus == .newBandSlot
        let color = spotRowColor(for: spot)

        return Button {
            tuneToSpot(spot)
        } label: {
            HStack(spacing: 4) {
                // Compact frequency: just the kHz offset within the band
                Text(compactFreq(spot.spot.frequencyKHz))
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .frame(minWidth: 36, alignment: .trailing)

                Text(spot.spot.callsign)
                    .font(.system(size: 10, weight: isNeeded ? .bold : .medium, design: .monospaced))
                    .foregroundStyle(color)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 0)

                if spot.neededStatus == .newEntity {
                    Circle()
                        .fill(Color(nsColor: .systemRed))
                        .frame(width: 5, height: 5)
                } else if spot.neededStatus == .newBandSlot {
                    Circle()
                        .fill(Color(nsColor: .systemOrange))
                        .frame(width: 5, height: 5)
                }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
        }
        .buttonStyle(.plain)
    }

    /// Show compact frequency — just the kHz portion (e.g. "025.7" for 14025.7)
    private func compactFreq(_ freqKHz: Double) -> String {
        let remainder = freqKHz.truncatingRemainder(dividingBy: 1_000)
        return String(format: "%05.1f", remainder)
    }

    private func columnFooter(spots: [EnrichedSpot], isActive: Bool) -> some View {
        HStack(spacing: 2) {
            if let freshest = spots.max(by: { $0.spot.timestamp < $1.spot.timestamp }) {
                let age = Date().timeIntervalSince(freshest.spot.timestamp)
                Text(formatAge(age))
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
            activityDots(spots: spots)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .background(isActive
            ? Color(nsColor: .systemGreen).opacity(0.08)
            : Color(nsColor: .controlBackgroundColor).opacity(0.3))
    }

    private func activityDots(spots: [EnrichedSpot]) -> some View {
        HStack(spacing: 1) {
            ForEach(0 ..< 5, id: \.self) { idx in
                let windowMinutes = [1.0, 3.0, 5.0, 10.0, 15.0]
                let cutoff = Date().addingTimeInterval(-windowMinutes[idx] * 60)
                let active = spots.contains { $0.spot.timestamp > cutoff }
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color(nsColor: .systemGreen).opacity(active ? 0.8 : 0.15))
                    .frame(width: 3, height: active ? 8 : 3)
            }
        }
        .frame(height: 10, alignment: .bottom)
    }
}

// MARK: - Helpers

extension StackedBandScopeView {
    private func spotRowColor(for spot: EnrichedSpot) -> Color {
        switch spot.neededStatus {
        case .newEntity: Color(nsColor: .systemGreen)
        case .newBandSlot: Color(nsColor: .systemOrange)
        case .confirmed,
             .workedNotConfirmed: Color(nsColor: .systemGray)
        case .unknown: Color(nsColor: .systemBlue)
        }
    }

    private func spotsForBand(_ bandId: String) -> [EnrichedSpot] {
        guard let band = BandEdges.hfBands.first(where: { $0.id == bandId }) else {
            return []
        }
        // SQL filter mode: trust the active query's allow-list and
        // skip the age cutoff (the query is the source of truth).
        // Widget mode: keep the existing age-decay pruning.
        let allowed: Set<String>? =
            (filterMode != .widgets) ? queryRunner.allowedSpotIDs : nil
        return spotAggregator.spots
            .filter { spot in
                guard spot.spot.frequencyKHz >= band.lowerKHz,
                      spot.spot.frequencyKHz <= band.upperKHz
                else {
                    return false
                }
                if let allowed {
                    return allowed.contains(spot.spot.id)
                }
                return !isExpired(spot)
            }
            .sorted { $0.spot.frequencyKHz < $1.spot.frequencyKHz }
    }

    private func multCount(for bandId: String) -> Int {
        spotsForBand(bandId).filter {
            $0.neededStatus == .newEntity || $0.neededStatus == .newBandSlot
        }.count
    }

    private func isExpired(_ spot: EnrichedSpot) -> Bool {
        let factor = switch spot.spot.source {
        case .rbn: 2.0
        case .pota,
             .sota,
             .wwff: 0.5
        default: 1.0
        }
        return Date().timeIntervalSince(spot.spot.timestamp) * factor > Double(maxAgeMinutes) * 60
    }

    private func formatAge(_ seconds: TimeInterval) -> String {
        if seconds < 60 {
            return "\(Int(seconds))s"
        }
        if seconds < 3_600 {
            return "\(Int(seconds / 60))m"
        }
        return "\(Int(seconds / 3_600))h"
    }

    private func tuneToSpot(_ spot: EnrichedSpot) {
        SpotEntryBridge.shared.pendingSpot = spot
        selectionState.selectedSpot = spot
        selectionState.selectedQSOId = nil
        Task {
            await radioManager.tuneToSpot(
                frequencyMHz: spot.spot.frequencyMHz,
                mode: spot.spot.mode,
                autoXITEnabled: autoXITEnabled,
                autoXITOffsetHz: autoXITOffsetHz
            )
        }
    }

    private func autoSwitchColumn(frequency freqMHz: Double) {
        let freqKHz = freqMHz * 1_000
        if let band = BandEdges.band(for: freqKHz),
           let idx = visibleBands.firstIndex(of: band.id)
        {
            activeColumnIndex = idx
        }
    }

    private func handleKeyPress(_ keyPress: KeyPress) -> KeyPress.Result {
        switch keyPress.key {
        case .leftArrow:
            if activeColumnIndex > 0 {
                activeColumnIndex -= 1
                return .handled
            }
            return .ignored
        case .rightArrow:
            if activeColumnIndex < visibleBands.count - 1 {
                activeColumnIndex += 1
                return .handled
            }
            return .ignored
        case KeyEquivalent("1"): selectColumn(0); return .handled
        case KeyEquivalent("2"): selectColumn(1); return .handled
        case KeyEquivalent("3"): selectColumn(2); return .handled
        case KeyEquivalent("4"): selectColumn(3); return .handled
        case KeyEquivalent("5"): selectColumn(4); return .handled
        default:
            return .ignored
        }
    }

    private func selectColumn(_ index: Int) {
        guard index < visibleBands.count else {
            return
        }
        activeColumnIndex = index
    }
}
