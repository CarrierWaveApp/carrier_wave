// Session Detail View - QSO Sections & Data Loading
//
// Extracted QSO list sections and data loading for SessionDetailView.
// Handles both flat and rove-grouped QSO display.

import CarrierWaveCore
import SwiftData
import SwiftUI

// MARK: - QSO Sections

extension SessionDetailView {
    @ViewBuilder
    var qsoSection: some View {
        if let session, session.isRove {
            roveQSOSections
        } else {
            flatQSOSection
        }
    }

    var flatQSOSection: some View {
        Section("\(qsos.count) QSO\(qsos.count == 1 ? "" : "s")") {
            ForEach(qsos.sorted { $0.timestamp > $1.timestamp }) { qso in
                Button {
                    qsoToEdit = qso
                } label: {
                    if activation != nil {
                        POTAQSORow(
                            qso: qso, parks: activation?.parks ?? [],
                            isSpotted: spotQSOMatch?.qsoWasSpotted(qso) ?? false
                        )
                    } else {
                        SessionQSORow(
                            qso: qso,
                            isSpotted: spotQSOMatch?.qsoWasSpotted(qso) ?? false
                        )
                    }
                }
                .tint(.primary)
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
    var roveQSOSections: some View {
        let grouped = roveGroupedQSOs
        ForEach(grouped, id: \.parkReference) { group in
            Section {
                ForEach(group.qsos) { qso in
                    Button {
                        qsoToEdit = qso
                    } label: {
                        if activation != nil {
                            POTAQSORow(
                                qso: qso, parks: activation?.parks ?? [],
                                isSpotted: spotQSOMatch?.qsoWasSpotted(qso) ?? false
                            )
                        } else {
                            SessionQSORow(
                                qso: qso,
                                isSpotted: spotQSOMatch?.qsoWasSpotted(qso) ?? false
                            )
                        }
                    }
                    .tint(.primary)
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

    /// Group QSOs by park reference, sorted by latest QSO timestamp (most recent park first).
    var roveGroupedQSOs: [RoveParkGroup] {
        var parkMap: [String: [QSO]] = [:]
        var displayRef: [String: String] = [:]
        for qso in qsos {
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

// MARK: - Data Loading

extension SessionDetailView {
    func loadQSOs() async {
        guard let session else {
            // For orphan activations without a session, use activation QSOs
            if let activation {
                qsos = activation.qsos
                    .filter { !hiddenQSOIds.contains($0.id) }
                    .sorted { $0.timestamp > $1.timestamp }
            }
            return
        }

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

        // Build spot/QSO cross-reference for display linking
        let sessionId = session.id
        let spotPredicate = #Predicate<SessionSpot> { spot in
            spot.loggingSessionId == sessionId
        }
        var spotDescriptor = FetchDescriptor<SessionSpot>(predicate: spotPredicate)
        spotDescriptor.fetchLimit = 500
        let spots = (try? modelContext.fetch(spotDescriptor)) ?? []
        if !spots.isEmpty {
            spotQSOMatch = SpotQSOMatch(qsos: qsos, spots: spots)
        }
    }

    func applyEditResult(_ result: SessionMetadataEditResult) {
        guard let session else {
            return
        }

        session.customTitle = result.title
        session.power = result.watts
        session.myRig = result.radio
        session.myAntenna = result.antenna
        session.myKey = result.key
        session.myMic = result.mic
        session.extraEquipment = result.extraEquipment
        session.attendees = result.attendees
        session.notes = result.notes

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
