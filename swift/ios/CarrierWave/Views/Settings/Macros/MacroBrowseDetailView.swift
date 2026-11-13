import CarrierWaveData
import SwiftData
import SwiftUI

// MARK: - MacroBrowseDetailView

/// Read-only detail view for a registry macro that hasn't been installed
/// yet. Fetches the full document on appear, runs the verifier, and
/// exposes an Install button that persists a local `RadioMacro` row
/// with `registry.slug` + `registry.registryVersion` set.
struct MacroBrowseDetailView: View {
    // MARK: Internal

    let entry: RegistryListEntry
    let isInstalled: Bool

    var body: some View {
        List {
            headerSection
            if let document {
                fetchedSections(document)
            } else if loadError != nil {
                errorSection
            } else {
                ProgressView("Loading…")
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
            }
        }
        .navigationTitle(entry.name)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadIfNeeded()
        }
        .alert("Install failed", isPresented: $showFailureAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(installError ?? "Unknown error")
        }
        .alert("Installed", isPresented: $showSuccessAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("\"\(entry.name)\" is now in your library.")
        }
    }

    // MARK: Private

    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss

    @Query(filter: #Predicate<RadioMacro> { !$0.tombstoned })
    private var installedMacros: [RadioMacro]

    @State private var document: RegistryMacroDocument?
    @State private var loadError: String?
    @State private var installing = false
    @State private var installError: String?
    @State private var showFailureAlert = false
    @State private var showSuccessAlert = false

    private var currentlyInstalled: Bool {
        installedMacros.contains { $0.registry?.slug == entry.slug }
    }

    private var headerSection: some View {
        Section {
            HStack(spacing: 12) {
                Image(systemName: entry.icon ?? "wand.and.stars")
                    .font(.system(size: 28))
                    .foregroundStyle(.tint)
                    .frame(width: 44, height: 44)
                    .background(Color.accentColor.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.name)
                        .font(.title3.weight(.semibold))
                    if let callsign = entry.authorCallsign {
                        Text("by \(callsign) · v\(entry.version)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }
            if let description = entry.description, !description.isEmpty {
                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if !entry.tags.isEmpty {
                MacroTagStrip(tags: entry.tags)
            }
        }
    }

    private var errorSection: some View {
        Section {
            VStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                Text(loadError ?? "Couldn't load this macro")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button("Retry") {
                    Task { await loadIfNeeded(force: true) }
                }
                .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
        }
    }

    @ViewBuilder
    private func fetchedSections(_ document: RegistryMacroDocument) -> some View {
        let spec = document.toRadioMacroDocument().macro

        Section("Capabilities") {
            MacroCapabilityChipsFull(capabilities: spec.capabilities)
                .padding(.vertical, 2)
        }

        if let appliesTo = spec.appliesTo, !appliesTo.isEmpty {
            Section("Applies To") {
                ForEach(appliesTo, id: \.rawValue) { rigProtocol in
                    Label(rigProtocol.displayName, systemImage: "antenna.radiowaves.left.and.right")
                }
            }
        }

        if !spec.args.isEmpty {
            Section("Arguments") {
                ForEach(spec.args) { arg in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(arg.label ?? arg.name)
                            .font(.body)
                        Text("\(arg.type.displayName)\(arg.defaultValue.map { " · default: \($0)" } ?? "")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }

        Section("Steps") {
            ForEach(Array(spec.steps.enumerated()), id: \.offset) { index, step in
                MacroStepSummaryRow(index: index, step: step)
            }
        }

        Section {
            installButton(spec: spec)
        } footer: {
            if spec.capabilities.usesRawBytes {
                Text("This macro sends raw radio bytes. Review the steps before installing.")
                    .font(.caption)
            }
        }
    }

    private func installButton(spec: RadioMacroSpec) -> some View {
        Button {
            Task { await install(spec: spec) }
        } label: {
            Group {
                if installing {
                    ProgressView()
                } else if currentlyInstalled {
                    Label("Already Installed", systemImage: "checkmark.circle.fill")
                } else {
                    Label("Install", systemImage: "square.and.arrow.down")
                }
            }
            .labelStyle(.titleAndIcon)
            .frame(maxWidth: .infinity)
        }
        .controlSize(.large)
        .buttonStyle(.borderedProminent)
        .disabled(installing || currentlyInstalled)
    }

    private func loadIfNeeded(force: Bool = false) async {
        if document != nil, !force {
            return
        }
        guard let client = MacrosRegistryHolder.shared.client else {
            loadError = "Registry not yet configured"
            return
        }
        do {
            document = try await client.get(slug: entry.slug)
            loadError = nil
        } catch {
            loadError = friendlyError(error)
        }
    }

    private func install(spec: RadioMacroSpec) async {
        installing = true
        defer { installing = false }
        let coordinator = MacroImportCoordinator()
        let outcome = await coordinator.evaluate(
            spec: spec,
            provenance: .registry(slug: entry.slug)
        )
        switch outcome {
        case let .readyToInstall(decoded, _, _):
            let macro = RadioMacro.from(spec: decoded)
            macro.registry = RegistryRef(
                slug: entry.slug,
                registryVersion: entry.version,
                publishedAt: entry.publishedAt
            )
            ctx.insert(macro)
            do {
                try EntityWriteSink.commitUpsert(macro, in: ctx)
                showSuccessAlert = true
            } catch {
                installError = "Couldn't save to library: \(error.localizedDescription)"
                showFailureAlert = true
            }
        case let .rejected(reason):
            installError = reason
            showFailureAlert = true
        }
    }

    private func friendlyError(_ error: Error) -> String {
        switch error {
        case let MacrosRegistryClientError.server(status, _):
            "Server returned status \(status)"
        case let MacrosRegistryClientError.transport(message):
            message
        default:
            String(describing: error)
        }
    }
}
