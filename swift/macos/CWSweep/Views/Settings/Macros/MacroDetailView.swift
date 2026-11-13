import CarrierWaveData
import SwiftData
import SwiftUI

// MARK: - MacroDetailView

/// Read-only detail view for a `RadioMacro`. Phase 1 surfaces name,
/// description, capability chips, applies-to protocols, and a
/// human-readable step list with Run / Edit affordances in the toolbar.
/// On macOS Run opens a separate window (see `MacroRunWindowController`);
/// Edit uses a sheet for now (matches iOS shape).
struct MacroDetailView: View {
    // MARK: Internal

    let macro: RadioMacro

    var body: some View {
        List {
            headerSection
            if let tombstone = tombstoneReason {
                tombstoneSection(tombstone)
            }
            if !macro.capabilities.regionsOrEmpty.isEmpty || hasAnyCapability {
                capabilitiesSection
            }
            if let appliesTo = macro.toSpec().appliesTo, !appliesTo.isEmpty {
                appliesToSection(appliesTo)
            }
            if !macro.args.isEmpty {
                argsSection
            }
            stepsSection
            metadataSection
        }
        .navigationTitle(macro.name)
        .toolbar { toolbarContent }
        .sheet(isPresented: $isEditing) {
            NavigationStack {
                MacroEditorView(macro: macro, isNewlyCreated: false)
            }
            .frame(minWidth: 560, minHeight: 640)
        }
        .alert("Export not yet available", isPresented: $exportAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Exporting .cwmacro documents ships in a later update.")
        }
    }

    // MARK: Private

    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss

    @State private var isEditing = false
    @State private var exportAlert = false

    private var tombstoneReason: MacroTombstoneReason? {
        guard macro.tombstoned else {
            return nil
        }
        let parsed = MacroTombstoneReason.from(raw: macro.tombstoneReason)
        return (parsed?.isServerOriginated == true) ? parsed : nil
    }

    private var hasAnyCapability: Bool {
        let caps = macro.capabilities
        return caps.transmits
            || caps.usesRawBytes
            || caps.changesFrequency
            || caps.changesMode
            || caps.changesPower
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            if tombstoneReason == nil {
                Button {
                    runMacro()
                } label: {
                    Label("Run", systemImage: "play.fill")
                }
                .help("Run macro")
            }
            Menu {
                Button {
                    runMacro()
                } label: {
                    Label("Run", systemImage: "play.fill")
                }
                .disabled(tombstoneReason != nil)
                Button {
                    isEditing = true
                } label: {
                    Label("Edit", systemImage: "pencil")
                }
                .disabled(tombstoneReason != nil)
                Button {
                    exportAlert = true
                } label: {
                    Label("Export…", systemImage: "square.and.arrow.up")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
        }
    }

    private var headerSection: some View {
        Section {
            HStack(spacing: 12) {
                Image(systemName: macro.icon ?? "wand.and.stars")
                    .font(.system(size: 28))
                    .foregroundStyle(.tint)
                    .frame(width: 44, height: 44)
                    .background(Color.accentColor.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 4) {
                    Text(macro.name)
                        .font(.title3.weight(.semibold))
                    if let author = macro.author, !author.isEmpty {
                        Text("by \(author)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }
            if let description = macro.macroDescription, !description.isEmpty {
                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if !macro.tags.isEmpty {
                MacroTagStrip(tags: macro.tags)
            }
        }
    }

    private var capabilitiesSection: some View {
        Section("Capabilities") {
            MacroCapabilityChipsFull(capabilities: macro.capabilities)
                .padding(.vertical, 2)
            if let regions = macro.capabilities.regions, !regions.isEmpty {
                LabeledContent("Regions", value: regions.joined(separator: ", "))
                    .font(.caption)
            }
        }
    }

    private var argsSection: some View {
        Section("Arguments") {
            ForEach(macro.args) { arg in
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

    private var stepsSection: some View {
        Section {
            ForEach(Array(macro.steps.enumerated()), id: \.offset) { index, step in
                MacroStepSummaryRow(index: index, step: step)
            }
        } header: {
            Text("Steps")
        } footer: {
            if macro.steps.isEmpty {
                Text("No steps yet — open the editor to add some.")
                    .font(.caption)
            }
        }
    }

    private var metadataSection: some View {
        Section("Metadata") {
            LabeledContent("Updated") {
                Text(macro.updatedAt, style: .date)
                    .font(.caption.monospacedDigit())
            }
            LabeledContent("Created") {
                Text(macro.createdAt, style: .date)
                    .font(.caption.monospacedDigit())
            }
            if let registry = macro.registry {
                LabeledContent("Registry slug") {
                    Text(registry.slug)
                        .font(.caption.monospaced())
                }
                LabeledContent("Registry version") {
                    Text("v\(registry.registryVersion)")
                        .font(.caption.monospacedDigit())
                }
            }
        }
    }

    private func tombstoneSection(_ reason: MacroTombstoneReason) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Label(reason.headlineLabel, systemImage: "exclamationmark.octagon")
                    .foregroundStyle(.orange)
                    .font(.headline)
                Text(tombstoneExplanation(reason))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Button(role: .destructive) {
                deleteFromLibrary()
            } label: {
                Label("Delete from My Library", systemImage: "trash")
            }
            Button {
                dismiss()
            } label: {
                Label("Keep as Read-only Artifact", systemImage: "lock.fill")
            }
        } header: {
            Text("Registry Status")
        }
    }

    private func appliesToSection(_ appliesTo: [RadioCommandProtocol]) -> some View {
        Section("Applies To") {
            ForEach(appliesTo, id: \.rawValue) { rigProtocol in
                Label(rigProtocol.displayName, systemImage: "antenna.radiowaves.left.and.right")
            }
        }
    }

    private func tombstoneExplanation(_ reason: MacroTombstoneReason) -> String {
        switch reason {
        case .withdrawn:
            "The author pulled this macro from the registry. You can keep it locally — "
                + "it just won't appear in Browse or auto-update."
        case .adminRemoved:
            "Carrier Wave moderators removed this macro. It may have violated registry policy."
        case .authorDeleted:
            "The author deleted their account, so this macro is no longer maintained upstream."
        case .userDeleted:
            "You removed this macro from your library."
        }
    }

    private func deleteFromLibrary() {
        ctx.delete(macro)
        try? ctx.save()
        dismiss()
    }

    /// Stubbed until Plan G Task 3 ships `MacroRunWindowController`. The
    /// editor sheet path is fine to ship in Task 2; Task 3 wires the
    /// window-based runner.
    private func runMacro() {
        MacroRunWindowController.present(spec: macro.toSpec())
    }
}

// MARK: - MacroStepSummaryRow

struct MacroStepSummaryRow: View {
    let index: Int
    let step: RadioMacroStep

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(index + 1)")
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 22, alignment: .trailing)
            VStack(alignment: .leading, spacing: 2) {
                Text(step.summaryTitle)
                    .font(.body)
                if let detail = step.summaryDetail {
                    Text(detail)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
    }
}

// MARK: - MacroTagStrip

struct MacroTagStrip: View {
    let tags: [String]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(tags, id: \.self) { tag in
                    Text("#\(tag)")
                        .font(.caption2.weight(.medium))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.15), in: Capsule())
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

// MARK: - RadioMacroCapabilities helper

private extension RadioMacroCapabilities {
    var regionsOrEmpty: [String] {
        regions ?? []
    }
}

// MARK: - RadioCommandProtocol display name

extension RadioCommandProtocol {
    var displayName: String {
        switch self {
        case .civ: "Icom CI-V"
        case .kenwood: "Kenwood CAT"
        case .yaesu: "Yaesu CAT"
        case .flex: "FlexRadio"
        }
    }
}

// MARK: - RadioCommandParamType display name

extension RadioCommandParamType {
    var displayName: String {
        switch self {
        case .bool: "Boolean"
        case .enumeration: "Enum"
        case .uint8: "UInt8"
        case .uint16: "UInt16"
        case .uint32: "UInt32"
        case .uint64: "UInt64"
        case .freqHz: "Frequency (Hz)"
        case .frequency: "Frequency"
        case .string: "Text"
        }
    }
}

// MARK: - RadioMacroStep summary

extension RadioMacroStep {
    var summaryTitle: String {
        switch self {
        case .delay: "Wait"
        case .setFrequency: "Set Frequency"
        case .setMode: "Set Mode"
        case .setPowerWatts: "Set Power"
        case .setPTT: "Press PTT"
        case .sendCW: "Send CW"
        case .vendorCommand: "Vendor Command"
        case .rawBytes: "Raw Bytes"
        case .readField: "Read Field"
        case .waitUntil: "Wait Until"
        case .assert: "Assert"
        }
    }

    var summaryDetail: String? {
        switch self {
        case let .delay(durationMs):
            "\(durationMs) ms"
        case let .setFrequency(hz):
            String(format: "%.6f MHz", Double(hz) / 1_000_000)
        case let .setMode(mode):
            mode
        case let .setPowerWatts(watts):
            "\(watts) W"
        case let .setPTT(on):
            on ? "ON" : "OFF"
        case let .sendCW(text):
            "\"\(text)\""
        case let .vendorCommand(commandId, args):
            if let args, !args.isEmpty {
                "\(commandId)(\(RadioMacroStep.formatVendorArgs(args)))"
            } else {
                commandId
            }
        case let .rawBytes(protocolName, bytes):
            "\(protocolName): \(bytes)"
        case let .readField(field, into):
            "\(field) → ctx.\(into)"
        case let .waitUntil(expr, timeoutMs):
            "\(expr) (≤ \(timeoutMs) ms)"
        case let .assert(expr, message):
            "\(expr) — \"\(message)\""
        }
    }
}
