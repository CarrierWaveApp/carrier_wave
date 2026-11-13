// Session Detail View - Components
//
// Extracted helper views and types for SessionDetailView:
// stat strip, rove stops, details section, map section,
// insights carousel, and supporting types.

import CarrierWaveData
import SwiftData
import SwiftUI

// MARK: - Session Detail Helpers

extension SessionDetailView {
    func roveStopsSection(_ session: LoggingSession) -> some View {
        Section("Rove Stops (\(session.uniqueParkCount))") {
            ForEach(session.mergedRoveStops) { stop in
                RoveStopDetailRow(stop: stop)
            }
        }
    }

    func computePercentiles() {
        let currentCount: Int
        let currentDuration: TimeInterval
        if let activation {
            currentCount = activation.qsoCount
            currentDuration = activation.duration
        } else if let session {
            currentCount = qsos.count
            currentDuration = session.duration
        } else {
            return
        }

        guard let allSessions = fetchCompletedSessions(),
              allSessions.count >= 3
        else {
            return
        }

        let qsoP = percentileRank(
            of: currentCount, in: allSessions.map(\.qsoCount).sorted()
        )
        let durP = percentileRank(
            of: currentDuration, in: allSessions.map(\.duration).sorted()
        )
        let rateP = computeRatePercentile(
            count: currentCount, duration: currentDuration,
            allSessions: allSessions
        )

        percentiles = SessionPercentiles(
            qsoCountPercentile: qsoP,
            durationPercentile: durP,
            ratePercentile: rateP
        )
    }

    private func fetchCompletedSessions() -> [LoggingSession]? {
        var descriptor = FetchDescriptor<LoggingSession>(
            predicate: #Predicate {
                $0.endedAt != nil && $0.qsoCount > 0
            }
        )
        descriptor.fetchLimit = 1_000
        return try? modelContext.fetch(descriptor)
    }

    private func computeRatePercentile(
        count: Int, duration: TimeInterval,
        allSessions: [LoggingSession]
    ) -> Int? {
        let hours = duration / 3_600
        guard hours > 0, count > 0 else {
            return nil
        }
        let currentRate = Double(count) / hours
        let rates = allSessions.compactMap { sess -> Double? in
            let hr = sess.duration / 3_600
            guard hr > 0 else {
                return nil
            }
            return Double(sess.qsoCount) / hr
        }.sorted()
        guard rates.count >= 3 else {
            return nil
        }
        return percentileRank(of: currentRate, in: rates)
    }

    /// Returns the "top X%" rank (100 = bottom, 1 = top).
    private func percentileRank<T: Comparable>(
        of value: T, in sorted: [T]
    ) -> Int {
        guard !sorted.isEmpty else {
            return 50
        }
        let below = sorted.filter { $0 < value }.count
        let rank = Double(below) / Double(sorted.count) * 100
        return max(1, 100 - Int(rank))
    }

    // MARK: - Notes & Photos Section

    func hasNotesOrPhotos(_ session: LoggingSession) -> Bool {
        session.attendees != nil || session.notes != nil
            || !session.photoFilenames.isEmpty
    }

    @ViewBuilder
    func notesAndPhotosSection(_ session: LoggingSession) -> some View {
        let hasNotes = session.attendees != nil || session.notes != nil
        let hasPhotos = !session.photoFilenames.isEmpty

        Section {
            if hasNotes {
                notesRows(session)
            }
            if hasPhotos {
                photosRow(session)
            }
        }
    }

    @ViewBuilder
    private func equipmentRows(_ session: LoggingSession) -> some View {
        if let rig = session.myRig {
            Label(rig, systemImage: "radio")
                .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
        }
        if let antenna = session.myAntenna {
            Label(
                antenna,
                systemImage: "antenna.radiowaves.left.and.right"
            )
            .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
        }
        if let key = session.myKey {
            Label(key, systemImage: "pianokeys")
                .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
        }
        if let mic = session.myMic {
            Label(mic, systemImage: "mic")
                .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
        }
        if let extra = session.extraEquipment {
            Text(extra)
                .foregroundStyle(.secondary)
                .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
        }
    }

    @ViewBuilder
    private func notesRows(_ session: LoggingSession) -> some View {
        if let attendees = session.attendees {
            LabeledContent("Attendees") {
                Text(attendees)
                    .font(.subheadline.monospaced())
            }
            .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
        }
        if let notes = session.notes {
            Text(notes)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
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

    // MARK: - Session Metadata Helpers

    /// Grid label for session metadata: shows all unique grids for roves
    func sessionGridLabel(
        _ session: LoggingSession
    ) -> String? {
        if session.isRove {
            let grids = session.roveStops
                .compactMap(\.myGrid)
            let unique = Array(Set(grids)).sorted()
            if !unique.isEmpty {
                return unique.joined(separator: ", ")
            }
        }
        return session.myGrid
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

// MARK: - SessionPercentiles

/// Percentile rankings for this session vs all completed sessions
struct SessionPercentiles {
    /// "Top X%" for QSO count (1 = best, 100 = worst)
    let qsoCountPercentile: Int
    /// "Top X%" for duration
    let durationPercentile: Int
    /// "Top X%" for QSOs/hr (nil if not enough data)
    let ratePercentile: Int?
}

// MARK: - PhotoItem

/// Identifiable wrapper for photo filenames (used for fullScreenCover)
struct PhotoItem: Identifiable {
    let filename: String

    var id: String {
        filename
    }
}
