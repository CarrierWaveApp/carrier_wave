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

    private var qsoSection: some View {
        Section("\(qsos.count) QSO\(qsos.count == 1 ? "" : "s")") {
            ForEach(qsos.sorted { $0.timestamp > $1.timestamp }) { qso in
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

// MARK: - PhotoItem

/// Identifiable wrapper for photo filenames (used for fullScreenCover)
struct PhotoItem: Identifiable {
    let filename: String

    var id: String {
        filename
    }
}
