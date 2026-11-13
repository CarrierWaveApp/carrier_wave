import CarrierWaveData
import SwiftUI

// MARK: - CallsignQSOTimeline

/// Chronological QSO history list with inline recording clips, showing last 5 by default.
struct CallsignQSOTimeline: View {
    // MARK: Internal

    let qsos: [QSO]
    let clipsByQSOId: [UUID: QSORecordingClip]
    var serviceConfig = ServiceConfiguration()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("QSO History")
                    .font(.headline)
                Spacer()
                if qsos.count > displayLimit {
                    Button("See All (\(qsos.count))") {
                        showAll = true
                    }
                    .font(.caption)
                }
            }

            if qsos.isEmpty {
                ContentUnavailableView(
                    "No QSOs",
                    systemImage: "antenna.radiowaves.left.and.right",
                    description: Text("You haven't worked this station yet.")
                )
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(displayedQSOs) { qso in
                        NavigationLink {
                            QSODetailView(qso: qso, serviceConfig: serviceConfig)
                        } label: {
                            CallsignQSORow(
                                qso: qso,
                                clip: clipsByQSOId[qso.id]
                            )
                        }
                        .buttonStyle(.plain)

                        if qso.id != displayedQSOs.last?.id {
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

    private let displayLimit = 5

    private var displayedQSOs: [QSO] {
        if showAll {
            return qsos
        }
        return Array(qsos.prefix(displayLimit))
    }
}
