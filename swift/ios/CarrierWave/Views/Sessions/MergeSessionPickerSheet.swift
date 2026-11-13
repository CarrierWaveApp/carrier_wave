import CarrierWaveData
import SwiftData
import SwiftUI

// MARK: - MergeSessionPickerSheet

struct MergeSessionPickerSheet: View {
    // MARK: Internal

    let sourceSession: LoggingSession
    let onMerge: (LoggingSession) -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(
                        "QSOs from \"\(sourceSession.displayTitle)\" "
                            + "will be moved into the selected session."
                    )
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
                if candidates.isEmpty {
                    noSessionsView
                } else {
                    candidatesList
                }
            }
            .navigationTitle("Merge Into")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .task { await loadCandidates() }
            .confirmationDialog(
                "Merge Sessions",
                isPresented: $showConfirm,
                titleVisibility: .visible
            ) {
                Button("Merge") {
                    if let target = selectedTarget {
                        onMerge(target)
                    }
                }
                Button("Cancel", role: .cancel) {
                    selectedTarget = nil
                }
            } message: {
                if let target = selectedTarget {
                    Text(
                        "Move \(sourceSession.qsoCount) QSO(s) into "
                            + "\"\(target.displayTitle)\"? "
                            + "This cannot be undone."
                    )
                }
            }
        }
    }

    // MARK: Private

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var candidates: [LoggingSession] = []
    @State private var selectedTarget: LoggingSession?
    @State private var showConfirm = false

    private var noSessionsView: some View {
        Section {
            Text("No other sessions available to merge into.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
        }
    }

    private var candidatesList: some View {
        Section("Select Target Session") {
            ForEach(candidates) { session in
                Button { selectTarget(session) } label: {
                    candidateRow(session)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func candidateRow(
        _ session: LoggingSession
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: session.programsIcon)
                .font(.title3)
                .foregroundStyle(.blue)
                .frame(width: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(session.displayTitle)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(session.startedAt.formatted(
                        .dateTime.month(.abbreviated).day()
                    ))
                    Text("\(session.qsoCount) QSO\(session.qsoCount == 1 ? "" : "s")")
                    if let mode = session.mode.nilIfEmpty {
                        Text(mode)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    private func selectTarget(_ session: LoggingSession) {
        selectedTarget = session
        showConfirm = true
    }

    private func loadCandidates() async {
        var descriptor = FetchDescriptor<LoggingSession>(
            predicate: #Predicate<LoggingSession> {
                $0.statusRawValue == "completed"
            },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 100
        guard let fetched = try? modelContext.fetch(descriptor) else {
            return
        }
        candidates = fetched.filter { $0.id != sourceSession.id }
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
