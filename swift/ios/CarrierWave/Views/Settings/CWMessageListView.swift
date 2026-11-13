import SwiftUI

// MARK: - CWMessageListView

/// Settings list for CW memory keyer: WPM speed and 8 message slots.
struct CWMessageListView: View {
    // MARK: Internal

    var body: some View {
        List {
            speedSection
            messagesSection
        }
        .navigationTitle("CW Messages")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            UserProfileService.shared.backfillDefaultsFromProfileIfNeeded()
        }
    }

    // MARK: Private

    @State private var keyerService = CWKeyerService()
    @AppStorage("loggerDefaultCallsign") private var myCall = ""
    @AppStorage("loggerDefaultName") private var myName = ""
    @AppStorage("contestExchange") private var exchange = ""

    private var speedSection: some View {
        Section("CW Speed") {
            Stepper("WPM: \(keyerService.wpm)", value: $keyerService.wpm, in: 5 ... 60)
        }
    }

    private var messagesSection: some View {
        Section("Messages") {
            ForEach(keyerService.slots) { slot in
                NavigationLink {
                    CWMessageEditorView(slotID: slot.id, keyerService: keyerService)
                } label: {
                    slotRow(slot)
                }
            }
        }
    }

    private func slotRow(_ slot: CWSlot) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Text("\(slot.id)")
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundStyle(.orange)
                .frame(width: 20, alignment: .trailing)

            if slot.isEmpty {
                Text("Empty")
                    .foregroundStyle(.tertiary)
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    Text(slot.displayLabel)
                    Text(keyerService.expandForPreview(
                        slot.text,
                        myCall: myCall,
                        myName: myName,
                        exchange: exchange
                    ))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                }
            }
        }
    }
}
