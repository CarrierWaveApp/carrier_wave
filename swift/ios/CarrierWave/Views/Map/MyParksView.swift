import CarrierWaveData
import SwiftData
import SwiftUI

// MARK: - MyParkEntry

/// A park the user has activated or hunted, with counts.
struct MyParkEntry: Identifiable, Equatable {
    let reference: String
    let name: String
    let locationDesc: String
    let activationQSOCount: Int
    let huntQSOCount: Int
    let lastWorked: Date

    var id: String {
        reference
    }

    var totalQSOs: Int {
        activationQSOCount + huntQSOCount
    }

    var state: String? {
        let parts = locationDesc.split(separator: "-")
        guard parts.count >= 2 else {
            return nil
        }
        return String(parts[1])
    }
}

// MARK: - MyParksSortOrder

enum MyParksSortOrder: String, CaseIterable {
    case recent = "Recent"
    case mostQSOs = "Most QSOs"
    case reference = "Reference"
}

// MARK: - MyParksView

/// Searchable list of all parks the user has activated or hunted.
struct MyParksView: View {
    // MARK: Internal

    var body: some View {
        parksContent
            .navigationTitle("My Parks")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Search by reference or name")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    sortMenu
                }
            }
            .task { await loadParks() }
            .onChange(of: entries) { _, _ in recomputeFilteredEntries() }
            .onChange(of: searchText) { _, _ in recomputeFilteredEntries() }
            .onChange(of: sortOrder) { _, _ in recomputeFilteredEntries() }
    }

    // MARK: Private

    @Environment(\.modelContext) private var modelContext

    @State private var entries: [MyParkEntry] = []
    @State private var filteredEntries: [MyParkEntry] = []
    @State private var isLoading = true
    @State private var searchText = ""
    @State private var sortOrder: MyParksSortOrder = .recent
}

// MARK: - Subviews

extension MyParksView {
    var parksContent: some View {
        Group {
            if isLoading {
                ProgressView("Loading parks…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filteredEntries.isEmpty {
                emptyState
            } else {
                parksList
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView(
            "No Parks Yet",
            systemImage: "tree",
            description: Text("Parks you activate or hunt will appear here.")
        )
    }

    private var sortMenu: some View {
        Menu {
            Picker("Sort", selection: $sortOrder) {
                ForEach(MyParksSortOrder.allCases, id: \.self) { order in
                    Text(order.rawValue).tag(order)
                }
            }
        } label: {
            Image(systemName: "arrow.up.arrow.down")
        }
    }

    private var parksList: some View {
        List(filteredEntries) { entry in
            parkRow(entry)
        }
        .listStyle(.plain)
    }

    private func parkRow(_ entry: MyParkEntry) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(entry.reference)
                    .font(.subheadline.monospaced())
                    .fontWeight(.semibold)
                    .foregroundStyle(.green)
                Spacer()
                Text(entry.lastWorked, format: .dateTime.month(.abbreviated).day().year())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(entry.name)
                .font(.subheadline)
                .lineLimit(1)

            HStack(spacing: 12) {
                if let state = entry.state {
                    Label(state, systemImage: "mappin")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if entry.activationQSOCount > 0 {
                    Label(
                        "\(entry.activationQSOCount) activated",
                        systemImage: "flag.fill"
                    )
                    .font(.caption)
                    .foregroundStyle(.orange)
                }
                if entry.huntQSOCount > 0 {
                    Label(
                        "\(entry.huntQSOCount) hunted",
                        systemImage: "target"
                    )
                    .font(.caption)
                    .foregroundStyle(.blue)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Data Loading

extension MyParksView {
    private func recomputeFilteredEntries() {
        let sorted: [MyParkEntry] = switch sortOrder {
        case .recent:
            entries.sorted { $0.lastWorked > $1.lastWorked }
        case .mostQSOs:
            entries.sorted { $0.totalQSOs > $1.totalQSOs }
        case .reference:
            entries.sorted { $0.reference < $1.reference }
        }
        guard !searchText.isEmpty else {
            filteredEntries = sorted
            return
        }
        let query = searchText.uppercased()
        filteredEntries = sorted.filter {
            $0.reference.uppercased().contains(query)
                || $0.name.uppercased().contains(query)
        }
    }

    private func loadParks() async {
        let container = modelContext.container
        let mode = CwStoreQSOMode.current
        let parks = await Task.detached(priority: .userInitiated) {
            // In `.on`, serve the per-park rollup from cw-store (SQL GROUP BY,
            // O(result rows)) — retires the unbounded SwiftData scan below. Falls
            // back to SwiftData if the store can't be opened or the query fails.
            if mode == .on,
               let store = try? await CwStoreProvider.shared.store(),
               let rows = try? await RustAnalyticsReadSource(store: store).parkRollup(query: "")
            {
                return rows.map(parkEntry(from:))
            }
            let context = ModelContext(container)
            return computeMyParkEntries(context: context)
        }.value
        entries = parks
        recomputeFilteredEntries()
        isLoading = false
    }
}

// MARK: - ParkActivityAccumulator

/// Accumulated activation and hunt counts for a single park.
private struct ParkActivityAccumulator {
    var activationDates: Set<Date> = []
    var hunts = 0
    var lastDate: Date = .distantPast
}

// MARK: - Computation (nonisolated)

nonisolated private func isMetadataMode(_ mode: String) -> Bool {
    QSOMode.isMetadata(mode)
}

/// Compute park entries on a background thread.
nonisolated private func computeMyParkEntries(
    context: ModelContext
) -> [MyParkEntry] {
    var parkData: [String: ParkActivityAccumulator] = [:]
    accumulateActivations(into: &parkData, context: context)
    accumulateHunts(into: &parkData, context: context)
    return resolveParkEntries(from: parkData)
}

nonisolated private func accumulateActivations(
    into parkData: inout [String: ParkActivityAccumulator],
    context: ModelContext
) {
    var utcCal = Calendar(identifier: .gregorian)
    utcCal.timeZone = TimeZone(identifier: "UTC")!
    let batchSize = BoundedDescriptor<QSO>.maxLimit
    var offset = 0

    while true {
        let desc = BoundedDescriptor<QSO>(
            predicate: #Predicate<QSO> { qso in
                qso.parkReference != nil && !qso.isHidden
            },
            limit: batchSize,
            offset: offset
        )
        let qsos = (try? context.boundedFetch(desc)) ?? []
        if qsos.isEmpty {
            break
        }

        for qso in qsos {
            guard let ref = qso.parkReference,
                  !isMetadataMode(qso.mode)
            else {
                continue
            }
            let utcDay = utcCal.startOfDay(for: qso.timestamp)
            for parkRef in splitParkRefs(ref) {
                parkData[parkRef, default: ParkActivityAccumulator()]
                    .activationDates.insert(utcDay)
                if qso.timestamp > parkData[parkRef]!.lastDate {
                    parkData[parkRef]!.lastDate = qso.timestamp
                }
            }
        }

        if qsos.count < batchSize {
            break
        }
        offset += batchSize
    }
}

nonisolated private func accumulateHunts(
    into parkData: inout [String: ParkActivityAccumulator],
    context: ModelContext
) {
    let batchSize = BoundedDescriptor<QSO>.maxLimit
    var offset = 0

    while true {
        let desc = BoundedDescriptor<QSO>(
            predicate: #Predicate<QSO> { qso in
                qso.theirParkReference != nil && !qso.isHidden
            },
            limit: batchSize,
            offset: offset
        )
        let qsos = (try? context.boundedFetch(desc)) ?? []
        if qsos.isEmpty {
            break
        }

        for qso in qsos {
            guard let ref = qso.theirParkReference,
                  !isMetadataMode(qso.mode)
            else {
                continue
            }
            for parkRef in splitParkRefs(ref) {
                parkData[parkRef, default: ParkActivityAccumulator()].hunts += 1
                if qso.timestamp > parkData[parkRef]!.lastDate {
                    parkData[parkRef]!.lastDate = qso.timestamp
                }
            }
        }

        if qsos.count < batchSize {
            break
        }
        offset += batchSize
    }
}

/// Split comma-separated two-fer park references.
nonisolated private func splitParkRefs(_ ref: String) -> [String] {
    ref.split(separator: ",")
        .map { $0.trimmingCharacters(in: .whitespaces) }
        .filter { !$0.isEmpty }
}

/// Build a `MyParkEntry` from a cw-store `parkRollup` row, resolving the park's
/// name/location from the cache (the SQL rollup only carries counts + last-worked).
nonisolated private func parkEntry(from row: ParkRollupRow) -> MyParkEntry {
    let park = POTAParksCache.shared.parkSync(for: row.park)
    return MyParkEntry(
        reference: row.park,
        name: park?.name ?? row.park,
        locationDesc: park?.locationDesc ?? "",
        activationQSOCount: row.activationDays,
        huntQSOCount: row.huntQSOs,
        lastWorked: Date(timeIntervalSince1970: TimeInterval(row.lastWorked))
    )
}

nonisolated private func resolveParkEntries(
    from parkData: [String: ParkActivityAccumulator]
) -> [MyParkEntry] {
    parkData.compactMap { ref, data in
        let park = POTAParksCache.shared.parkSync(for: ref)
        return MyParkEntry(
            reference: ref,
            name: park?.name ?? ref,
            locationDesc: park?.locationDesc ?? "",
            activationQSOCount: data.activationDates.count,
            huntQSOCount: data.hunts,
            lastWorked: data.lastDate
        )
    }
}
