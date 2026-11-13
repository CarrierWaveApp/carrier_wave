import SwiftUI

// MARK: - VimModeSettingsTab

struct VimModeSettingsTab: View {
    // MARK: Internal

    var body: some View {
        Form {
            Section {
                Toggle("Enable Vim Mode", isOn: $vimModeEnabled)

                Text(
                    "Vim mode adds a composable keyboard language for navigating spots, "
                        + "tuning your radio, and logging QSOs without the mouse. "
                        + "Type :help in Normal mode for a full command reference."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            } header: {
                Text("Keyboard Mode")
            }

            Section {
                VStack(alignment: .leading, spacing: 8) {
                    learningLevel(
                        "Level 1 — Survive",
                        keys: "j k t i Esc",
                        desc: "Browse spots, tune, log QSOs, escape"
                    )
                    learningLevel(
                        "Level 2 — Efficient",
                        keys: "/ ? . '' Tab",
                        desc: "Filter, lookup, repeat, jump-back, pane switching"
                    )
                    learningLevel(
                        "Level 3 — Power",
                        keys: "m/' q/@ :",
                        desc: "Marks, macros, command mode"
                    )
                }
            } header: {
                Text("Learning Path")
            }
        }
        .formStyle(.grouped)
    }

    // MARK: Private

    @AppStorage("vimModeEnabled") private var vimModeEnabled = false

    private func learningLevel(_ title: String, keys: String, desc: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(keys)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.blue)
                .frame(width: 100, alignment: .trailing)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.bold())
                Text(desc)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
