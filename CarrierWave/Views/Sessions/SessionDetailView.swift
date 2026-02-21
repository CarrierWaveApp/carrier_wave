import CarrierWaveCore
import SwiftData
import SwiftUI

// MARK: - SessionDetailView

/// Detail view for sessions showing metadata, equipment, photos, and QSO list.
struct SessionDetailView: View {
    // MARK: Internal

    let session: LoggingSession
    var onShare: (() -> Void)?
    var onExport: (() -> Void)?
    var onMap: (() -> Void)?

    var body: some View {
        let _ = statisticianMode
        List {
            infoSection
            if session.isRove {
                roveStopsSection
            }
            if let stats = sessionStatistics, statisticianMode {
                Section("Statistics") {
                    ActivationStatsChartsView(stats: stats, qsos: qsos)
                    ActivationStatsSummaryView(stats: stats)
                }
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
                actionsMenu
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
        .alert(
            "Delete QSO",
            isPresented: Binding(
                get: { qsoToDelete != nil },
                set: { newValue in
                    if !newValue {
                        qsoToDelete = nil
                    }
                }
            )
        ) {
            Button("Delete", role: .destructive) {
                if let qso = qsoToDelete {
                    qso.isHidden = true
                    qsos.removeAll { $0.id == qso.id }
                    try? modelContext.save()
                }
                qsoToDelete = nil
            }
            Button("Cancel", role: .cancel) {
                qsoToDelete = nil
            }
        } message: {
            if let qso = qsoToDelete {
                Text("Delete QSO with \(qso.callsign)?")
            }
        }
        .task {
            await loadQSOs()
            if statisticianMode, qsos.count >= 2 {
                sessionStatistics = ActivationStatistics.compute(from: qsos)
            }
        }
        .onChange(of: statisticianMode) { _, newValue in
            if newValue, qsos.count >= 2 {
                sessionStatistics = ActivationStatistics.compute(from: qsos)
            } else {
                sessionStatistics = nil
            }
        }
    }

    // MARK: Private

    @Environment(\.modelContext) private var modelContext
    @AppStorage("statisticianMode") private var statisticianMode = false
    @State private var qsos: [QSO] = []
    @State private var sessionStatistics: ActivationStatistics?
    @State private var showEditSheet = false
    @State private var selectedPhoto: PhotoItem?
    @State private var qsoToDelete: QSO?

    private var hasActions: Bool {
        onShare != nil || onExport != nil || onMap != nil
    }

    private var formattedQSOsPerHour: String {
        let hours = session.duration / 3_600
        guard hours > 0 else {
            return "\(qsos.count)"
        }
        let rate = Double(qsos.count) / hours
        return String(format: "%.1f", rate)
    }

    /// Group QSOs by park reference, sorted by latest QSO timestamp (most recent park first).
    private var roveGroupedQSOs: [RoveParkGroup] {
        // Group QSOs by park reference
        var parkMap: [String: [QSO]] = [:]
        var displayRef: [String: String] = [:]
        for qso in qsos {
            let park = (qso.parkReference ?? "").uppercased()
            parkMap[park, default: []].append(qso)
            if displayRef[park] == nil {
                displayRef[park] = qso.parkReference ?? ""
            }
        }

        // Sort QSOs within each group latest-first, then sort groups by latest QSO
        return parkMap.map { key, groupQSOs in
            let sorted = groupQSOs.sorted { $0.timestamp > $1.timestamp }
            let ref = displayRef[key] ?? key
            return RoveParkGroup(parkReference: ref.isEmpty ? "Other" : ref, qsos: sorted)
        }.sorted {
            ($0.qsos.first?.timestamp ?? .distantPast) > ($1.qsos.first?.timestamp ?? .distantPast)
        }
    }

    private var actionsMenu: some View {
        Group {
            if hasActions {
                Menu {
                    Button {
                        showEditSheet = true
                    } label: {
                        Label("Edit Info", systemImage: "pencil")
                    }
                    if let onMap {
                        Button {
                            onMap()
                        } label: {
                            Label("View Map", systemImage: "map")
                        }
                    }
                    if let onExport {
                        Button {
                            onExport()
                        } label: {
                            Label("Export ADIF", systemImage: "doc.text")
                        }
                    }
                    if let onShare {
                        Button {
                            onShare()
                        } label: {
                            Label("Brag Sheet", systemImage: "square.and.arrow.up")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            } else {
                Button("Edit") {
                    showEditSheet = true
                }
            }
        }
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
        Section("Rove Stops (\(session.uniqueParkCount))") {
            ForEach(session.mergedRoveStops) { stop in
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
}

// MARK: - QSO Sections & Data Loading

extension SessionDetailView {
    @ViewBuilder
    var qsoSection: some View {
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
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            qsoToDelete = qso
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
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
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                qsoToDelete = qso
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
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

    func loadQSOs() async {
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

    func applyEditResult(_ result: SessionMetadataEditResult) {
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
