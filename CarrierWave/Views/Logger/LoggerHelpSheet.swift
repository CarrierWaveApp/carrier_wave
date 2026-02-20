import SwiftUI

// MARK: - LoggerHelpSheet

/// Sheet displaying available logger commands with clear formatting
struct LoggerHelpSheet: View {
    // MARK: Internal

    var body: some View {
        NavigationStack {
            List {
                Section {
                    commandRow(
                        command: "FREQ <freq>",
                        description: "Set frequency",
                        example: "14.060, 14060 kHz, 14.060 MHz"
                    )
                    commandRow(
                        command: "<mode>",
                        description: "Set mode",
                        example: "CW, SSB, FT8, etc."
                    )
                    commandRow(
                        command: "SPOT [comment]",
                        description: "Self-spot to POTA",
                        example: "SPOT QRT, SPOT QSY"
                    )
                    commandRow(
                        command: "RBN [callsign]",
                        description: "Show RBN/POTA spots",
                        example: "RBN W1AW (or just RBN)"
                    )
                    commandRow(command: "POTA", description: "Show POTA activator spots")
                    commandRow(command: "SOLAR", description: "Show solar conditions")
                    commandRow(command: "WEATHER", description: "Show weather (or WX)")
                    commandRow(command: "MAP", description: "Show session QSO map")
                    commandRow(command: "HIDDEN", description: "Show deleted QSOs")
                    commandRow(
                        command: "NOTE <text>",
                        description: "Add a note to the session log"
                    )
                    commandRow(command: "HELP", description: "Show this help (or ?)")
                } header: {
                    Text("Commands")
                }

                Section {
                    HStack {
                        Text("Type a frequency directly:")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("14.060, 14060, 14060kHz")
                            .font(.subheadline.monospaced())
                            .foregroundStyle(.primary)
                    }
                } header: {
                    Text("Quick Entry")
                }
            }
            .navigationTitle("Logger Commands")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .landscapeAdaptiveDetents(portrait: [.medium, .large])
    }

    // MARK: Private

    @Environment(\.dismiss) private var dismiss

    private func commandRow(
        command: String,
        description: String,
        example: String? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(command)
                    .font(.subheadline.monospaced().weight(.semibold))
                    .foregroundStyle(.purple)
                Spacer()
                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
            }
            if let example {
                Text(example)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

#Preview {
    LoggerHelpSheet()
}
