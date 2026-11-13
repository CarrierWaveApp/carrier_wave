import CarrierWaveData
import SwiftUI

// MARK: - MacroEditorView+CapabilitiesSection

extension MacroEditorView {
    var capabilitiesSection: some View {
        Section {
            ForEach(MacroCapabilityToggle.allCases, id: \.rawValue) { toggle in
                MacroCapabilityToggleRow(
                    toggle: toggle,
                    capabilities: capabilitiesBinding,
                    inferred: inferredCapabilities,
                    onRequestRemoveSteps: { removeStepsThatRequire(toggle) }
                )
            }
        } header: {
            Text("Capabilities")
        } footer: {
            Text(
                "Capabilities declare what the macro is allowed to do. " +
                    "The verifier blocks Save if any step exceeds the declaration."
            )
        }
    }

    private var capabilitiesBinding: Binding<RadioMacroCapabilities> {
        Binding(
            get: { model.spec.capabilities },
            set: { newValue in
                model.spec.capabilities = newValue
                model.markDirty()
            }
        )
    }

    private var inferredCapabilities: RadioMacroCapabilities {
        MacroVerifier.inferCapabilities(from: model.spec.steps)
    }

    private func removeStepsThatRequire(_ toggle: MacroCapabilityToggle) {
        let inferredBefore = inferredCapabilities
        model.spec.steps.removeAll { step in
            stepRequires(step, toggle: toggle, inferred: inferredBefore)
        }
        model.markDirty()
    }

    private func stepRequires(
        _ step: RadioMacroStep,
        toggle: MacroCapabilityToggle,
        inferred _: RadioMacroCapabilities
    ) -> Bool {
        let contribution = MacroVerifier.inferCapabilities(from: [step])
        switch toggle {
        case .transmits: return contribution.transmits
        case .changesFrequency: return contribution.changesFrequency
        case .changesMode: return contribution.changesMode
        case .changesPower: return contribution.changesPower
        case .usesRawBytes: return contribution.usesRawBytes
        }
    }
}

// MARK: - MacroCapabilityToggle

enum MacroCapabilityToggle: String, CaseIterable {
    case transmits
    case changesFrequency
    case changesMode
    case changesPower
    case usesRawBytes

    // MARK: Internal

    var title: String {
        switch self {
        case .transmits: "Transmits"
        case .changesFrequency: "Changes Frequency"
        case .changesMode: "Changes Mode"
        case .changesPower: "Changes Power"
        case .usesRawBytes: "Sends Raw Bytes"
        }
    }

    var icon: String {
        switch self {
        case .transmits: "antenna.radiowaves.left.and.right"
        case .changesFrequency: "dial.high"
        case .changesMode: "waveform.path"
        case .changesPower: "bolt"
        case .usesRawBytes: "rectangle.dashed.badge.record"
        }
    }

    var tint: Color {
        switch self {
        case .transmits: .red
        case .usesRawBytes: .orange
        case .changesFrequency: .blue
        case .changesMode: .teal
        case .changesPower: .purple
        }
    }

    var detail: String {
        switch self {
        case .transmits: "Will key PTT or otherwise put the radio on the air."
        case .changesFrequency: "Will retune the radio."
        case .changesMode: "Will change CW / SSB / FM / digital mode."
        case .changesPower: "Will adjust transmit power."
        case .usesRawBytes: "Sends opaque vendor frames the safety net can't introspect."
        }
    }
}

// MARK: - MacroCapabilityToggleRow

struct MacroCapabilityToggleRow: View {
    // MARK: Internal

    let toggle: MacroCapabilityToggle
    @Binding var capabilities: RadioMacroCapabilities

    let inferred: RadioMacroCapabilities
    let onRequestRemoveSteps: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle(isOn: binding) {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(toggle.title)
                            .font(.body)
                        Text(toggle.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: toggle.icon)
                        .foregroundStyle(toggle.tint)
                }
            }
            if inferredOn, !declaredOn {
                Text("Steps already require this capability — turn it on to save.")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .alert("Steps require this capability", isPresented: $conflictAlert) {
            Button("Remove Conflicting Steps", role: .destructive) {
                onRequestRemoveSteps()
            }
            Button("Cancel", role: .cancel) {
                declaredOn = true
            }
        } message: {
            Text(
                "Disabling \(toggle.title) will break verification. " +
                    "Remove the steps that need it or keep the capability enabled."
            )
        }
    }

    // MARK: Private

    @State private var conflictAlert = false

    private var binding: Binding<Bool> {
        Binding(
            get: { declaredOn },
            set: { newValue in
                if !newValue, inferredOn {
                    conflictAlert = true
                } else {
                    declaredOn = newValue
                }
            }
        )
    }

    private var declaredOn: Bool {
        get {
            switch toggle {
            case .transmits: capabilities.transmits
            case .changesFrequency: capabilities.changesFrequency
            case .changesMode: capabilities.changesMode
            case .changesPower: capabilities.changesPower
            case .usesRawBytes: capabilities.usesRawBytes
            }
        }
        nonmutating set {
            switch toggle {
            case .transmits: capabilities.transmits = newValue
            case .changesFrequency: capabilities.changesFrequency = newValue
            case .changesMode: capabilities.changesMode = newValue
            case .changesPower: capabilities.changesPower = newValue
            case .usesRawBytes: capabilities.usesRawBytes = newValue
            }
        }
    }

    private var inferredOn: Bool {
        switch toggle {
        case .transmits: inferred.transmits
        case .changesFrequency: inferred.changesFrequency
        case .changesMode: inferred.changesMode
        case .changesPower: inferred.changesPower
        case .usesRawBytes: inferred.usesRawBytes
        }
    }
}
