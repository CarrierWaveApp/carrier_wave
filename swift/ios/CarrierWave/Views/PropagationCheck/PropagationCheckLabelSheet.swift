import CarrierWaveData
import SwiftUI

// MARK: - PropagationCheckLabelSheet

/// Post-stop prompt for naming the just-completed check. Auto-name suggestion
/// is pre-filled — accepting it costs only one tap.
struct PropagationCheckLabelSheet: View {
    // MARK: Lifecycle

    init(prompt: PropagationCheckLabelPrompt, onSave: @escaping (String) -> Void) {
        self.prompt = prompt
        self.onSave = onSave
        _label = State(initialValue: prompt.suggestedLabel)
    }

    // MARK: Internal

    let prompt: PropagationCheckLabelPrompt
    let onSave: (String) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Label", text: $label, axis: .vertical)
                        .lineLimit(1 ... 3)
                        .autocorrectionDisabled()
                } header: {
                    Text("Name this check")
                } footer: {
                    Text("Compare reads better with names like \"EFHW roof, 20m\" or \"Dipole yard, 40m night\".")
                }
                Section {
                    headlineRow("Total spots", value: "\(prompt.snapshot.spots.count)")
                    headlineRow(
                        "Bands",
                        value: prompt.snapshot.spots.compactMap(\.band).reduce(into: Set<String>()) { $0.insert($1) }
                            .sorted().joined(separator: " · ")
                    )
                    headlineRow("Duration", value: format(prompt.duration))
                }
            }
            .navigationTitle("Save Check")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Discard", role: .destructive) {
                        onSave("")
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(label.trimmingCharacters(in: .whitespacesAndNewlines))
                        dismiss()
                    }
                    .disabled(label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    // MARK: Private

    @Environment(\.dismiss) private var dismiss
    @State private var label: String

    private func headlineRow(_ title: String, value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }

    private func format(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        if mins == 0 {
            return "\(Int(seconds)) s"
        }
        return "\(mins) min"
    }
}

// MARK: - PropagationCheckLabelPrompt

/// Identifiable wrapper for the label sheet binding. Carries the snapshot and
/// the suggested auto-name.
nonisolated struct PropagationCheckLabelPrompt: Identifiable {
    let id = UUID()
    var snapshot: PropagationCheckSession.Snapshot
    var startedAt: Date
    var bands: [String]

    var duration: TimeInterval {
        max(0, snapshot.endedAt.timeIntervalSince(startedAt))
    }

    var suggestedLabel: String {
        let bandPart = bands.isEmpty ? "" : bands.joined(separator: "+") + " · "
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return "\(bandPart)\(formatter.string(from: startedAt))"
    }
}
