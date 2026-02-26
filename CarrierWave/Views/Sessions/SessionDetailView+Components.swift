// Session Detail View - Components
//
// Extracted helper views and types for SessionDetailView:
// RoveStopDetailRow, RoveParkGroup, PhotoItem, session info sections.

import CarrierWaveCore
import MapKit
import SwiftUI

// MARK: - Session Info Sections

extension SessionDetailView {
    func sessionSummarySection(_ session: LoggingSession) -> some View {
        Section {
            statStrip(
                qsoCount: qsos.count,
                duration: session.formattedDuration,
                rate: qsos.isEmpty ? nil : formattedQSOsPerHour
            )

            let items = buildSessionMetadataItems(session)
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

    func roveStopsSection(_ session: LoggingSession) -> some View {
        Section("Rove Stops (\(session.uniqueParkCount))") {
            ForEach(session.mergedRoveStops) { stop in
                RoveStopDetailRow(stop: stop)
            }
        }
    }

    // MARK: - Stat Strip

    func statStrip(
        qsoCount: Int, duration: String, rate: String?
    ) -> some View {
        HStack(spacing: 0) {
            statCell(value: "\(qsoCount)", label: "QSOs")
            statDivider
            statCell(value: duration, label: "Duration")
            if let rate {
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

    // MARK: - Details Section (Collapsed)

    @ViewBuilder
    func detailsSection(_ session: LoggingSession) -> some View {
        let hasEquipment = session.myRig != nil || session.myAntenna != nil
            || session.myKey != nil || session.myMic != nil
            || session.extraEquipment != nil
        let hasNotes = session.attendees != nil || session.notes != nil
        let hasPhotos = !session.photoFilenames.isEmpty

        if hasEquipment || hasNotes || hasPhotos {
            Section {
                DisclosureGroup("Details") {
                    if hasEquipment {
                        equipmentRows(session)
                    }
                    if hasNotes {
                        notesRows(session)
                    }
                    if hasPhotos {
                        photosRow(session)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func equipmentRows(_ session: LoggingSession) -> some View {
        if let rig = session.myRig {
            Label(rig, systemImage: "radio")
        }
        if let antenna = session.myAntenna {
            Label(
                antenna,
                systemImage: "antenna.radiowaves.left.and.right"
            )
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
    private func notesRows(_ session: LoggingSession) -> some View {
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

    private func photosRow(_ session: LoggingSession) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(
                    session.photoFilenames, id: \.self
                ) { filename in
                    let url = SessionPhotoManager.photoURL(
                        filename: filename, sessionID: session.id
                    )
                    Button {
                        selectedPhoto = PhotoItem(filename: filename)
                    } label: {
                        AsyncImage(url: url) { image in
                            image.resizable()
                                .aspectRatio(contentMode: .fill)
                        } placeholder: {
                            Color.gray.opacity(0.3)
                        }
                        .frame(width: 100, height: 100)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Session Metadata

    private func buildSessionMetadataItems(
        _ session: LoggingSession
    ) -> [MetadataItem] {
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
        if let ref = session.activationReference {
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

    func computeStatistics() {
        guard statisticianMode else {
            activationStatistics = nil
            return
        }
        if let activation, let activationMetadata {
            activationStatistics = ActivationStatistics.compute(
                from: activation, metadata: activationMetadata
            )
        } else if let activation {
            activationStatistics = ActivationStatistics.compute(
                from: activation, metadata: nil
            )
        } else if qsos.count >= 2 {
            activationStatistics = ActivationStatistics.compute(from: qsos)
        } else {
            activationStatistics = nil
        }
    }

    var formattedQSOsPerHour: String {
        guard let session else {
            return "\(qsos.count)"
        }
        let hours = session.duration / 3_600
        guard hours > 0 else {
            return "\(qsos.count)"
        }
        let rate = Double(qsos.count) / hours
        return String(format: "%.1f", rate)
    }
}

// MARK: - Map Section

extension SessionDetailView {
    @ViewBuilder
    var mapSection: some View {
        let mappable = displayQSOs.filter { qso in
            guard let grid = qso.theirGrid, grid.count >= 4 else {
                return false
            }
            return MaidenheadConverter.coordinate(from: grid) != nil
        }
        if !mappable.isEmpty {
            Section("Map") {
                NavigationLink {
                    mapDestination
                } label: {
                    mapPreview(mappable: mappable)
                }
                .buttonStyle(.plain)
                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
            }
        }
    }

    @ViewBuilder
    private var mapDestination: some View {
        if let activation {
            ActivationMapView(
                activation: activation,
                parkName: parkName,
                metadata: activationMetadata,
                roveStops: session?.isRove == true
                    ? (session?.mergedRoveStops ?? []) : []
            )
        } else {
            SidebarMapView(
                sessionQSOs: qsos,
                myGrid: session?.myGrid,
                roveStops: session?.isRove == true
                    ? (session?.mergedRoveStops ?? []) : []
            )
            .navigationTitle("Session Map")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func mapPreview(mappable: [QSO]) -> some View {
        let myGridStr = session?.myGrid ?? activation?.qsos.first?.myGrid
        let myCoord: CLLocationCoordinate2D? = if let grid = myGridStr, grid.count >= 4 {
            MaidenheadConverter.coordinate(from: grid)
        } else {
            nil
        }
        return ZStack(alignment: .bottomTrailing) {
            mapPreviewContent(mappable: mappable, myCoord: myCoord)
                .frame(height: 200)

            HStack(spacing: 4) {
                Image(systemName: "map.fill")
                Text("\(mappable.count) QSOs")
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .font(.caption2)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.thinMaterial, in: Capsule())
            .padding(8)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Session map with \(mappable.count) QSOs")
        .accessibilityHint("Tap to view full map")
        .accessibilityAddTraits(.isButton)
    }

    private func mapPreviewContent(
        mappable: [QSO], myCoord: CLLocationCoordinate2D?
    ) -> some View {
        Map(interactionModes: []) {
            ForEach(mappable) { qso in
                if let grid = qso.theirGrid,
                   let coord = MaidenheadConverter.coordinate(from: grid)
                {
                    Annotation(qso.callsign, coordinate: coord, anchor: .center) {
                        Circle()
                            .fill(.green)
                            .frame(width: 8, height: 8)
                            .overlay(Circle().stroke(.white, lineWidth: 1))
                    }
                }
            }
            if let myCoord {
                Annotation("Me", coordinate: myCoord, anchor: .center) {
                    Circle()
                        .fill(.blue)
                        .frame(width: 10, height: 10)
                        .overlay(Circle().stroke(.white, lineWidth: 2))
                }
                ForEach(mappable) { qso in
                    if let grid = qso.theirGrid,
                       let theirCoord = MaidenheadConverter.coordinate(from: grid)
                    {
                        MapPolyline(
                            coordinates: ActivationMapHelpers.geodesicPath(
                                from: myCoord, to: theirCoord, segments: 20
                            )
                        )
                        .stroke(.blue.opacity(0.4), lineWidth: 1.5)
                    }
                }
            }
        }
        .mapStyle(.standard(elevation: .flat))
        .allowsHitTesting(false)
    }
}

// MARK: - RoveStopDetailRow

/// Timeline row showing a single rove stop with park, time range, QSO count, and grid
struct RoveStopDetailRow: View {
    // MARK: Internal

    let stop: RoveStop

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(stop.isActive ? Color.green : Color(.systemGray3))
                .frame(width: 10, height: 10)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                let parks = ParkReference.split(stop.parkReference)
                ForEach(parks, id: \.self) { park in
                    HStack(spacing: 6) {
                        Text(park)
                            .font(.subheadline.monospaced().weight(.semibold))
                            .foregroundStyle(.green)
                        if let name = POTAParksCache.shared.nameSync(for: park) {
                            Text(name)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
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

// MARK: - RoveParkGroup

/// A group of QSOs at a single park within a rove
struct RoveParkGroup {
    let parkReference: String
    let qsos: [QSO]

    /// First individual park ref (for name lookup when n-fer)
    var primaryPark: String {
        ParkReference.split(parkReference).first ?? parkReference
    }
}

// MARK: - PhotoItem

/// Identifiable wrapper for photo filenames (used for fullScreenCover)
struct PhotoItem: Identifiable {
    let filename: String

    var id: String {
        filename
    }
}
