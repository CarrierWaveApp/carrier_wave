import CarrierWaveData
import SwiftData
import SwiftUI

// MARK: - AllHiddenQSOsView

/// View showing all hidden (deleted) QSOs across the app with option to restore
struct AllHiddenQSOsView: View {
    // MARK: Internal

    var body: some View {
        Group {
            if hiddenQSOs.isEmpty, !isLoading {
                ContentUnavailableView(
                    "No Hidden QSOs",
                    systemImage: "checkmark.circle",
                    description: Text("All QSOs are visible")
                )
            } else {
                hiddenQSOsList
            }
        }
        .navigationTitle("Hidden QSOs")
        .task {
            await loadHiddenQSOs()
        }
        .alert("Restore All?", isPresented: $showRestoreAllConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Restore All") {
                Task { await restoreAllQSOs() }
            }
        } message: {
            Text(
                "This will restore \(totalCount) hidden QSO(s) "
                    + "and include them in sync."
            )
        }
        .alert(
            "Permanently Delete All?",
            isPresented: $showDeleteAllConfirmation
        ) {
            Button("Cancel", role: .cancel) {}
            Button("Delete All", role: .destructive) {
                Task { await permanentlyDeleteAllQSOs() }
            }
        } message: {
            Text(
                "This will permanently delete \(totalCount) "
                    + "hidden QSO(s). This cannot be undone."
            )
        }
    }

    // MARK: Private

    private static let batchSize = 100

    @Environment(\.modelContext) private var modelContext

    @State private var hiddenQSOs: [QSO] = []
    @State private var totalCount = 0
    @State private var isLoading = false
    @State private var isLoadingMore = false
    @State private var showRestoreAllConfirmation = false
    @State private var showDeleteAllConfirmation = false

    private var hasMoreQSOs: Bool {
        hiddenQSOs.count < totalCount
    }

    private var hiddenQSOsList: some View {
        List {
            Section {
                ForEach(hiddenQSOs) { qso in
                    AllHiddenQSORow(qso: qso) {
                        restoreQSO(qso)
                    }
                }

                if hasMoreQSOs {
                    loadMoreButton
                }
            } header: {
                Text(
                    "\(totalCount) hidden "
                        + "QSO\(totalCount == 1 ? "" : "s")"
                )
            } footer: {
                Text(
                    "Hidden QSOs are excluded from sync and "
                        + "statistics. Restore them to include "
                        + "them again."
                )
            }

            if !hiddenQSOs.isEmpty {
                Section {
                    Button("Restore All") {
                        showRestoreAllConfirmation = true
                    }

                    Button(
                        "Permanently Delete All",
                        role: .destructive
                    ) {
                        showDeleteAllConfirmation = true
                    }
                }
            }
        }
    }

    private var loadMoreButton: some View {
        HStack {
            Spacer()
            Button {
                Task { await loadMoreHiddenQSOs() }
            } label: {
                if isLoadingMore {
                    ProgressView()
                        .padding(.vertical, 8)
                } else {
                    Text(
                        "Load More "
                            + "(\(totalCount - hiddenQSOs.count) "
                            + "remaining)"
                    )
                    .foregroundStyle(.blue)
                }
            }
            .disabled(isLoadingMore)
            Spacer()
        }
    }

    private func loadHiddenQSOs() async {
        isLoading = true
        defer { isLoading = false }

        totalCount = (try? modelContext.boundedCount(
            QSO.self,
            predicate: #Predicate { $0.isHidden }
        )) ?? 0

        let descriptor = BoundedDescriptor<QSO>(
            predicate: #Predicate { $0.isHidden },
            sortBy: [
                SortDescriptor(\QSO.timestamp, order: .reverse),
            ],
            limit: Self.batchSize
        )

        if let fetched = try? modelContext.boundedFetch(descriptor) {
            hiddenQSOs = fetched
        }
    }

    private func loadMoreHiddenQSOs() async {
        guard !isLoadingMore, hasMoreQSOs else {
            return
        }
        isLoadingMore = true
        defer { isLoadingMore = false }

        let descriptor = BoundedDescriptor<QSO>(
            predicate: #Predicate { $0.isHidden },
            sortBy: [
                SortDescriptor(\QSO.timestamp, order: .reverse),
            ],
            limit: Self.batchSize,
            offset: hiddenQSOs.count
        )

        if let fetched = try? modelContext.boundedFetch(descriptor) {
            hiddenQSOs.append(contentsOf: fetched)
        }
    }

    private func restoreQSO(_ qso: QSO) {
        do {
            if let sink = QSOWriteSinkRegistry.current {
                try sink.setHidden(qso, hidden: false, in: modelContext)
            } else {
                qso.isHidden = false
                try modelContext.save()
            }
        } catch {
            modelContext.rollback()
            CwStoreWriteLog.shared.record("Restore failed: \(error.localizedDescription)")
            return
        }
        Task { await loadHiddenQSOs() }
    }

    private func restoreAllQSOs() async {
        // Each batch is committed before the next fetch, so restored rows leave the
        // `isHidden` predicate — fetch from offset 0 every iteration (no offset walk).
        while true {
            let descriptor = BoundedDescriptor<QSO>(
                predicate: #Predicate { $0.isHidden },
                limit: Self.batchSize
            )

            guard let batch = try? modelContext.boundedFetch(descriptor),
                  !batch.isEmpty
            else {
                break
            }

            for qso in batch {
                qso.isHidden = false
            }
            do {
                try QSOWriteSink.commitUpsertBatch(batch, in: modelContext)
            } catch {
                modelContext.rollback()
                CwStoreWriteLog.shared.record("Restore all failed: \(error.localizedDescription)")
                break
            }
            await Task.yield()
        }
        await loadHiddenQSOs()
    }

    private func permanentlyDeleteAllQSOs() async {
        while true {
            let descriptor = BoundedDescriptor<QSO>(
                predicate: #Predicate { $0.isHidden },
                limit: Self.batchSize
            )

            guard let batch = try? modelContext.boundedFetch(descriptor),
                  !batch.isEmpty
            else {
                break
            }

            do {
                try QSOWriteSink.commitDeleteBatch(batch, in: modelContext)
            } catch {
                modelContext.rollback()
                CwStoreWriteLog.shared.record("Delete hidden failed: \(error.localizedDescription)")
                break
            }
            await Task.yield()
        }
        await loadHiddenQSOs()
    }
}

// MARK: - AllHiddenQSORow

/// A row displaying a hidden QSO with restore button
struct AllHiddenQSORow: View {
    // MARK: Internal

    let qso: QSO
    let onRestore: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(qso.callsign)
                    .font(.headline.monospaced())

                HStack(spacing: 8) {
                    Text(
                        qso.timestamp,
                        format: .dateTime.month().day()
                            .hour().minute()
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    Text(qso.band)
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.blue.opacity(0.2))
                        .clipShape(Capsule())

                    Text(qso.mode)
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.blue.opacity(0.2))
                        .clipShape(Capsule())
                }

                if let park = qso.parkReference {
                    Text(park)
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }

            Spacer()

            Button {
                onRestore()
            } label: {
                Label(
                    "Restore",
                    systemImage: "arrow.uturn.backward"
                )
                .font(.subheadline)
            }
            .buttonStyle(.bordered)
        }
        .padding(.vertical, 4)
    }

    // MARK: Private

    /// Shared date formatter for performance
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, HH:mm"
        return formatter
    }()
}
