import SwiftUI

/// Settings tab for CW keyer F1-F12 message configuration.
struct KeyerSettingsTab: View {
    // MARK: Internal

    var body: some View {
        Form {
            Section("CW Speed") {
                Stepper("WPM: \(wpm)", value: $wpm, in: 5 ... 60)
            }

            Section("Function Key Messages") {
                ForEach(1 ... 12, id: \.self) { slot in
                    HStack {
                        Text("F\(slot)")
                            .font(.caption.bold().monospaced())
                            .frame(width: 30, alignment: .trailing)
                        TextField(
                            defaultLabel(for: slot),
                            text: Binding(
                                get: { messages[slot] ?? "" },
                                set: { messages[slot] = $0 }
                            )
                        )
                        .font(.system(.body, design: .monospaced))
                        .onSubmit {
                            Task {
                                await keyerService.setMessage(slot: slot, text: messages[slot] ?? "")
                            }
                        }
                    }
                }
            }

            Section("Macros") {
                VStack(alignment: .leading, spacing: 4) {
                    macroHelp("{MYCALL}", "Your callsign")
                    macroHelp("{HISCALL}", "Their callsign")
                    macroHelp("{NR}", "Serial number (3 digits)")
                    macroHelp("{EXCH}", "Your exchange")
                    macroHelp("{FREQ}", "Current frequency")
                }
                .font(.caption)
            }
        }
        .formStyle(.grouped)
        .task {
            for slot in 1 ... 12 {
                messages[slot] = await keyerService.message(for: slot)
            }
        }
    }

    // MARK: Private

    @State private var messages: [Int: String] = [:]
    @AppStorage("cwKeyer.wpm") private var wpm: Int = 25

    private let keyerService = CWKeyerService()

    private func macroHelp(_ macro: String, _ description: String) -> some View {
        HStack {
            Text(macro)
                .fontWeight(.medium)
                .monospaced()
                .frame(width: 100, alignment: .leading)
            Text(description)
                .foregroundStyle(.secondary)
        }
    }

    private func defaultLabel(for slot: Int) -> String {
        switch slot {
        case 1: "CQ (F1)"
        case 2: "Exchange (F2)"
        case 3: "TU (F3)"
        case 4: "His Call (F4)"
        case 5: "NR? (F5)"
        case 6: "QSO B4 (F6)"
        case 7: "73 (F7)"
        case 8: "CQ TEST (F8)"
        default: "F\(slot)"
        }
    }
}
