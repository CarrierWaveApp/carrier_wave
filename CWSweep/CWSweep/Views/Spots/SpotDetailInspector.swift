import CarrierWaveCore
import CarrierWaveData
import SwiftData
import SwiftUI

/// Inspector panel showing spot details, HamDB operator info, and previous QSO history.
struct SpotDetailInspector: View {
    // MARK: Internal

    let spot: EnrichedSpot

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                callsignHeader
                Divider()
                spotDetailsSection
                operatorInfoSection
                callsignNotesSection
                previousQSOsSection
            }
            .padding(.vertical)
        }
        .task(id: spot.spot.callsign) {
            await loadCallsignInfo()
        }
    }

    // MARK: Private

    private static let infoCache = CallsignInfoCache.shared

    @State private var callsignInfo: CallsignInfo?
    @State private var poloEntry: PoloNotesEntry?
    @State private var isLoading = false
    @Environment(\.modelContext) private var modelContext

    // MARK: - Callsign Header

    private var callsignHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(spot.spot.callsign)
                .font(.title2.bold())

            if let name = callsignInfo?.operatorName {
                Text(name)
                    .foregroundStyle(.secondary)
            }

            if isLoading {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .padding(.horizontal)
    }

    // MARK: - Spot Details

    private var spotDetailsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Spot Details")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal)

            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
            ], alignment: .leading, spacing: 8) {
                InspectorField(
                    label: "Frequency",
                    value: String(format: "%.1f kHz", spot.spot.frequencyKHz)
                )
                InspectorField(label: "Band", value: spot.spot.band)
                InspectorField(label: "Mode", value: spot.spot.mode)
                InspectorField(label: "Source", value: spot.spot.source.displayName)

                if let distance = spot.formattedDistance() {
                    InspectorField(label: "Distance", value: distance)
                }

                if let bearing = spot.formattedBearing() {
                    InspectorField(label: "Bearing", value: bearing)
                }

                InspectorField(label: "Region", value: spot.region.rawValue)

                if let state = spot.state, !state.isEmpty {
                    InspectorField(label: "State", value: state)
                }

                if let country = spot.country, !country.isEmpty {
                    InspectorField(label: "Country", value: country)
                }

                if let spotter = spot.spot.spotter {
                    InspectorField(label: "Spotter", value: spotter)
                }

                if let ref = spot.spot.referenceDisplay {
                    InspectorField(label: "Reference", value: ref)
                }

                if let loc = spot.spot.locationDisplay {
                    InspectorField(label: "Location", value: loc)
                }
            }
            .padding(.horizontal)
        }
    }

    // MARK: - Operator Info

    @ViewBuilder
    private var operatorInfoSection: some View {
        if let info = callsignInfo, info.license != nil {
            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("Operator Info")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)

                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                ], alignment: .leading, spacing: 8) {
                    if let name = info.operatorName {
                        InspectorField(label: "Name", value: name)
                    }
                    if let location = info.location {
                        InspectorField(label: "QTH", value: location)
                    }
                    if let licClass = info.licenseClass {
                        InspectorField(label: "Class", value: licClass)
                    }
                    if let grid = info.grid {
                        InspectorField(label: "Grid", value: grid)
                    }
                }
                .padding(.horizontal)
            }
        }
    }

    // MARK: - Callsign Notes

    @ViewBuilder
    private var callsignNotesSection: some View {
        if let entry = poloEntry {
            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("Callsign Notes")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)

                VStack(alignment: .leading, spacing: 4) {
                    if let emoji = entry.emoji, let name = entry.name {
                        Text("\(emoji) \(name)")
                            .font(.body)
                    } else if let name = entry.name {
                        Text(name)
                            .font(.body)
                    } else if let emoji = entry.emoji {
                        Text(emoji)
                            .font(.body)
                    }

                    if let note = entry.note {
                        Text(note)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal)
            }
        }
    }

    // MARK: - Previous QSOs

    @ViewBuilder
    private var previousQSOsSection: some View {
        if let info = callsignInfo, info.previousQSOCount > 0 {
            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("Previous QSOs (\(info.previousQSOCount))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)

                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                ], alignment: .leading, spacing: 8) {
                    if let lastWorked = info.lastWorked {
                        InspectorField(
                            label: "Last Worked",
                            value: lastWorked.formatted(
                                .dateTime.month(.abbreviated).day().year()
                            )
                        )
                    }
                    if let band = info.lastBand {
                        InspectorField(label: "Last Band", value: band)
                    }
                    if let mode = info.lastMode {
                        InspectorField(label: "Last Mode", value: mode)
                    }
                    if let notes = info.lastNotes, !notes.isEmpty {
                        InspectorField(label: "Notes", value: notes)
                    }
                }
                .padding(.horizontal)
            }
        }
    }

    // MARK: - Data Loading

    private func loadCallsignInfo() async {
        isLoading = true
        defer { isLoading = false }

        let callsign = spot.spot.callsign.uppercased()

        // Fetch previous QSO summaries from SwiftData on MainActor
        let summaries = fetchPreviousQSOSummaries(callsign: callsign)

        // Look up via cache (handles HamDB + merges summaries)
        let info = await Self.infoCache.lookup(
            callsign: callsign,
            qsoSummaries: summaries
        )
        callsignInfo = info

        // Load Polo notes
        let store = PoloNotesStore.shared
        await store.ensureLoaded()
        poloEntry = await store.info(for: callsign)
    }

    @MainActor
    private func fetchPreviousQSOSummaries(callsign: String) -> [PreviousQSOSummary] {
        var descriptor = FetchDescriptor<QSO>(
            predicate: #Predicate<QSO> { qso in
                qso.callsign == callsign && !qso.isHidden
            },
            sortBy: [SortDescriptor(\QSO.timestamp, order: .reverse)]
        )
        descriptor.fetchLimit = 10

        guard let qsos = try? modelContext.fetch(descriptor) else {
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
