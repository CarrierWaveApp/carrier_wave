import CarrierWaveData
import SwiftUI

// MARK: - MacroImportSheet

/// Sheet shown when the user opens a `.cwmacro` file from Finder, a
/// Universal Link, or the `cwmacro://` scheme. Drives
/// `MacroImportCoordinator` for validation and routes the resulting
/// outcome — install, review, or rejection. Raw-bytes imports require
/// an extra confirmation gate before the install completes.
struct MacroImportSheet: View {
    // MARK: Lifecycle

    init(
        documentData: Data,
        provenance: MacroImportProvenance,
        onInstall: @escaping (RadioMacroSpec) -> Void
    ) {
        self.documentData = documentData
        self.provenance = provenance
        self.onInstall = onInstall
    }

    // MARK: Internal

    let documentData: Data
    let provenance: MacroImportProvenance
    let onInstall: (RadioMacroSpec) -> Void

    var body: some View {
        NavigationStack {
            Form {
                provenanceSection
                if let outcome {
                    body(for: outcome)
                } else {
                    Section {
                        ProgressView("Validating…")
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Install Macro")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .task {
                outcome = await coordinator.evaluate(
                    documentData: documentData,
                    provenance: provenance
                )
            }
            .alert("Trust raw bytes?", isPresented: $rawBytesAlert) {
                Button("Install anyway", role: .destructive) {
                    performInstall()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This macro contains raw protocol bytes the catalog " +
                    "can't introspect. Only install if you trust the source.")
            }
            .sheet(isPresented: $showStepPreview) {
                if case let .readyToInstall(spec, _, _) = outcome {
                    NavigationStack {
                        MacroStepPreviewView(spec: spec)
                    }
                    .frame(minWidth: 480, minHeight: 440)
                }
            }
        }
        .frame(minWidth: 520, minHeight: 540)
    }

    // MARK: Private

    @Environment(\.dismiss) private var dismiss
    @State private var coordinator = MacroImportCoordinator()
    @State private var outcome: MacroImportOutcome?
    @State private var rawBytesAlert = false
    @State private var showStepPreview = false

    private var provenanceSection: some View {
        Section("Source") {
            HStack(spacing: 8) {
                Image(systemName: provenance.iconName)
                    .foregroundStyle(provenance.iconColor)
                Text(provenance.shortLabel)
                    .font(.body)
            }
            if let detail = provenance.detail {
                Text(detail)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
        }
        .listRowBackground(provenance.isRegistry ? Color.clear : Color.red.opacity(0.08))
    }

    @ViewBuilder
    private func body(for outcome: MacroImportOutcome) -> some View {
        switch outcome {
        case let .readyToInstall(spec, _, requiresRawBytesConfirmation):
            specSection(spec)
            stepsPreviewSection(stepCount: spec.steps.count)
            actionsSection(spec: spec, requiresRawBytes: requiresRawBytesConfirmation)
        case let .rejected(reason):
            Section {
                MacroSafetyConfirmationBanner(reason: reason, tone: .error)
            }
        }
    }

    private func specSection(_ spec: RadioMacroSpec) -> some View {
        Section {
            HStack(spacing: 12) {
                Image(systemName: spec.icon ?? "wand.and.stars")
                    .font(.title2)
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 4) {
                    Text(spec.name)
                        .font(.headline)
                    if let author = spec.author, !author.isEmpty {
                        Text("Claims to be: \(author)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }
            if let description = spec.description, !description.isEmpty {
                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            MacroCapabilityChipsFull(capabilities: spec.capabilities)
                .padding(.vertical, 2)
        }
    }

    private func stepsPreviewSection(stepCount: Int) -> some View {
        Section {
            Button {
                showStepPreview = true
            } label: {
                HStack {
                    Label("Review \(stepCount) step\(stepCount == 1 ? "" : "s")", systemImage: "list.bullet")
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.plain)
        }
    }

    private func actionsSection(spec _: RadioMacroSpec, requiresRawBytes: Bool) -> some View {
        Section {
            Button {
                if requiresRawBytes {
                    rawBytesAlert = true
                } else {
                    performInstall()
                }
            } label: {
                HStack {
                    Image(systemName: "tray.and.arrow.down")
                    Text("Install macro")
                    Spacer()
                }
                .font(.body.weight(.semibold))
            }
        } footer: {
            if requiresRawBytes {
                Text("Installation requires explicit confirmation because " +
                    "the macro sends raw protocol bytes.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    private func performInstall() {
        guard case let .readyToInstall(spec, _, _) = outcome else {
            return
        }
        onInstall(spec)
        dismiss()
    }
}

// MARK: - MacroImportProvenance UI helpers

extension MacroImportProvenance {
    var shortLabel: String {
        switch self {
        case .registry: "Carrier Wave Registry"
        case .airDrop: "AirDrop"
        case .files: "Finder"
        case let .web(host): "From \(host)"
        case let .other(label): label
        }
    }

    var detail: String? {
        switch self {
        case let .registry(slug): "slug: \(slug)"
        case .airDrop,
             .files: nil
        case let .web(host): host
        case .other: nil
        }
    }

    var iconName: String {
        switch self {
        case .registry: "checkmark.seal.fill"
        case .airDrop: "rectangle.portrait.and.arrow.right.fill"
        case .files: "folder.fill"
        case .web: "globe"
        case .other: "questionmark.circle"
        }
    }

    var iconColor: Color {
        switch self {
        case .registry: .green
        case .airDrop,
             .files: .blue
        case .web: .orange
        case .other: .red
        }
    }

    var isRegistry: Bool {
        if case .registry = self {
            return true
        }
        return false
    }
}

// MARK: - MacroStepPreviewView

struct MacroStepPreviewView: View {
    // MARK: Internal

    let spec: RadioMacroSpec

    var body: some View {
        List {
            Section {
                ForEach(Array(spec.steps.enumerated()), id: \.offset) { index, step in
                    MacroStepSummaryRow(index: index, step: step)
                }
            } header: {
                Text("\(spec.steps.count) steps")
            }
        }
        .navigationTitle("Steps")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Done") { dismiss() }
            }
        }
    }

    // MARK: Private

    @Environment(\.dismiss) private var dismiss
}
