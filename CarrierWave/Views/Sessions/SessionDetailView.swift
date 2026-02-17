import CarrierWaveCore
import SwiftData
import SwiftUI

// MARK: - SessionDetailView

/// Detail view for sessions showing metadata, equipment, photos, and QSO list.
struct SessionDetailView: View {
    // MARK: Internal

    let session: LoggingSession

    var body: some View {
        List {
            infoSection
            if session.isRove {
                roveStopsSection
            }
            equipmentSection
            if session.attendees != nil || session.notes != nil {
                notesSection
            }
            if !session.photoFilenames.isEmpty {
                photosSection
            }
            SessionSpotsSection(session: session)
            qsoSection
        }
        .navigationTitle(session.displayTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Edit") {
                    showEditSheet = true
                }
            }
        }
        .sheet(isPresented: $showEditSheet) {
            SessionMetadataEditSheet(
                session: session,
                metadata: nil,
                userGrid: session.myGrid,
                onSave: { result in
                    applyEditResult(result)
                    showEditSheet = false
                },
                onCancel: { showEditSheet = false }
            )
        }
        .fullScreenCover(item: $selectedPhoto) { photo in
            PhotoViewer(
                url: SessionPhotoManager.photoURL(
                    filename: photo.filename, sessionID: session.id
                )
            )
        }
        .task {
            await loadQSOs()
        }
    }

    // MARK: Private

    @Environment(\.modelContext) private var modelContext
    @State private var qsos: [QSO] = []
    @State private var showEditSheet = false
    @State private var selectedPhoto: PhotoItem?

    private var formattedQSOsPerHour: String {
        let hours = session.duration / 3_600
        guard hours > 0 else {
            return "\(qsos.count)"
        }
        let rate = Double(qsos.count) / hours
        return String(format: "%.1f", rate)
    }

    /// Group QSOs by park reference, ordered by rove stop order
    private var roveGroupedQSOs: [RoveParkGroup] {
        let stops = session.roveStops
        let sorted = qsos.sorted { $0.timestamp > $1.timestamp }

        // Build groups in rove stop order
        var groups: [RoveParkGroup] = []
        var usedParks = Set<String>()

        for stop in stops {
            let park = stop.parkReference.uppercased()
            guard !usedParks.contains(park) else {
                continue
            }
            usedParks.insert(park)

            let stopQSOs = sorted.filter { $0.parkReference?.uppercased() == park }
            if !stopQSOs.isEmpty {
                groups.append(RoveParkGroup(parkReference: stop.parkReference, qsos: stopQSOs))
            }
        }

        // Catch any QSOs not matching a rove stop
        let ungrouped = sorted.filter { qso in
            guard let park = qso.parkReference?.uppercased() else {
                return true
            }
            return !usedParks.contains(park)
        }
        if !ungrouped.isEmpty {
            groups.append(RoveParkGroup(parkReference: "Other", qsos: ungrouped))
        }

        return groups
    }

    private var infoSection: some View {
        Section("Session Info") {
            LabeledContent("Type", value: session.activationType.displayName)

            if let freq = session.frequency {
                LabeledContent("Frequency") {
                    Text(String(format: "%.3f MHz", freq))
                }
            }

            LabeledContent("Mode", value: session.mode)

            LabeledContent("Duration", value: session.formattedDuration)

            if !qsos.isEmpty {
                LabeledContent("QSOs/Hour") {
                    Text(formattedQSOsPerHour)
                }
            }

            if let ref = session.activationReference {
                LabeledContent("Reference", value: ref)
            }

            if let grid = session.myGrid {
                LabeledContent("Grid", value: grid)
            }

            if let power = session.power {
                LabeledContent("Power") {
                    Text("\(power)W")
                }
            }
        }
    }

    private var roveStopsSection: some View {
        Section("Rove Stops (\(session.roveStopCount))") {
            ForEach(session.roveStops) { stop in
                RoveStopDetailRow(stop: stop)
            }
        }
    }

    @ViewBuilder
    private var equipmentSection: some View {
        let hasEquipment = session.myRig != nil || session.myAntenna != nil
            || session.myKey != nil || session.myMic != nil
            || session.extraEquipment != nil

        if hasEquipment {
            Section("Equipment") {
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
        }
    }

    private var notesSection: some View {
        Section {
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
        } header: {
            Text("Notes")
        }
    }

    private var photosSection: some View {
        Section("Photos") {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(session.photoFilenames, id: \.self) { filename in
                        let url = SessionPhotoManager.photoURL(
                            filename: filename, sessionID: session.id
                        )
                        Button {
                            selectedPhoto = PhotoItem(filename: filename)
                        } label: {
                            AsyncImage(url: url) { image in
                                image.resizable().aspectRatio(contentMode: .fill)
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
    }

    @ViewBuilder
    private var qsoSection: some View {
        if session.isRove {
            roveQSOSections
        } else {
            flatQSOSection
        }
    }

    private var flatQSOSection: some View {
        Section("\(qsos.count) QSO\(qsos.count == 1 ? "" : "s")") {
            ForEach(qsos.sorted { $0.timestamp > $1.timestamp }) { qso in
                SessionQSORow(qso: qso)
            }
        }
    }

    @ViewBuilder
    private var roveQSOSections: some View {
        let grouped = roveGroupedQSOs
        ForEach(grouped, id: \.parkReference) { group in
            Section {
                ForEach(group.qsos) { qso in
                    SessionQSORow(qso: qso)
                }
            } header: {
                HStack {
                    Text(group.parkReference)
                        .font(.subheadline.monospaced().weight(.semibold))
                    if let name = POTAParksCache.shared.nameSync(for: group.primaryPark) {
                        Text(name)
                            .font(.caption)
                    }
                    Spacer()
                    Text("\(group.qsos.count)Q")
                        .font(.caption)
                }
            }
        }
    }

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

        qsos = (try? modelContext.fetch(descriptor)) ?? []
    }

    private func applyEditResult(_ result: SessionMetadataEditResult) {
        session.customTitle = result.title
        session.power = result.watts
        session.myRig = result.radio
        session.myAntenna = result.antenna
        session.myKey = result.key
        session.myMic = result.mic
        session.extraEquipment = result.extraEquipment
        session.attendees = result.attendees
        session.notes = result.notes

        // Handle photos
        for photo in result.addedPhotos {
            if let filename = try? SessionPhotoManager.savePhoto(
                photo, sessionID: session.id
            ) {
                session.photoFilenames.append(filename)
            }
        }
        for filename in result.deletedPhotoFilenames {
            try? SessionPhotoManager.deletePhoto(
                filename: filename, sessionID: session.id
            )
            session.photoFilenames.removeAll { $0 == filename }
        }

        try? modelContext.save()
    }
}

// MARK: - RoveStopDetailRow

/// Timeline row showing a single rove stop with park, time range, QSO count, and grid
private struct RoveStopDetailRow: View {
    // MARK: Internal

    let stop: RoveStop

    var body: some View {
        HStack(spacing: 12) {
            // Timeline indicator
            Circle()
                .fill(stop.isActive ? Color.green : Color(.systemGray3))
                .frame(width: 10, height: 10)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                // Park reference + resolved name
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

                // Time range + stats
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
private struct RoveParkGroup {
    let parkReference: String
    let qsos: [QSO]

    /// First individual park ref (for name lookup when n-fer)
    var primaryPark: String {
        ParkReference.split(parkReference).first ?? parkReference
    }
}

// MARK: - SessionQSORow

/// Shared QSO row used in session detail
private struct SessionQSORow: View {
    let qso: QSO

    var body: some View {
        HStack {
            Text(qso.callsign)
                .font(.subheadline)
            Spacer()
            Text(qso.band)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(qso.mode)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(
                qso.timestamp.formatted(date: .omitted, time: .shortened)
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
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
