import CarrierWaveData
import SwiftData
import SwiftUI

// MARK: - Bulk Delete & Selection

extension LogsListContentView {
    var bulkDeleteBar: some View {
        HStack {
            Button("Select All") {
                selectedQSOIDs = Set(snapshots.map(\.id))
            }
            Spacer()
            Button {
                groupingSummary = buildGroupingSummary()
            } label: {
                Label(
                    "Group \(selectedQSOIDs.count)",
                    systemImage: "rectangle.stack.badge.plus"
                )
            }
            Spacer()
            Button(role: .destructive) {
                showBulkDeleteConfirm = true
            } label: {
                Label(
                    "Delete \(selectedQSOIDs.count)",
                    systemImage: "trash"
                )
            }
        }
        .padding()
        .background(.ultraThinMaterial)
    }

    func softDeleteQSOs(_ toDelete: [QSO]) {
        guard !toDelete.isEmpty else {
            return
        }
        for qso in toDelete {
            qso.isHidden = true
            qso.cloudDirtyFlag = true
            qso.modifiedAt = Date()
            // Clear upload flags so hidden QSOs don't get re-flagged by reconciliation
            for presence in qso.servicePresence {
                presence.needsUpload = false
            }
        }
        do {
            try QSOWriteSink.commitUpsertBatch(toDelete, in: modelContext)
        } catch {
            // Roll back so the rows are NOT dropped from `snapshots` (which only happens
            // on success below) — a failed bulk-hide must not leave the list inconsistent.
            modelContext.rollback()
            CwStoreWriteLog.shared.record("Bulk hide failed: \(error.localizedDescription)")
            return
        }
        // Drop the rows only after the write committed; `refreshAfterNewQSO` re-pages
        // authoritatively on the notification below.
        let snapshotIDsToRemove = Set(toDelete.map { SwiftDataStoreImporter.uuid($0.id) })
        snapshots.removeAll { snapshotIDsToRemove.contains($0.id) }
        NotificationCenter.default.post(name: .didLogQSO, object: nil)
    }

    func bulkDeleteSelected() {
        softDeleteQSOs(LogbookIDBridge.fetchQSOs(ids: selectedQSOIDs, in: modelContext))
        selectedQSOIDs.removeAll()
        isSelectMode = false
    }
}
