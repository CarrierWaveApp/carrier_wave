// Needs Management View
//
// Shows auto-detected and custom needs with actions to dismiss, pin, or delete.
// Includes HamAlert export entry point (Phase 3).

import SwiftData
import SwiftUI

// MARK: - NeedsManagementView

struct NeedsManagementView: View {
    // MARK: Internal

    let snapshot: NeedsSnapshot

    var body: some View {
        List {
            autoDetectedSection
            customNeedsSection
            exportSection
        }
        .navigationTitle("My Needs")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingAddSheet) {
            AddCustomNeedSheet()
        }
        .sheet(isPresented: $showingExportSheet) {
            HamAlertExportSheet(snapshot: snapshot)
        }
    }

    // MARK: Private

    @Environment(\.modelContext) private var modelContext

    @Query(
        filter: #Predicate<CustomNeed> { $0.isActive },
        sort: \CustomNeed.createdAt, order: .reverse
    )
    private var customNeeds: [CustomNeed]

    @State private var showingAddSheet = false
    @State private var showingExportSheet = false

    // MARK: - Auto-Detected Section

    private var autoDetectedSection: some View {
        Section("Auto-Detected") {
            if let tierName = snapshot.dxcc.nextTier.name {
                let worked = snapshot.dxcc.entitiesWorkedCount
                let target = snapshot.dxcc.nextTier.threshold
                let gridNote = snapshot.dxcc.gridSquare
                    .map { " from \($0)" } ?? ""
                needRow(
                    icon: "globe.americas",
                    title: "DXCC",
                    detail: "\(worked)/\(target) — "
                        + "\(target - worked) to \(tierName)\(gridNote)"
                )
            }

            if !snapshot.was.isComplete {
                let missing = snapshot.was.statesMissing.sorted()
                    .prefix(5).joined(separator: ", ")
                let suffix = snapshot.was.statesMissing.count > 5
                    ? " +\(snapshot.was.statesMissing.count - 5) more"
                    : ""
                needRow(
                    icon: "map",
                    title: "WAS",
                    detail: "\(missing)\(suffix)"
                )
            }

            if snapshot.potaHunter.parksRemaining > 0 {
                let tier = snapshot.potaHunter.nextTierName ?? "next tier"
                needRow(
                    icon: "tree",
                    title: "POTA Hunter",
                    detail: "\(snapshot.potaHunter.parksRemaining) parks to \(tier)"
                )
            }

            if snapshot.wwffHunter.referencesRemaining > 0 {
                let tier = snapshot.wwffHunter.nextTierName ?? "next tier"
                needRow(
                    icon: "leaf",
                    title: "WWFF Hunter",
                    detail: "\(snapshot.wwffHunter.referencesRemaining) refs to \(tier)"
                )
            }
        }
    }

    // MARK: - Custom Needs Section

    private var customNeedsSection: some View {
        Section {
            if customNeeds.isEmpty {
                Text("No custom needs")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            ForEach(customNeeds, id: \.id) { need in
                customNeedRow(need)
            }
            .onDelete(perform: deleteCustomNeeds)

            Button {
                showingAddSheet = true
            } label: {
                Label("Add Custom Need", systemImage: "plus")
            }
        } header: {
            Text("Custom")
        }
    }

    // MARK: - Export Section

    private var exportSection: some View {
        Section {
            Button {
                showingExportSheet = true
            } label: {
                Label("Export to HamAlert", systemImage: "square.and.arrow.up")
            }
        } footer: {
            Text("Generate trigger configurations for HamAlert based on your current needs.")
        }
    }

    // MARK: - Row Views

    private func needRow(
        icon: String,
        title: String,
        detail: String
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundStyle(.blue)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func customNeedRow(_ need: CustomNeed) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "star.fill")
                .font(.caption)
                .foregroundStyle(.yellow)
            VStack(alignment: .leading, spacing: 2) {
                Text(need.pattern)
                    .font(.subheadline.weight(.medium).monospaced())
                Text(need.label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let fulfilled = need.fulfilledAt {
                let formatter = RelativeDateTimeFormatter()
                Text("Fulfilled \(formatter.localizedString(for: fulfilled, relativeTo: Date()))")
                    .font(.caption2)
                    .foregroundStyle(.green)
            }
        }
    }

    private func deleteCustomNeeds(at offsets: IndexSet) {
        // Resolve to objects before mutating. The @Query array can shrink
        // out from under us (cloud sync / another window), and index-based
        // deletion against a stale IndexSet is an out-of-bounds crash.
        let toDelete = offsets.compactMap { index in
            customNeeds.indices.contains(index) ? customNeeds[index] : nil
        }
        for need in toDelete {
            modelContext.delete(need)
        }
    }
}
