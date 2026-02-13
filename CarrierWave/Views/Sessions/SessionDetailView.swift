import SwiftData
import SwiftUI

/// Simple detail view for sessions without recordings.
/// Shows session metadata and QSO list.
struct SessionDetailView: View {
    // MARK: Internal

    let session: LoggingSession

    var body: some View {
        List {
            infoSection
            qsoSection
        }
        .navigationTitle(session.displayTitle)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadQSOs()
        }
    }

    // MARK: Private

    @Environment(\.modelContext) private var modelContext
    @State private var qsos: [QSO] = []

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

            if let ref = session.activationReference {
                LabeledContent("Reference", value: ref)
            }

            if let grid = session.myGrid {
                LabeledContent("Grid", value: grid)
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
}
