import CarrierWaveData
import SwiftData
import SwiftUI

// MARK: - ExperimentsView

/// Central hub listing all experimental features with maturity badges
/// and opt-in toggles for hidden features.
struct ExperimentsView: View {
    // MARK: Internal

    var body: some View {
        List {
            SettingsHeroHeader(
                icon: "testtube.2",
                tint: .purple,
                title: "Experiments",
                subtitle: "Try features that are still in development."
            )
            enabledSection
            if !hiddenFeatures.isEmpty {
                hiddenSection
            }
            if ExperimentalFeature.isEnabled(.radioControl) {
                radioControlToolsSection
            }
            if ExperimentalFeature.isEnabled(.queryRunner)
                || ExperimentalFeature.isEnabled(.bandScope)
            {
                toolsSection
            }
            dataMigrationSection
        }
        .id(refreshID)
        .navigationTitle("Experiments")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: Private

    @Environment(\.modelContext) private var modelContext

    @State private var refreshID = UUID()
    @State private var parityStatus: String?
    @State private var reconcileStatus: String?

    @AppStorage(MacroTelemetryReporter.optInKey) private var macrosTelemetryOptIn = false
    @AppStorage(CwStoreQSOMode.appStorageKey) private var qsoMode = CwStoreQSOMode.on
    @AppStorage(CwStoreSyncMode.appStorageKey) private var syncMode = CwStoreSyncMode.off

    private var visibleFeatures: [ExperimentalFeature] {
        ExperimentalFeature.allCases.filter { !$0.isHiddenByDefault }
    }

    private var hiddenFeatures: [ExperimentalFeature] {
        ExperimentalFeature.allCases.filter(\.isHiddenByDefault)
    }

    private var enabledSection: some View {
        Section {
            ForEach(visibleFeatures) { feature in
                if feature.canBeDisabled {
                    Toggle(isOn: Binding(
                        get: { ExperimentalFeature.isEnabled(feature) },
                        set: { newValue in
                            ExperimentalFeature.setEnabled(feature, enabled: newValue)
                            refreshID = UUID()
                            NotificationCenter.default.post(
                                name: .tabConfigurationChanged, object: nil
                            )
                        }
                    )) {
                        ExperimentFeatureRow(feature: feature)
                    }
                } else {
                    ExperimentFeatureRow(feature: feature)
                }
            }
        } header: {
            Text("Active Experiments")
        } footer: {
            Text(
                "These features are under active development. "
                    + "They may change, have rough edges, or be removed."
            )
        }
    }

    private var radioControlToolsSection: some View {
        Section {
            NavigationLink(destination: MacrosLibraryView()) {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text("Macros")
                            ExperimentalBadge(feature: .radioControl)
                        }
                        Text("Author and run multi-step radio command sequences.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "wand.and.stars")
                        .foregroundStyle(.secondary)
                }
            }
            Toggle(isOn: $macrosTelemetryOptIn) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Share Macro Run Stats")
                    Text(
                        "When on, sends success/failure counts for registry macros so authors "
                            + "can fix flaky steps. No callsigns, frequencies, or step contents."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Radio CAT Control")
        }
    }

    private var toolsSection: some View {
        Section {
            if ExperimentalFeature.isEnabled(.queryRunner) {
                NavigationLink(destination: SpotQueryEditorView()) {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Open Spot SQL Editor")
                            Text("Write, run, and save SQL against live spots and your QSO log.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "doc.text.magnifyingglass")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            if ExperimentalFeature.isEnabled(.bandScope) {
                NavigationLink(destination: BandScopeContainerView()) {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text("Open Band Scope")
                                ExperimentalBadge(feature: .bandScope)
                            }
                            Text("Scope + Heard spot browser with goal profiles and SQL-driven filtering.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "chart.xyaxis.line")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } header: {
            Text("Experiment Tools")
        }
    }

    private var dataMigrationSection: some View {
        Section {
            CwStoreMigrationRow()
            if ExperimentalFeature.isEnabled(.rustStoreQSO) {
                Picker("QSO Rust Store", selection: $qsoMode) {
                    ForEach(CwStoreQSOMode.allCases, id: \.self) { mode in
                        Text(mode.displayLabel).tag(mode)
                    }
                }
                Picker("Sync Engine", selection: $syncMode) {
                    ForEach(CwStoreSyncMode.allCases, id: \.self) { mode in
                        Text(mode.displayLabel).tag(mode)
                    }
                }
                Button {
                    runQSOParityCheck()
                } label: {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Run QSO Parity Check")
                                .font(.body)
                            Text(parityStatus ?? "Compare SwiftData and Rust store QSO counts.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "checkmark.circle")
                            .foregroundStyle(.secondary)
                    }
                }
                Button {
                    runReconcile()
                } label: {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Reconcile cw-store")
                                .font(.body)
                            Text(reconcileStatus ??
                                "Prune cw-store rows SwiftData no longer has (heals mirror-blind deletes).")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .foregroundStyle(.secondary)
                    }
                }
                if !CwStoreWriteLog.shared.entries.isEmpty {
                    DisclosureGroup("cw-store write log") {
                        ForEach(
                            Array(CwStoreWriteLog.shared.entries.suffix(10).enumerated()),
                            id: \.offset
                        ) { _, entry in
                            Text(entry)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        } header: {
            Text("Data Migration")
        } footer: {
            Text(
                "Seeds the experimental encrypted Rust store from your current log. "
                    + "Safe to run: your existing data is never modified. Sync Engine "
                    + "selects which engine drives cross-device sync — leave on iCloud "
                    + "until two-device Carrier Wave Server sync is verified."
            )
        }
    }

    private var hiddenSection: some View {
        Section {
            ForEach(hiddenFeatures) { feature in
                let isEnabled = ExperimentalFeature.isEnabled(feature)
                let canToggle = feature.canBeDisabled || !isEnabled
                Toggle(isOn: Binding(
                    get: { isEnabled },
                    set: { newValue in
                        ExperimentalFeature.setEnabled(feature, enabled: newValue)
                        refreshID = UUID()
                        NotificationCenter.default.post(
                            name: .tabConfigurationChanged, object: nil
                        )
                    }
                )) {
                    ExperimentFeatureRow(feature: feature)
                }
                .disabled(!canToggle)
            }
        } header: {
            Text("Hidden Experiments")
        } footer: {
            Text("Enable these to try features that are still very early.")
        }
    }

    private func runQSOParityCheck() {
        parityStatus = "Checking…"
        let container = modelContext.container
        Task.detached {
            let message: String
            do {
                let store = try await CwStoreProvider.shared.store()
                // SwiftDataQSOReadSource.count() uses fetchCount — unbounded by design
                // for a total-count parity invariant check (no rows are loaded into memory).
                let swiftSource = await MainActor.run {
                    SwiftDataQSOReadSource(context: ModelContext(container))
                }
                let count = try await swiftSource.count()
                let rust = try Int(store.qsoCount())
                let result = QSOParityProbe().compareCounts(swiftData: count, rust: rust)
                message = result.matches
                    ? "QSO parity OK: \(count) rows."
                    : "QSO parity MISMATCH: SwiftData \(result.swiftData) ≠ Rust \(result.rust)."
            } catch {
                message = "Parity check failed: \(error.localizedDescription)"
            }
            await MainActor.run { parityStatus = message }
        }
    }
}

// MARK: - CwStoreMigrationRow

/// Runs the one-time SwiftData → cw-store seed import off the main actor and
/// surfaces the outcome inline. The import is idempotent and never mutates the
/// SwiftData source (see `CwStoreImportCoordinator`).
private struct CwStoreMigrationRow: View {
    // MARK: Internal

    var body: some View {
        Button {
            run()
        } label: {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Migrate to Rust Store")
                        .font(.body)
                    Text(status ?? "Seed the encrypted cw-store from your SwiftData log.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } icon: {
                if running {
                    ProgressView()
                } else {
                    Image(systemName: "internaldrive")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .disabled(running)
    }

    // MARK: Private

    @Environment(\.modelContext) private var modelContext
    @State private var running = false
    @State private var status: String?

    private func run() {
        running = true
        status = "Importing…"
        let container = modelContext.container
        let version = Bundle.main
            .object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
        Task.detached {
            let message: String
            do {
                let coordinator = try CwStoreImportCoordinator.appGroup(version: version)
                switch try await coordinator.runIfNeeded(from: container) {
                case .alreadyComplete:
                    message = "Already migrated for this version."
                case let .completed(report):
                    message = "Imported \(report.total) rows across \(report.counts.count) tables."
                case let .verificationFailed(tables):
                    let detail = tables
                        .map { "\($0.name) (src \($0.sourceCount) ≠ stored \($0.storedCount))" }
                        .joined(separator: ", ")
                    message = "Verification failed: \(detail)"
                }
            } catch {
                message = "Failed: \(error.localizedDescription)"
            }
            await MainActor.run {
                status = message
                running = false
            }
        }
    }
}

// MARK: - CwStoreQSOMode + UI

private extension CwStoreQSOMode {
    var displayLabel: String {
        switch self {
        case .off: "Off"
        case .shadow: "Shadow"
        case .on: "On"
        }
    }
}

// MARK: - CwStoreSyncMode + UI

private extension CwStoreSyncMode {
    var displayLabel: String {
        switch self {
        case .off: "iCloud (CKSyncEngine)"
        case .serverSync: "Carrier Wave Server"
        }
    }
}

// MARK: - ExperimentFeatureRow

private struct ExperimentFeatureRow: View {
    let feature: ExperimentalFeature

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(feature.title)
                        .font(.body)
                    ExperimentalBadge(feature: feature)
                }
                Text(feature.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        } icon: {
            Image(systemName: feature.iconName)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Reconcile

extension ExperimentsView {
    func runReconcile() {
        reconcileStatus = "Reconciling\u{2026}"
        let container = modelContext.container
        Task.detached {
            let message: String
            do {
                // Settle in-flight follower writes before snapshotting cw-store.
                let mirror = await MainActor.run { CwStoreMirrorRegistry.current }
                await mirror?.drain()
                let store = try await CwStoreProvider.shared.store()
                let context = ModelContext(container)
                let report = try CwStoreReconciler(store: store).reconcileAll(in: context)
                message = report.total == 0
                    ? "Reconcile OK: no orphans."
                    : "Reconcile pruned \(report.total) orphan row(s)."
            } catch {
                message = "Reconcile failed: \(error.localizedDescription)"
            }
            await MainActor.run { reconcileStatus = message }
        }
    }
}
