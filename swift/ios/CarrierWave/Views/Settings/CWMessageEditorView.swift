import SwiftUI

// MARK: - CWMessageEditorView

/// Detail editor for a single CW memory keyer slot.
struct CWMessageEditorView: View {
    // MARK: Internal

    let slotID: Int

    @Bindable var keyerService: CWKeyerService

    var body: some View {
        Form {
            labelSection
            messageSection
            macroSection
            previewSection
        }
        .navigationTitle("Message \(slotID)")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { loadSlot() }
        .onDisappear { saveSlot() }
    }

    // MARK: Private

    @State private var label: String = ""
    @State private var text: String = ""
    @Environment(\.dismiss) private var dismiss
    @AppStorage("loggerDefaultCallsign") private var myCall = ""
    @AppStorage("loggerDefaultName") private var myName = ""
    @AppStorage("contestExchange") private var exchange = ""

    // MARK: - Sections

    private var labelSection: some View {
        Section("Label") {
            TextField("CQ, EXCH, TU...", text: $label)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.characters)
                .onChange(of: label) { _, newValue in
                    if newValue.count > 8 {
                        label = String(newValue.prefix(8))
                    }
                }
        }
    }

    private var messageSection: some View {
        Section("Message") {
            TextField("CQ CQ DE {MYCALL} K", text: $text, axis: .vertical)
                .font(.system(.body, design: .monospaced))
                .autocorrectionDisabled()
                .textInputAutocapitalization(.characters)
                .lineLimit(3 ... 5)
                .onChange(of: text) { _, newValue in
                    if newValue.count > CWKeyerService.maxSlotLength {
                        text = String(newValue.prefix(CWKeyerService.maxSlotLength))
                    }
                }
        }
    }

    private var macroSection: some View {
        Section("Insert Macro") {
            FlowLayout(spacing: 8) {
                ForEach(CWKeyerService.macroVariables, id: \.macro) { item in
                    macroPill(item.macro, isVariable: true)
                }
                ForEach(CWKeyerService.macroProsigns, id: \.self) { prosign in
                    macroPill(prosign, isVariable: false)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var previewSection: some View {
        Section("Preview") {
            Text(keyerService.expandForPreview(
                text,
                myCall: myCall,
                myName: myName,
                exchange: exchange
            ))
            .font(.system(.body, design: .monospaced))
            .foregroundStyle(.green)
        }
    }

    // MARK: - Helpers

    private func macroPill(_ macro: String, isVariable: Bool) -> some View {
        let bgOpacity: Double = isVariable ? 0.15 : 0.25
        let fgColor: Color = isVariable ? .orange : Color.orange.opacity(0.8)

        return Button {
            text.append(macro)
        } label: {
            Text(macro)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(fgColor)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.orange.opacity(bgOpacity), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private func loadSlot() {
        guard let slot = keyerService.slot(for: slotID) else {
            return
        }
        label = slot.label
        text = slot.text
    }

    private func saveSlot() {
        keyerService.updateSlot(id: slotID, label: label, text: text)
    }
}
