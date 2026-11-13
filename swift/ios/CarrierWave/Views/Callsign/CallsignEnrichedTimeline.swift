import CarrierWaveCore
import CarrierWaveData
import SwiftUI

// MARK: - EnrichedTimelineItem

/// A unified timeline item merging a QSO with its associated recording context,
/// or a standalone tune-in recording without a specific QSO.
struct EnrichedTimelineItem: Identifiable {
    let qso: QSO?
    let recording: WebSDRRecording?
    let callsignRanges: [DetectedQSORange]
    let clip: QSORecordingClip?

    var id: UUID {
        qso?.id ?? recording?.id ?? UUID()
    }

    var date: Date {
        qso?.timestamp ?? recording?.startedAt ?? .distantPast
    }

    var isTuneIn: Bool {
        qso == nil && recording?.spotCallsign != nil
    }
}

// MARK: - CallsignEnrichedTimeline

/// Unified timeline showing QSOs enriched with recording data and standalone
/// tune-in recordings, sorted chronologically.
struct CallsignEnrichedTimeline: View {
    // MARK: Internal

    let items: [EnrichedTimelineItem]
    var onPlay: (WebSDRRecording, TimeInterval?) -> Void = { _, _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("History")
                    .font(.headline)
                Spacer()
                if items.count > displayLimit {
                    Button("See All (\(items.count))") {
                        showAll = true
                    }
                    .font(.caption)
                }
            }

            if items.isEmpty {
                ContentUnavailableView(
                    "No QSOs",
                    systemImage: "antenna.radiowaves.left.and.right",
                    description: Text("You haven't worked this station yet.")
                )
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(displayedItems) { item in
                        enrichedRow(item)

                        if item.id != displayedItems.last?.id {
                            Divider()
                        }
                    }
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: Private

    @State private var showAll = false

    private let displayLimit = 10

    private var displayedItems: [EnrichedTimelineItem] {
        showAll ? items : Array(items.prefix(displayLimit))
    }
}
