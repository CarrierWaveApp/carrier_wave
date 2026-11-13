// Keyer Row Settings View
//
// Detail page for the automatic CW keyer row in the Keyboard Rows hub:
// documents the conditions under which the row appears and links to the
// CW message editor.

import SwiftUI

struct KeyerRowSettingsView: View {
    // MARK: Internal

    var body: some View {
        List {
            Section {
                conditionRow(
                    "CW Bridge connected over USB",
                    satisfied: radioService.bridgeHasCWKeyer && radioService.bridgeUSBConnected
                )
                conditionRow(
                    "Radio mode is CW or CW-R",
                    satisfied: radioService.radioMode == "CW" || radioService.radioMode == "CW-R"
                )
                conditionRow(
                    "At least one CW message programmed",
                    satisfied: !radioService.cwKeyer.programmedSlots.isEmpty
                )
            } header: {
                Text("Appears when")
            } footer: {
                Text(
                    """
                    The keyer row has no on/off switch — it appears automatically \
                    when all three conditions are met, in the position set on the \
                    previous screen.
                    """
                )
            }

            Section {
                NavigationLink("CW Messages") {
                    CWMessageListView()
                }
            } footer: {
                Text("Message slots are shared with the radio's keyer memories.")
            }
        }
        .navigationTitle("CW Keyer")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            KeyboardRowsStackPreview(highlighted: .keyer)
        }
    }

    // MARK: Private

    @State private var radioService = RadioService.shared

    private func conditionRow(_ label: String, satisfied: Bool) -> some View {
        HStack {
            Text(label)
            Spacer()
            Image(systemName: satisfied ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(satisfied ? .green : .secondary)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(satisfied ? "met" : "not met")")
    }
}

#Preview {
    NavigationStack {
        KeyerRowSettingsView()
    }
}
