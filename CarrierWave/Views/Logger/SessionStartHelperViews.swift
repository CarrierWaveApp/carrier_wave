import CarrierWaveCore
import SwiftUI

// MARK: - CallsignBreakdownView

/// Extracted view showing callsign prefix/base/suffix breakdown
struct CallsignBreakdownView: View {
    let prefix: String
    let baseCallsign: String
    let suffix: String

    var body: some View {
        HStack(spacing: 4) {
            if !prefix.isEmpty {
                Text(prefix.uppercased())
                    .font(.caption.monospaced())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.orange.opacity(0.2))
                    .clipShape(Capsule())
                Text("/")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(baseCallsign.uppercased())
                .font(.caption.monospaced())
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.blue.opacity(0.2))
                .clipShape(Capsule())

            if !suffix.isEmpty {
                Text("/")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(suffix)
                    .font(.caption.monospaced())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.green.opacity(0.2))
                    .clipShape(Capsule())
            }
        }
    }
}

// MARK: - ProgramChip

/// Toggle chip for selecting an operating program (POTA, SOTA)
struct ProgramChip: View {
    let label: String
    let icon: String
    let isSelected: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 4) {
                Image(systemName: isSelected ? "checkmark" : icon)
                    .font(.caption.weight(.semibold))
                Text(label)
                    .font(.subheadline.weight(.medium))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                isSelected
                    ? Color.accentColor.opacity(0.15)
                    : Color(.tertiarySystemFill)
            )
            .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(
                        isSelected ? Color.accentColor : Color.clear,
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - ActivationSectionView

/// Extracted view for program selection with toggle chips
struct ActivationSectionView: View {
    // MARK: Internal

    @Binding var selectedPrograms: Set<String>
    @Binding var parkReference: String
    @Binding var sotaReference: String
    @Binding var missionReference: String
    @Binding var isRove: Bool

    /// User's grid square for nearby parks
    var userGrid: String?
    /// Default country prefix for park shorthand
    var defaultCountry: String = "US"

    var body: some View {
        Section {
            programChips
            if selectedPrograms.contains("pota") {
                potaFields
            }
            if selectedPrograms.contains("sota") {
                sotaFields
            }
            if selectedPrograms.contains("aoa") {
                aoaFields
            }
        } header: {
            Text("Programs")
        } footer: {
            if selectedPrograms.isEmpty {
                Text("No program selected — casual session")
            }
        }
    }

    // MARK: Private

    private var programChips: some View {
        HStack(spacing: 12) {
            ProgramChip(
                label: "POTA",
                icon: "tree",
                isSelected: selectedPrograms.contains("pota"),
                onToggle: { toggleProgram("pota") }
            )
            ProgramChip(
                label: "SOTA",
                icon: "mountain.2",
                isSelected: selectedPrograms.contains("sota"),
                onToggle: { toggleProgram("sota") }
            )
            ProgramChip(
                label: "AoA",
                icon: "eye",
                isSelected: selectedPrograms.contains("aoa"),
                onToggle: { toggleProgram("aoa") }
            )
            Spacer()
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var potaFields: some View {
        ParkEntryField(
            parkReference: $parkReference,
            label: "Parks",
            placeholder: "1234 or US-1234",
            userGrid: userGrid,
            defaultCountry: defaultCountry
        )
        Toggle(isOn: $isRove) {
            VStack(alignment: .leading, spacing: 2) {
                Text("This is a rove")
                    .font(.subheadline.weight(.medium))
                Text("Visit multiple parks in one session")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var sotaFields: some View {
        SummitEntryField(
            sotaReference: $sotaReference,
            userGrid: userGrid
        )
    }

    private var aoaFields: some View {
        HStack {
            Text("Mission")
            Spacer()
            TextField("M-a01f", text: $missionReference)
                .multilineTextAlignment(.trailing)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .frame(width: 120)
        }
    }

    private func toggleProgram(_ slug: String) {
        withAnimation(.easeInOut(duration: 0.2)) {
            if selectedPrograms.contains(slug) {
                selectedPrograms.remove(slug)
            } else {
                selectedPrograms.insert(slug)
            }
        }
        // Clear rove when POTA is deselected
        if slug == "pota", !selectedPrograms.contains("pota") {
            isRove = false
        }
    }
}

// MARK: - SessionStartInput

/// Input for session start validation
struct SessionStartInput {
    let callsign: String
    let programs: Set<String>
    let parkReference: String
    let sotaReference: String
    let missionReference: String
    let frequency: Double?
}

// MARK: - SessionStartValidation

/// Validation logic for session start requirements
enum SessionStartValidation {
    static func canStart(_ input: SessionStartInput) -> Bool {
        guard !input.callsign.isEmpty, input.callsign.count >= 3 else {
            return false
        }
        if input.programs.contains("pota"),
           input.parkReference.trimmingCharacters(in: .whitespaces).isEmpty
        {
            return false
        }
        if input.programs.contains("sota"),
           input.sotaReference.trimmingCharacters(in: .whitespaces).isEmpty
        {
            return false
        }
        if input.programs.contains("aoa"),
           input.missionReference.trimmingCharacters(in: .whitespaces).isEmpty
        {
            return false
        }
        return true
    }

    static func disabledReason(_ input: SessionStartInput) -> String? {
        if input.callsign.isEmpty || input.callsign.count < 3 {
            return "Set your callsign in Settings → About Me"
        }
        if input.programs.contains("pota"),
           input.parkReference.trimmingCharacters(in: .whitespaces).isEmpty
        {
            return "POTA requires park reference"
        }
        if input.programs.contains("sota"),
           input.sotaReference.trimmingCharacters(in: .whitespaces).isEmpty
        {
            return "SOTA requires summit reference"
        }
        if input.programs.contains("aoa"),
           input.missionReference.trimmingCharacters(in: .whitespaces).isEmpty
        {
            return "AoA requires mission reference"
        }
        return nil
    }
}
