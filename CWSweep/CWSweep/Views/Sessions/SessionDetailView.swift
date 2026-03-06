import CarrierWaveCore
import CarrierWaveData
import MapKit
import SwiftData
import SwiftUI

// MARK: - SessionDetailView

/// Detail view for a logging session, showing stats, metadata, map, states worked, and QSOs
struct SessionDetailView: View {
    // MARK: Internal

    let session: LoggingSession

    var body: some View {
        List {
            sessionSummarySection

            if session.isRove {
                roveStopsSection
            }

            mapSection

            statesWorkedSection

            qsoSection

            detailsSection
        }
        .task(id: session.id) {
            await loadQSOs()
        }
    }

    // MARK: Private

    private static let metadataModes: Set<String> = ["WEATHER", "SOLAR", "NOTE"]

    @Environment(\.modelContext) private var modelContext

    @State private var displayRows: [SessionQSODisplayRow] = []
    @State private var mappableQSOs: [QSO] = []
    @State private var mapPaths: [UUID: [CLLocationCoordinate2D]] = [:]
    @State private var stateCountsCache: [String: Int] = [:]
    @State private var stateCallsignsCache: [String: [String]] = [:]

    // MARK: - Data Loading

    private func loadQSOs() async {
        let sessionStart = session.startedAt
        let sessionEnd = session.endedAt ?? Date()
        let callsign = session.myCallsign

        var descriptor = FetchDescriptor<QSO>(
            predicate: #Predicate {
                $0.myCallsign == callsign
                    && $0.timestamp >= sessionStart
                    && $0.timestamp <= sessionEnd
                    && !$0.isHidden
            },
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        descriptor.fetchLimit = 500

        let fetched = (try? modelContext.fetch(descriptor)) ?? []

        // Dedup by UUID
        var seen = Set<UUID>()
        let dedupedQSOs = fetched.filter { seen.insert($0.id).inserted }

        // Filter metadata modes, snapshot to plain structs
        let displayQSOs = dedupedQSOs.filter {
            !Self.metadataModes.contains($0.mode.uppercased())
        }
        displayRows = displayQSOs.map { SessionQSODisplayRow(from: $0) }

        // Pre-compute derived data (still uses @Model for coordinate lookups)
        computeMappableQSOs(from: displayQSOs)
        computeMapPaths()
        computeStateCounts()
    }

    private func computeMappableQSOs(from qsos: [QSO]) {
        mappableQSOs = qsos.filter { qso in
            guard let grid = qso.theirGrid, grid.count >= 4 else {
                return false
            }
            return MaidenheadConverter.coordinate(from: grid) != nil
        }
    }

    private func computeMapPaths() {
        guard let myGrid = session.myGrid, myGrid.count >= 4,
              let myPos = MaidenheadConverter.coordinate(from: myGrid)
        else {
            mapPaths = [:]
            return
        }
        let myCoord = CLLocationCoordinate2D(
            latitude: myPos.latitude, longitude: myPos.longitude
        )
        var paths: [UUID: [CLLocationCoordinate2D]] = [:]
        for qso in mappableQSOs {
            if let grid = qso.theirGrid,
               let coord = MaidenheadConverter.coordinate(from: grid)
            {
                let clCoord = CLLocationCoordinate2D(
                    latitude: coord.latitude, longitude: coord.longitude
                )
                paths[qso.id] = Self.geodesicPath(
                    from: myCoord, to: clCoord, segments: 20
                )
            }
        }
        mapPaths = paths
    }

    private func computeStateCounts() {
        var counts: [String: Int] = [:]
        var callsigns: [String: [String]] = [:]
        for row in displayRows {
            guard let state = row.state?.uppercased()
                .trimmingCharacters(in: .whitespaces),
                USStates.abbreviations.contains(state)
            else {
                continue
            }
            counts[state, default: 0] += 1
            callsigns[state, default: []].append(row.callsign)
        }
        stateCountsCache = counts
        stateCallsignsCache = callsigns
    }
}

// MARK: - Session Summary Section

extension SessionDetailView {
    private var sessionSummarySection: some View {
        Section {
            statStrip

            let items = buildMetadataItems()
            if !items.isEmpty {
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), alignment: .leading),
                        GridItem(.flexible(), alignment: .leading),
                    ],
                    alignment: .leading,
                    spacing: 6
                ) {
                    ForEach(items, id: \.label) { item in
                        Label(item.label, systemImage: item.icon)
                            .lineLimit(1)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

    private var statStrip: some View {
        HStack(spacing: 0) {
            statCell(value: "\(displayRows.count)", label: "QSOs")
            statDivider
            statCell(value: formattedDuration, label: "Duration")
            if let rate = formattedRate {
                statDivider
                statCell(value: rate, label: "QSOs/hr")
            }
        }
        .padding(.vertical, 4)
    }

    private func statCell(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.headline.monospacedDigit())
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var statDivider: some View {
        Divider().frame(height: 28)
    }

    private var formattedDuration: String {
        let interval = session.duration
        let hours = Int(interval) / 3_600
        let minutes = (Int(interval) % 3_600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }

    private var formattedRate: String? {
        let hours = session.duration / 3_600
        guard hours > 0 else {
            return nil
        }
        let rate = Double(displayRows.count) / hours
        return String(format: "%.1f", rate)
    }

    /// Activation reference (park, summit, etc.) derived from session type
    private var activationReference: String? {
        switch session.activationType {
        case .pota: session.parkReference
        case .sota: session.sotaReference
        case .wwff: session.wwffReference
        case .aoa: session.missionReference
        case .casual: nil
        }
    }

    private func buildMetadataItems() -> [MetadataItem] {
        var items: [MetadataItem] = []
        items.append(MetadataItem(
            icon: "flag.fill",
            label: session.programsDisplayName
        ))
        if let freq = session.frequency {
            items.append(MetadataItem(
                icon: "dial.medium.fill",
                label: String(format: "%.3f MHz", freq)
            ))
        }
        items.append(MetadataItem(
            icon: "waveform", label: session.mode
        ))
        if let ref = activationReference {
            items.append(MetadataItem(
                icon: "leaf.fill", label: ref
            ))
        }
        if let grid = session.myGrid {
            items.append(MetadataItem(
                icon: "square.grid.3x3", label: grid
            ))
        }
        if let power = session.power {
            items.append(MetadataItem(
                icon: "bolt.fill", label: "\(power)W"
            ))
        }
        return items
    }
}

// MARK: - Rove Stops Section

extension SessionDetailView {
    private var roveStopsSection: some View {
        Section("Rove Stops (\(session.uniqueParkCount))") {
            ForEach(session.mergedRoveStops) { stop in
                RoveStopRow(stop: stop)
            }
        }
    }
}

// MARK: - Map Section

extension SessionDetailView {
    @ViewBuilder
    private var mapSection: some View {
        if !mappableQSOs.isEmpty {
            Section("Map") {
                mapPreview(mappable: mappableQSOs)
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
            }
        }
    }

    private func mapPreview(mappable: [QSO]) -> some View {
        let myCoord: CLLocationCoordinate2D? = if let grid = session.myGrid, grid.count >= 4,
                                                  let coord = MaidenheadConverter.coordinate(from: grid)
        {
            CLLocationCoordinate2D(latitude: coord.latitude, longitude: coord.longitude)
        } else {
            nil
        }
        let cachedPaths = mapPaths

        return ZStack(alignment: .bottomTrailing) {
            Map(interactionModes: []) {
                ForEach(mappable) { qso in
                    if let grid = qso.theirGrid,
                       let coord = MaidenheadConverter.coordinate(from: grid)
                    {
                        let clCoord = CLLocationCoordinate2D(
                            latitude: coord.latitude, longitude: coord.longitude
                        )
                        Annotation(qso.callsign, coordinate: clCoord, anchor: .bottom) {
                            SessionMapPin(color: .orange)
                        }
                    }
                }
                if let myCoord {
                    Annotation("Me", coordinate: myCoord, anchor: .bottom) {
                        SessionMapPin(color: .blue, size: 12)
                    }
                    ForEach(mappable) { qso in
                        if let path = cachedPaths[qso.id] {
                            MapPolyline(coordinates: path)
                                .stroke(.white.opacity(0.5), lineWidth: 2.5)
                        }
                    }
                }
            }
            .mapStyle(.standard(elevation: .realistic))
            .allowsHitTesting(false)
            .frame(height: 200)

            HStack(spacing: 4) {
                Image(systemName: "map.fill")
                Text("\(mappable.count) QSOs")
            }
            .font(.caption2)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.thinMaterial, in: Capsule())
            .padding(8)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Session map with \(mappable.count) QSOs")
    }

    /// Great-circle interpolation for geodesic lines on the map
    static func geodesicPath(
        from: CLLocationCoordinate2D,
        to: CLLocationCoordinate2D,
        segments: Int
    ) -> [CLLocationCoordinate2D] {
        let lat1 = from.latitude * .pi / 180
        let lon1 = from.longitude * .pi / 180
        let lat2 = to.latitude * .pi / 180
        let lon2 = to.longitude * .pi / 180

        let dLat = lat2 - lat1
        let dLon = lon2 - lon1
        let a = sin(dLat / 2) * sin(dLat / 2)
            + cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2)
        let angularDist = 2 * atan2(sqrt(a), sqrt(1 - a))

        guard angularDist > 0.001 else {
            return [from, to]
        }

        var points: [CLLocationCoordinate2D] = []
        points.reserveCapacity(segments + 1)

        for i in 0 ... segments {
            let frac = Double(i) / Double(segments)
            let aFrac = sin((1 - frac) * angularDist) / sin(angularDist)
            let bFrac = sin(frac * angularDist) / sin(angularDist)

            let x = aFrac * cos(lat1) * cos(lon1) + bFrac * cos(lat2) * cos(lon2)
            let y = aFrac * cos(lat1) * sin(lon1) + bFrac * cos(lat2) * sin(lon2)
            let z = aFrac * sin(lat1) + bFrac * sin(lat2)

            let lat = atan2(z, sqrt(x * x + y * y)) * 180 / .pi
            let lon = atan2(y, x) * 180 / .pi

            points.append(CLLocationCoordinate2D(latitude: lat, longitude: lon))
        }

        return points
    }
}

// MARK: - States Worked Section

extension SessionDetailView {
    @ViewBuilder
    private var statesWorkedSection: some View {
        if !stateCountsCache.isEmpty {
            Section {
                StatesWorkedMosaic(
                    stateCounts: stateCountsCache,
                    stateCallsigns: stateCallsignsCache
                )
            }
        }
    }
}

// MARK: - QSO Section

extension SessionDetailView {
    @ViewBuilder
    private var qsoSection: some View {
        if session.isRove {
            roveQSOSections
        } else {
            flatQSOSection
        }
    }

    private var flatQSOSection: some View {
        Section("\(displayRows.count) QSO\(displayRows.count == 1 ? "" : "s")") {
            ForEach(displayRows) { row in
                SessionDetailQSORow(row: row)
            }
        }
    }

    @ViewBuilder
    private var roveQSOSections: some View {
        let grouped = roveGroupedQSOs
        ForEach(grouped, id: \.parkReference) { group in
            Section {
                ForEach(group.rows) { row in
                    SessionDetailQSORow(row: row)
                }
            } header: {
                HStack {
                    Text(group.parkReference)
                        .font(.subheadline.monospaced().weight(.semibold))
                    Spacer()
                    Text("\(group.rows.count)Q")
                        .font(.caption)
                }
            }
        }
    }

    private var roveGroupedQSOs: [RoveParkGroup] {
        var parkMap: [String: [SessionQSODisplayRow]] = [:]
        var displayRef: [String: String] = [:]
        for row in displayRows {
            let park = (row.parkReference ?? "").uppercased()
            parkMap[park, default: []].append(row)
            if displayRef[park] == nil {
                displayRef[park] = row.parkReference ?? ""
            }
        }

        return parkMap.map { key, groupRows in
            let sorted = groupRows.sorted { $0.timestamp > $1.timestamp }
            let ref = displayRef[key] ?? key
            return RoveParkGroup(
                parkReference: ref.isEmpty ? "Other" : ref, rows: sorted
            )
        }.sorted {
            ($0.rows.first?.timestamp ?? .distantPast)
                > ($1.rows.first?.timestamp ?? .distantPast)
        }
    }
}
