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

    @State private var qsos: [QSO] = []
    @State private var displayQSOs: [QSO] = []

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
        qsos = fetched.filter { seen.insert($0.id).inserted }

        // Filter metadata modes for display
        displayQSOs = qsos.filter {
            !Self.metadataModes.contains($0.mode.uppercased())
        }
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
            statCell(value: "\(displayQSOs.count)", label: "QSOs")
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
        let rate = Double(displayQSOs.count) / hours
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

// MARK: - RoveStopRow

/// Timeline row showing a single rove stop
private struct RoveStopRow: View {
    // MARK: Internal

    let stop: RoveStop

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(stop.isActive ? Color.green : Color.secondary.opacity(0.3))
                .frame(width: 10, height: 10)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                let parks = ParkReference.split(stop.parkReference)
                ForEach(parks, id: \.self) { park in
                    Text(park)
                        .font(.subheadline.monospaced().weight(.semibold))
                        .foregroundStyle(.green)
                }

                HStack(spacing: 8) {
                    Text(timeRange)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)

                    Text("\(stop.qsoCount) QSOs")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let grid = stop.myGrid {
                        Text(grid)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    // MARK: Private

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()

    private var timeRange: String {
        let start = Self.timeFormatter.string(from: stop.startedAt)
        if let endedAt = stop.endedAt {
            let end = Self.timeFormatter.string(from: endedAt)
            return "\(start)\u{2013}\(end) UTC"
        }
        return "\(start)\u{2013}now UTC"
    }
}

// MARK: - Map Section

extension SessionDetailView {
    @ViewBuilder
    private var mapSection: some View {
        let mappable = displayQSOs.filter { qso in
            guard let grid = qso.theirGrid, grid.count >= 4 else {
                return false
            }
            return MaidenheadConverter.coordinate(from: grid) != nil
        }
        if !mappable.isEmpty {
            Section("Map") {
                mapPreview(mappable: mappable)
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
                        if let grid = qso.theirGrid,
                           let theirCoord = MaidenheadConverter.coordinate(from: grid)
                        {
                            let clCoord = CLLocationCoordinate2D(
                                latitude: theirCoord.latitude, longitude: theirCoord.longitude
                            )
                            MapPolyline(
                                coordinates: Self.geodesicPath(
                                    from: myCoord, to: clCoord, segments: 20
                                )
                            )
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
    private static func geodesicPath(
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
            let f = Double(i) / Double(segments)
            let aFrac = sin((1 - f) * angularDist) / sin(angularDist)
            let bFrac = sin(f * angularDist) / sin(angularDist)

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

// MARK: - SessionMapPin

/// Small map pin marker
private struct SessionMapPin: View {
    let color: Color
    var size: CGFloat = 9

    var body: some View {
        VStack(spacing: 0) {
            Circle()
                .fill(color.opacity(0.8))
                .frame(width: size, height: size)
            Rectangle()
                .fill(color.opacity(0.7))
                .frame(width: max(1.5, size * 0.17), height: max(6, size * 0.67))
        }
    }
}

// MARK: - States Worked Section

extension SessionDetailView {
    @ViewBuilder
    private var statesWorkedSection: some View {
        let counts = stateQSOCounts
        if !counts.isEmpty {
            Section {
                StatesWorkedMosaic(
                    stateCounts: counts,
                    stateCallsigns: stateCallsignMap
                )
            }
        }
    }

    private var stateQSOCounts: [String: Int] {
        var counts: [String: Int] = [:]
        for qso in displayQSOs {
            guard let state = qso.state?.uppercased().trimmingCharacters(in: .whitespaces),
                  USStates.abbreviations.contains(state)
            else {
                continue
            }
            counts[state, default: 0] += 1
        }
        return counts
    }

    private var stateCallsignMap: [String: [String]] {
        var map: [String: [String]] = [:]
        for qso in displayQSOs {
            guard let state = qso.state?.uppercased().trimmingCharacters(in: .whitespaces),
                  USStates.abbreviations.contains(state)
            else {
                continue
            }
            map[state, default: []].append(qso.callsign)
        }
        return map
    }
}

// MARK: - USStates

enum USStates {
    static let ordered: [String] = [
        "AK", "AL", "AR", "AZ", "CA", "CO", "CT", "DE", "FL", "GA",
        "HI", "IA", "ID", "IL", "IN", "KS", "KY", "LA", "MA", "MD",
        "ME", "MI", "MN", "MO", "MS", "MT", "NC", "ND", "NE", "NH",
        "NJ", "NM", "NV", "NY", "OH", "OK", "OR", "PA", "RI", "SC",
        "SD", "TN", "TX", "UT", "VA", "VT", "WA", "WI", "WV", "WY",
    ]

    static let abbreviations: Set<String> = Set(ordered)

    static let names: [String: String] = [
        "AK": "Alaska", "AL": "Alabama", "AR": "Arkansas",
        "AZ": "Arizona", "CA": "California", "CO": "Colorado",
        "CT": "Connecticut", "DE": "Delaware", "FL": "Florida",
        "GA": "Georgia", "HI": "Hawaii", "IA": "Iowa",
        "ID": "Idaho", "IL": "Illinois", "IN": "Indiana",
        "KS": "Kansas", "KY": "Kentucky", "LA": "Louisiana",
        "MA": "Massachusetts", "MD": "Maryland", "ME": "Maine",
        "MI": "Michigan", "MN": "Minnesota", "MO": "Missouri",
        "MS": "Mississippi", "MT": "Montana", "NC": "North Carolina",
        "ND": "North Dakota", "NE": "Nebraska", "NH": "New Hampshire",
        "NJ": "New Jersey", "NM": "New Mexico", "NV": "Nevada",
        "NY": "New York", "OH": "Ohio", "OK": "Oklahoma",
        "OR": "Oregon", "PA": "Pennsylvania", "RI": "Rhode Island",
        "SC": "South Carolina", "SD": "South Dakota", "TN": "Tennessee",
        "TX": "Texas", "UT": "Utah", "VA": "Virginia",
        "VT": "Vermont", "WA": "Washington", "WI": "Wisconsin",
        "WV": "West Virginia", "WY": "Wyoming",
    ]

    static func fullName(for abbreviation: String) -> String? {
        names[abbreviation.uppercased()]
    }
}

// MARK: - StatesWorkedMosaic

struct StatesWorkedMosaic: View {
    // MARK: Internal

    let stateCounts: [String: Int]
    let stateCallsigns: [String: [String]]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            mosaic
            legend
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("States worked mosaic, \(stateCounts.count) of 50 states")
    }

    // MARK: Private

    @State private var selectedState: String?

    @ScaledMetric(relativeTo: .caption2) private var cellHeight: CGFloat = 22

    private let columns = 10
    private let rows = 5
    private let cellSpacing: CGFloat = 2

    private var maxCount: Int {
        stateCounts.values.max() ?? 1
    }

    private var header: some View {
        HStack {
            Label("States Worked", systemImage: "map.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
            Spacer()
            Text("\(stateCounts.count)")
                .font(.subheadline.weight(.bold).monospacedDigit())
                .foregroundStyle(.green) +
                Text(" / 50")
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }

    private var mosaic: some View {
        VStack(spacing: cellSpacing) {
            ForEach(0 ..< rows, id: \.self) { row in
                HStack(spacing: cellSpacing) {
                    ForEach(0 ..< columns, id: \.self) { col in
                        let index = row * columns + col
                        let state = USStates.ordered[index]
                        let count = stateCounts[state] ?? 0
                        mosaicCell(state: state, count: count)
                    }
                }
            }
        }
    }

    private var legend: some View {
        HStack(spacing: 12) {
            legendItem(color: Color.green, label: "3+")
            legendItem(color: Color.green.opacity(0.55), label: "1\u{2013}2")
            legendItem(color: Color(nsColor: .separatorColor), label: "None")
        }
        .accessibilityHidden(true)
    }

    private func mosaicCell(state: String, count: Int) -> some View {
        let isWorked = count > 0

        return Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                selectedState = selectedState == state ? nil : state
            }
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 3)
                    .fill(cellColor(count: count))

                if selectedState == state {
                    RoundedRectangle(cornerRadius: 3)
                        .strokeBorder(Color.primary.opacity(0.5), lineWidth: 1)
                }

                Text(state)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(
                        isWorked
                            ? Color(nsColor: .windowBackgroundColor)
                            : Color(nsColor: .tertiaryLabelColor)
                    )
            }
            .frame(maxWidth: .infinity)
            .frame(height: cellHeight)
        }
        .buttonStyle(.plain)
        .popover(
            isPresented: Binding(
                get: { selectedState == state },
                set: { if !$0 {
                    selectedState = nil
                } }
            ),
            arrowEdge: .top
        ) {
            statePopover(state: state, count: count)
        }
        .accessibilityLabel(cellAccessibilityLabel(state: state, count: count))
        .accessibilityHint(count > 0 ? "Tap to see callsigns" : "")
    }

    private func statePopover(state: String, count: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(state)
                    .font(.headline.monospaced())
                if let name = USStates.names[state] {
                    Text(name)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Text("\(count) QSO\(count == 1 ? "" : "s")")
                .font(.subheadline.weight(.medium))

            if let callsigns = stateCallsigns[state] {
                let unique = Array(Set(callsigns)).sorted()
                Text(unique.joined(separator: ", "))
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func legendItem(color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2)
                .fill(color)
                .frame(width: 10, height: 10)
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
    }

    private func cellColor(count: Int) -> Color {
        guard count > 0 else {
            return Color(nsColor: .separatorColor)
        }
        let intensity = 0.4 + min(Double(count) / Double(max(maxCount, 1)), 1.0) * 0.6
        return Color.green.opacity(intensity)
    }

    private func cellAccessibilityLabel(state: String, count: Int) -> String {
        let name = USStates.names[state] ?? state
        if count > 0 {
            return "\(name), \(count) QSO\(count == 1 ? "" : "s")"
        }
        return "\(name), not worked"
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
        Section("\(displayQSOs.count) QSO\(displayQSOs.count == 1 ? "" : "s")") {
            ForEach(displayQSOs.sorted { $0.timestamp > $1.timestamp }) { qso in
                SessionDetailQSORow(qso: qso)
            }
        }
    }

    @ViewBuilder
    private var roveQSOSections: some View {
        let grouped = roveGroupedQSOs
        ForEach(grouped, id: \.parkReference) { group in
            Section {
                ForEach(group.qsos) { qso in
                    SessionDetailQSORow(qso: qso)
                }
            } header: {
                HStack {
                    Text(group.parkReference)
                        .font(.subheadline.monospaced().weight(.semibold))
                    Spacer()
                    Text("\(group.qsos.count)Q")
                        .font(.caption)
                }
            }
        }
    }

    private var roveGroupedQSOs: [RoveParkGroup] {
        var parkMap: [String: [QSO]] = [:]
        var displayRef: [String: String] = [:]
        for qso in displayQSOs {
            let park = (qso.parkReference ?? "").uppercased()
            parkMap[park, default: []].append(qso)
            if displayRef[park] == nil {
                displayRef[park] = qso.parkReference ?? ""
            }
        }

        return parkMap.map { key, groupQSOs in
            let sorted = groupQSOs.sorted { $0.timestamp > $1.timestamp }
            let ref = displayRef[key] ?? key
            return RoveParkGroup(parkReference: ref.isEmpty ? "Other" : ref, qsos: sorted)
        }.sorted {
            ($0.qsos.first?.timestamp ?? .distantPast) > ($1.qsos.first?.timestamp ?? .distantPast)
        }
    }
}

// MARK: - RoveParkGroup

/// Grouped QSOs for a rove park
private struct RoveParkGroup {
    let parkReference: String
    let qsos: [QSO]
}

// MARK: - SessionDetailQSORow

/// Compact QSO row for the session detail
private struct SessionDetailQSORow: View {
    // MARK: Internal

    let qso: QSO

    var body: some View {
        HStack(spacing: 8) {
            Text(qso.callsign)
                .font(.subheadline.monospaced().weight(.semibold))

            Spacer()

            pill(qso.band, color: .blue)
            pill(qso.mode, color: .green)

            if let rst = qso.rstSent {
                Text(rst)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }

            if let grid = qso.theirGrid {
                Text(grid)
                    .font(.caption.monospaced())
                    .foregroundStyle(.purple)
            }

            Text(Self.timeFormatter.string(from: qso.timestamp))
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
    }

    // MARK: Private

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()

    private func pill(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15))
            .clipShape(Capsule())
    }
}

// MARK: - Details Section

extension SessionDetailView {
    @ViewBuilder
    private var detailsSection: some View {
        let hasEquipment = session.myRig != nil || session.myAntenna != nil
            || session.myKey != nil || session.myMic != nil
            || session.extraEquipment != nil
        let hasNotes = session.attendees != nil || session.notes != nil

        if hasEquipment || hasNotes {
            Section {
                DisclosureGroup("Details") {
                    if hasEquipment {
                        equipmentRows
                    }
                    if hasNotes {
                        notesRows
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var equipmentRows: some View {
        if let rig = session.myRig {
            Label(rig, systemImage: "radio")
        }
        if let antenna = session.myAntenna {
            Label(antenna, systemImage: "antenna.radiowaves.left.and.right")
        }
        if let key = session.myKey {
            Label(key, systemImage: "pianokeys")
        }
        if let mic = session.myMic {
            Label(mic, systemImage: "mic")
        }
        if let extra = session.extraEquipment {
            Text(extra)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var notesRows: some View {
        if let attendees = session.attendees {
            LabeledContent("Attendees") {
                Text(attendees)
                    .font(.subheadline.monospaced())
            }
        }
        if let notes = session.notes {
            Text(notes)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - MetadataItem

private struct MetadataItem {
    let icon: String
    let label: String
}
