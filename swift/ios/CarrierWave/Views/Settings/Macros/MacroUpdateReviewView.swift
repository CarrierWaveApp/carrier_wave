import CarrierWaveData
import SwiftData
import SwiftUI

// MARK: - MacroUpdateReviewView

/// Diff-and-apply sheet for a pending registry update. Fetches the
/// remote document on appear, renders the field-level diff, and exposes
/// three actions: Update, Keep my version, View on web.
///
/// Raw-bytes macros invalidate the existing spec-hash acceptance before
/// the new steps land — guaranteeing the safety gate re-prompts before
/// the new bytes go on the air.
struct MacroUpdateReviewView: View {
    // MARK: Internal

    let macro: RadioMacro

    var body: some View {
        List {
            headerSection
            if let document {
                if changes.isEmpty {
                    Section {
                        Text("No visible changes — the registry bumped a metadata-only field.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    ForEach(changes) { change in
                        Section(change.field) {
                            DiffRow(change: change)
                        }
                    }
                }
                actionsSection(document: document)
            } else if let loadError {
                errorSection(loadError)
            } else {
                ProgressView("Loading update…")
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
            }
        }
        .navigationTitle("Update Macro")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Done") { dismiss() }
            }
        }
        .task { await load() }
        .alert("Update failed", isPresented: $showFailure) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(applyError ?? "Unknown error")
        }
    }

    // MARK: Private

    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @State private var document: RegistryMacroDocument?
    @State private var changes: [RadioMacroSpecDiff.Change] = []
    @State private var loadError: String?
    @State private var applyError: String?
    @State private var showFailure = false
    @State private var applying = false

    private var headerSection: some View {
        Section {
            HStack(spacing: 12) {
                Image(systemName: macro.icon ?? "wand.and.stars")
                    .font(.system(size: 22))
                    .foregroundStyle(.tint)
                    .frame(width: 40, height: 40)
                    .background(Color.accentColor.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 2) {
                    Text(macro.name)
                        .font(.headline)
                    if let slug = macro.registry?.slug {
                        Text(slug)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if let local = macro.registry?.registryVersion, let remote = document?.version {
                    VStack(alignment: .trailing, spacing: 0) {
                        Text("v\(local)")
                            .strikethrough()
                            .foregroundStyle(.secondary)
                        Text("v\(remote)")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.tint)
                    }
                    .font(.caption.monospacedDigit())
                }
            }
        }
    }

    private func actionsSection(document: RegistryMacroDocument) -> some View {
        Section {
            Button {
                Task { await apply(document: document) }
            } label: {
                if applying {
                    ProgressView()
                } else {
                    Label("Update", systemImage: "arrow.triangle.2.circlepath")
                }
            }
            .frame(maxWidth: .infinity)
            .buttonStyle(.borderedProminent)
            .disabled(applying)

            Button("Keep My Version") {
                dismiss()
            }

            if let slug = macro.registry?.slug,
               let url = URL(string: "https://carrierwave.app/m/\(slug)")
            {
                Button {
                    openURL(url)
                } label: {
                    Label("View on Carrierwave.app", systemImage: "safari")
                }
            }
        } footer: {
            if macro.capabilities.usesRawBytes || document.toRadioMacroDocument().macro.capabilities.usesRawBytes {
                Text("Raw-bytes acceptance is reset when you apply this update — the safety gate will prompt again.")
                    .font(.caption)
            }
        }
    }

    private func errorSection(_ message: String) -> some View {
        Section {
            VStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button("Retry") {
                    Task { await load(force: true) }
                }
                .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func load(force: Bool = false) async {
        guard let slug = macro.registry?.slug else {
            loadError = "Macro has no registry slug"
            return
        }
        if document != nil, !force {
            return
        }
        guard let client = MacrosRegistryHolder.shared.client else {
            loadError = "Registry not yet configured"
            return
        }
        do {
            let fetched = try await client.get(slug: slug)
            let remoteSpec = fetched.toRadioMacroDocument().macro
            changes = RadioMacroSpecDiff.diff(local: macro.toSpec(), remote: remoteSpec)
            document = fetched
            loadError = nil
        } catch {
            loadError = String(describing: error)
        }
    }

    private func apply(document: RegistryMacroDocument) async {
        applying = true
        defer { applying = false }
        let remoteSpec = document.toRadioMacroDocument().macro
        let coordinator = MacroImportCoordinator()
        let outcome = await coordinator.evaluate(
            spec: remoteSpec,
            provenance: .registry(slug: document.slug)
        )
        switch outcome {
        case let .readyToInstall(decoded, _, _):
            let oldHash = MacroSpecHash.canonical(macro.toSpec())
            UserDefaultsRawBytesAcceptanceStore.shared.invalidate(specId: macro.id, hash: oldHash)
            applyDecoded(decoded, document: document)
            do {
                try EntityWriteSink.commitUpsert(macro, in: ctx)
                dismiss()
            } catch {
                applyError = "Couldn't save update: \(error.localizedDescription)"
                showFailure = true
            }
        case let .rejected(reason):
            applyError = reason
            showFailure = true
        }
    }

    private func applyDecoded(_ spec: RadioMacroSpec, document: RegistryMacroDocument) {
        macro.name = spec.name
        macro.icon = spec.icon
        macro.macroDescription = spec.description
        macro.tags = spec.tags ?? []
        macro.appliesTo = spec.appliesTo ?? []
        macro.args = spec.args
        macro.steps = spec.steps
        macro.capabilities = spec.capabilities
        macro.registry = RegistryRef(
            slug: document.slug,
            registryVersion: document.version,
            publishedAt: document.publishedAt
        )
        macro.format = document.format
        macro.updatedAt = Date()
    }
}

// MARK: - DiffRow

private struct DiffRow: View {
    let change: RadioMacroSpecDiff.Change

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "minus.circle.fill")
                    .foregroundStyle(.red)
                Text(change.before ?? "—")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "plus.circle.fill")
                    .foregroundStyle(.green)
                Text(change.after ?? "—")
                    .font(.subheadline)
            }
        }
        .padding(.vertical, 2)
    }
}
