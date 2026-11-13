import CarrierWaveCore
import CarrierWaveData
import CoreLocation
import SwiftData
import SwiftUI

// MARK: - ClusterSpotDetailView

/// Inspector panel for a selected spot in the cluster view.
/// Card-based layout with mini map, operator info, and worked status.
struct ClusterSpotDetailView: View {
    // MARK: Internal

    let spot: EnrichedSpot
    let allSpots: [EnrichedSpot]
    let isWorked: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                headerSection
                spotInfoChips
                spotMapSection
                operatorRow
                callsignNotesSection
                previousQSOsRow
                otherSpotsSection
            }
            .padding(.vertical, 8)
        }
        .task(id: spot.spot.callsign) {
            await loadCallsignInfo()
        }
    }

    // MARK: Private

    private static let infoCache = CallsignInfoCache.shared

    @State private var callsignInfo: CallsignInfo?
    @State private var poloEntry: PoloNotesEntry?
    @State private var combinedEmoji: String?
    @State private var isLoading = false
    @Environment(\.modelContext) private var modelContext
    @Environment(DXCCLookupService.self) private var dxccLookup

    private var otherSpots: [EnrichedSpot] {
        let callsign = spot.spot.callsign.uppercased()
        return allSpots.filter {
            $0.spot.callsign.uppercased() == callsign && $0.id != spot.id
        }
    }

    // MARK: - Map + Info Row

    /// DXCC entity lat/lon as fallback when no grid is available
    private var dxccEntityCoordinate: CLLocationCoordinate2D? {
        guard let entity = dxccLookup.lookup(spot.spot.callsign) else {
            return nil
        }
        return CLLocationCoordinate2D(
            latitude: entity.latitude, longitude: entity.longitude
        )
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                if let emoji = combinedEmoji {
                    Text(emoji)
                }
                Text(spot.spot.callsign)
                    .font(.title2.bold().monospaced())
                    .strikethrough(isWorked)
                    .foregroundStyle(isWorked ? .secondary : .primary)
                Spacer()
                qsoCountBadge
                statusBadge
            }

            HStack(spacing: 8) {
                if let entity = spot.dxccEntity {
                    Text(entity)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                if let name = callsignInfo?.operatorName {
                    Text("· \(name)")
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                }
            }
            .lineLimit(1)

            if let components = callsignInfo?.components,
               components.hasModifiers
            {
                CallsignModifiersView(components: components)
                    .padding(.top, 2)
            }

            if isLoading {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .padding(.horizontal)
    }

    @ViewBuilder
    private var qsoCountBadge: some View {
        if let count = callsignInfo?.previousQSOCount, count > 0 {
            Text("\(count)×")
                .font(.caption.weight(.medium).monospacedDigit())
                .foregroundStyle(.green)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Color.green.opacity(0.15))
                .clipShape(Capsule())
        }
    }

    @ViewBuilder
    private var statusBadge: some View {
        if isWorked {
            Label("Worked", systemImage: "checkmark.circle.fill")
                .font(.caption.weight(.medium))
                .foregroundStyle(.green)
        } else if spot.neededStatus != .unknown {
            let color = SpotColorScheme.neededColor(spot.neededStatus)
            Text(spot.neededStatus.label)
                .font(.caption.weight(.medium))
                .foregroundStyle(color)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(color.opacity(0.2))
                .clipShape(Capsule())
        }
    }

    // MARK: - Spot Info Chips

    private var spotInfoChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                Text(String(format: "%.1f", spot.spot.frequencyKHz))
                    .font(.caption.monospaced().weight(.medium))

                chipBadge(spot.spot.band, color: .blue)
                chipBadge(spot.spot.mode, color: .blue)
                chipBadge(spot.spot.source.displayName, color: .purple)

                if let wpm = spot.spot.wpm {
                    chipBadge("\(wpm) WPM", color: .teal)
                }
                if let snr = spot.spot.snr {
                    chipBadge("\(snr) dB", color: .teal)
                }
            }
            .padding(.horizontal)
        }
    }

    // MARK: - Map

    @ViewBuilder
    private var spotMapSection: some View {
        let grid = spot.spot.dxGrid ?? callsignInfo?.grid
        SpotMapView(
            spotGrid: grid,
            spotCoordinate: dxccEntityCoordinate,
            band: spot.spot.band,
            callsign: spot.spot.callsign
        )
        .padding(.horizontal)
    }

    // MARK: - Operator Row

    @ViewBuilder
    private var operatorRow: some View {
        if let info = callsignInfo, info.source != nil {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 12) {
                    if let name = info.operatorName {
                        compactField("Name", value: name)
                    }
                    if let grid = info.grid {
                        compactField("Grid", value: grid, mono: true)
                    }
                    if let licClass = info.licenseClass {
                        compactField("Class", value: licClass)
                    }
                    if let prev = info.previousCallsign {
                        compactField("Prev", value: prev, mono: true)
                    }
                }

                if let location = info.location {
                    Text(location)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal)
        }
    }

    private func compactField(
        _ label: String,
        value: String,
        mono: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Text(value)
                .font(mono ? .caption.monospaced() : .caption)
                .lineLimit(1)
        }
    }
}

// MARK: - ClusterSpotDetailView + Sections

extension ClusterSpotDetailView {
    // MARK: - Callsign Notes

    @ViewBuilder
    var callsignNotesSection: some View {
        if let entry = poloEntry {
            HStack(spacing: 8) {
                if let emoji = entry.emoji {
                    Text(emoji)
                }
                VStack(alignment: .leading, spacing: 2) {
                    if let name = entry.name {
                        Text(name).font(.callout)
                    }
                    if let note = entry.note {
                        Text(note)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal)
        }
    }

    // MARK: - Previous QSOs

    @ViewBuilder
    var previousQSOsRow: some View {
        if let info = callsignInfo, info.previousQSOCount > 0 {
            HStack(spacing: 8) {
                Label(
                    "\(info.previousQSOCount) QSO\(info.previousQSOCount == 1 ? "" : "s")",
                    systemImage: "clock"
                )
                .font(.caption.weight(.medium))
                .foregroundStyle(.green)

                if let lastWorked = info.lastWorked {
                    Text(lastWorked.formatted(.dateTime.month(.abbreviated).day()))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let band = info.lastBand {
                    chipBadge(band, color: .secondary)
                }
                if let mode = info.lastMode {
                    chipBadge(mode, color: .secondary)
                }
            }
            .padding(.horizontal)
        }
    }

    // MARK: - Also Spotted On

    @ViewBuilder
    var otherSpotsSection: some View {
        if !otherSpots.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text("Also Spotted On")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(otherSpots.prefix(5)) { other in
                            HStack(spacing: 4) {
                                chipBadge(other.spot.band, color: .blue)
                                Text(other.spot.mode)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.horizontal)
                }
            }
        }
    }

    // MARK: - Shared Components

    func chipBadge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.medium))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15))
            .clipShape(Capsule())
    }

    // MARK: - Data Loading

    func loadCallsignInfo() async {
        isLoading = true
        defer { isLoading = false }

        let callsign = spot.spot.callsign.uppercased()

        let components = CallsignComponentsParser.parse(
            callsign, dxccLookup: dxccLookup
        )
        let baseCall = components.baseCallsign

        let summaries = fetchPreviousQSOSummaries(callsign: baseCall)

        let info = await Self.infoCache.lookup(
            callsign: callsign,
            qsoSummaries: summaries,
            components: components
        )
        callsignInfo = info

        let store = PoloNotesStore.shared
        await store.ensureLoaded()
        poloEntry = await store.info(for: baseCall)
        combinedEmoji = await store.combinedEmoji(for: baseCall)
    }

    @MainActor
    func fetchPreviousQSOSummaries(
        callsign: String
    ) -> [PreviousQSOSummary] {
        let descriptor = BoundedDescriptor<QSO>(
            predicate: #Predicate<QSO> { qso in
                qso.callsign == callsign && !qso.isHidden
            },
            sortBy: [SortDescriptor(\QSO.timestamp, order: .reverse)],
            limit: 10
        )

        guard let qsos = try? modelContext.boundedFetch(descriptor) else {
            return []
        }

        return qsos.map { qso in
            PreviousQSOSummary(
                timestamp: qso.timestamp,
                band: qso.band,
                mode: qso.mode,
                notes: qso.notes
            )
        }
    }
}
