import CarrierWaveData
import SwiftData
import SwiftUI

// MARK: - PropagationCheckRootView

/// Entry point for "Propagation Check" — lists prior checks and offers a "+"
/// to start a new one. Multi-select drives Compare.
struct PropagationCheckRootView: View {
    // MARK: Internal

    var body: some View {
        Group {
            if checks.isEmpty {
                emptyState
            } else {
                listContent
            }
        }
        .environment(\.editMode, $editMode)
        .navigationTitle("Propagation Check")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if !checks.isEmpty {
                    EditButton()
                }
                Button {
                    presentStartSheet = true
                } label: {
                    Label("New Check", systemImage: "plus")
                }
            }
            ToolbarItem(placement: .bottomBar) {
                if !selectedIDs.isEmpty {
                    HStack {
                        Spacer()
                        Button {
                            presentCompare = true
                        } label: {
                            Label("Compare \(selectedIDs.count)", systemImage: "rectangle.on.rectangle")
                        }
                        .disabled(selectedIDs.count < 2 || selectedIDs.count > 2)
                    }
                }
            }
        }
        .sheet(isPresented: $presentStartSheet) {
            PropagationCheckStartSheet { config in
                lastUsedConfig = config
                let session = PropagationCheckSession()
                session.start(config: config)
                liveSession = session
            }
        }
        .fullScreenCover(item: $liveSession) { session in
            PropagationCheckLiveView(session: session) { snapshot in
                liveSession = nil
                if let cfg = lastUsedConfig {
                    presentLabelPrompt = PropagationCheckLabelPrompt(
                        snapshot: snapshot,
                        startedAt: cfg.startedAt,
                        bands: cfg.bands
                    )
                }
            }
        }
        .sheet(item: $presentLabelPrompt) { prompt in
            PropagationCheckLabelSheet(prompt: prompt) { label in
                if !label.isEmpty {
                    persist(snapshot: prompt.snapshot, label: label)
                }
                presentLabelPrompt = nil
            }
        }
        .sheet(isPresented: $presentCompare) {
            if let pair = selectedPair {
                PropagationCompareView(checks: pair)
            }
        }
    }

    // MARK: Private

    @Environment(\.modelContext) private var modelContext

    @Query(sort: \PropagationCheck.startedAt, order: .reverse)
    private var checks: [PropagationCheck]

    @State private var presentStartSheet = false
    @State private var liveSession: PropagationCheckSession?
    @State private var presentLabelPrompt: PropagationCheckLabelPrompt?
    @State private var selectedIDs: Set<UUID> = []
    @State private var presentCompare = false
    @State private var editMode: EditMode = .inactive

    @State private var lastUsedConfig: PropagationCheckConfig?

    private var selectedPair: [PropagationCheck]? {
        let pair = checks.filter { selectedIDs.contains($0.id) }
        return pair.count == 2 ? pair : nil
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Propagation Checks", systemImage: "dot.radiowaves.up.forward")
        } description: {
            Text("Run a check while you CQ, then save the results to compare antennas, bands, or time of day.")
        } actions: {
            Button {
                presentStartSheet = true
            } label: {
                Label("Start a Check", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
        }
    }

    @ViewBuilder
    private var listContent: some View {
        if editMode.isEditing {
            editingList
        } else {
            navigatingList
        }
    }

    private var navigatingList: some View {
        List {
            ForEach(checks) { check in
                NavigationLink {
                    PropagationCheckResultsView(check: check)
                } label: {
                    PropagationCheckRow(check: check)
                }
            }
            .onDelete(perform: deleteChecks)
        }
        .listStyle(.insetGrouped)
    }

    private var editingList: some View {
        List(selection: $selectedIDs) {
            ForEach(checks) { check in
                PropagationCheckRow(check: check)
                    .tag(check.id)
            }
            .onDelete(perform: deleteChecks)
        }
        .listStyle(.insetGrouped)
        .onChange(of: editMode) { _, newValue in
            if newValue == .inactive {
                selectedIDs.removeAll()
            }
        }
    }

    private func deleteChecks(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(checks[index])
        }
        try? modelContext.save()
    }

    private func persist(snapshot: PropagationCheckSession.Snapshot, label: String) {
        guard let lastConfig = lastUsedConfig else {
            return
        }
        // Headline totals + connectivity gaps + solar all come pre-computed off
        // the Rust `PropagationApi.results()` on the snapshot.
        let blob = PropagationCheckBlob(spots: snapshot.spots, connectivityGaps: snapshot.gaps)
        let check = PropagationCheck(
            label: label,
            startedAt: lastConfig.startedAt,
            endedAt: snapshot.endedAt,
            callsignUsed: lastConfig.callsign,
            userGridUsed: lastConfig.userGrid,
            bandsRequested: lastConfig.bands,
            transmitMode: lastConfig.transmitMode.rawValue,
            stopReason: snapshot.stopReason.rawValue,
            totalSpots: snapshot.totalSpots,
            uniqueSkimmers: snapshot.uniqueSkimmers,
            bandsWithActivity: snapshot.bandsWithActivity,
            maxDistanceKm: snapshot.maxDistanceKm,
            peakSNRdB: snapshot.peakSNRdB,
            spotsBlob: blob.encode(),
            spotsBlobSchemaVersion: PropagationCheckBlob.currentSchemaVersion,
            solarKIndex: snapshot.solarKIndex,
            solarAIndex: snapshot.solarAIndex,
            solarFlux: snapshot.solarFlux,
            solarSunspots: snapshot.solarSunspots,
            solarPropagationRating: snapshot.solarPropagationRating,
            solarBandConditions: snapshot.solarBandConditions,
            solarTimestamp: snapshot.solarTimestamp
        )
        modelContext.insert(check)
        try? modelContext.save()
        lastUsedConfig = nil
    }
}

// MARK: - PropagationCheckRow

private struct PropagationCheckRow: View {
    let check: PropagationCheck

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(check.label.isEmpty ? "Untitled Check" : check.label)
                    .font(.headline)
                Spacer()
                Text(check.startedAt, format: .dateTime.month().day().hour().minute())
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 12) {
                Label("\(check.totalSpots)", systemImage: "antenna.radiowaves.left.and.right")
                Label("\(check.uniqueSkimmers)", systemImage: "ear")
                if !check.bandsWithActivity.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(check.bandsWithActivity.sorted(), id: \.self) { band in
                            Text(band)
                                .font(.caption2.bold())
                                .padding(.horizontal, 4)
                                .padding(.vertical, 2)
                                .background(BandColors.color(for: band).opacity(0.18), in: Capsule())
                                .foregroundStyle(BandColors.color(for: band))
                        }
                    }
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - PropagationCheckSession + Identifiable

extension PropagationCheckSession: Identifiable {
    var id: ObjectIdentifier {
        ObjectIdentifier(self)
    }
}
