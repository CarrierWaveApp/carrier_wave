import CarrierWaveCore
import SwiftData
import SwiftUI

// MARK: - RemoteSweepCWPane

//
// Remote-control mirror of `CWKeyerRow` (the activation-log keyer row). Field
// keys CW through Sweep over the existing TCP RemoteOp link — Sweep keeps its
// single-central BLE bond with the CW Bridge dongle.
//
// Pane shape: status line (freq · mode · WPM) on top, two-column grid of
// large slot buttons + STOP + CUSTOM beneath. Each slot tile shows the slot
// label as headline plus a footnote-sized monospaced preview of what will
// actually be sent (macros expanded against the current QSO context, or the
// list of missing macros when the slot can't be played yet). Long-press
// opens the slot editor sheet for programming.

struct RemoteSweepCWPane: View {
    // MARK: Internal

    var body: some View {
        VStack(spacing: 0) {
            statusLine
                .padding(.vertical, 8)
                .background(Color(.secondarySystemBackground))
            Divider()
            buttonStrip
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.secondarySystemBackground))
        }
        .navigationTitle("CW Keyer")
        .alert("Send CW", isPresented: $showCustomAlert) {
            TextField("CW text", text: $customText)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.characters)
            Button("Send") { sendCustom() }
            Button("Cancel", role: .cancel) { customText = "" }
        } message: {
            Text("Enter freeform text to send (max 100 chars)")
        }
        .sheet(item: $editingSlot) { slot in
            RemoteCWSlotEditor(slot: slot) { newLabel, newText in
                Task {
                    await coordinator.cwSetSlot(slot.id, label: newLabel, text: newText)
                }
            }
        }
    }

    // MARK: Private

    @Environment(RemoteSweepCoordinator.self) private var coordinator
    @Environment(\.modelContext) private var modelContext
    @State private var customText = ""
    @State private var showCustomAlert = false
    @State private var editingSlot: RemoteCWSlot?
    @State private var showPresetsMenu = false

    private var keyerAvailable: Bool {
        coordinator.isRemoteCWKeyerAvailable
    }

    private var sendingSlot: UInt8? {
        coordinator.cwStatus?.sendingSlot
    }

    private var programmedSlots: [RemoteCWSlot] {
        coordinator.cwSlots.filter { !$0.isEmpty }
    }

    /// Adaptive columns: 2 across in portrait, 3–4 in landscape (iPhone) or
    /// when docked in a CarPlay-style dashboard mount, without a separate
    /// orientation observer. Each tile holds at least 160pt so labels stay
    /// readable at arm's length.
    private var gridColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 160), spacing: 10)]
    }

    private var statusLine: some View {
        HStack(spacing: 6) {
            Spacer()
            if let radio = coordinator.radioState {
                Text(formatFrequency(radio.freqHz))
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                Text("·").font(.caption2).foregroundStyle(.secondary)
                Text(radio.mode)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                Text("·").font(.caption2).foregroundStyle(.secondary)
            }
            wpmButton
            if let buffer = coordinator.cwStatus?.bufferDepth, buffer > 0 {
                Text("buf \(buffer)")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.orange)
            }
            Spacer()
        }
    }

    private var wpmButton: some View {
        Menu {
            ForEach([15, 18, 20, 22, 25, 28, 30, 32, 35, 40], id: \.self) { wpm in
                Button("\(wpm) WPM") {
                    Task { await coordinator.cwSetSpeed(wpm: wpm) }
                }
            }
        } label: {
            Text("\(coordinator.cwStatus?.wpm.map { Int($0) } ?? 0) WPM")
                .font(.caption.weight(.medium))
                .foregroundStyle(keyerAvailable ? .orange : .secondary)
        }
        .disabled(!keyerAvailable)
    }

    private var buttonStrip: some View {
        ScrollView {
            VStack(spacing: 12) {
                LazyVGrid(columns: gridColumns, spacing: 10) {
                    ForEach(programmedSlots) { slot in
                        slotButton(slot)
                    }
                    stopButton
                    customButton
                    presetsButton
                }
                inlineHelp
                if programmedSlots.isEmpty, !coordinator.cwSlots.isEmpty {
                    emptySlotsRow
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
        }
    }

    @ViewBuilder
    private var inlineHelp: some View {
        if let error = coordinator.lastError {
            Text(error)
                .foregroundStyle(.red)
                .font(.caption)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        if !keyerAvailable {
            Text("Sweep has no CW Bridge keyer attached.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else if coordinator.cwSlotsLoading, programmedSlots.isEmpty {
            ProgressView().controlSize(.small)
        } else if programmedSlots.isEmpty {
            Text("No programmed slots — long-press a slot tile to set one up, or use CUSTOM.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var stopButton: some View {
        Button {
            Task { await coordinator.cwStop() }
        } label: {
            VStack(spacing: 4) {
                Image(systemName: "stop.fill").font(.title2)
                Text("STOP")
                    .font(.headline.weight(.bold))
            }
            .frame(maxWidth: .infinity, minHeight: 84)
            .background(Color.red.opacity(0.18))
            .foregroundStyle(Color.red)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .disabled(!keyerAvailable)
    }

    private var customButton: some View {
        Button {
            showCustomAlert = true
        } label: {
            VStack(spacing: 4) {
                Image(systemName: "text.cursor").font(.title2)
                Text("CUSTOM")
                    .font(.headline.weight(.bold))
            }
            .frame(maxWidth: .infinity, minHeight: 84)
            .background(Color.blue.opacity(0.18))
            .foregroundStyle(.blue)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .disabled(!keyerAvailable)
    }

    /// Mode-specific keyer preset menu. Tapping a preset programs Sweep's
    /// slot table in one shot via repeated `cwSetSlot` calls. Macros stay
    /// in the slot text so each preset works regardless of who's being
    /// worked next — Sweep expands them at play time from its Quick Entry.
    private var presetsButton: some View {
        Menu {
            ForEach(CWKeyerPreset.builtin) { preset in
                Button(preset.name) { applyPreset(preset) }
            }
        } label: {
            VStack(spacing: 4) {
                Image(systemName: "rectangle.stack.badge.plus").font(.title2)
                Text("PRESETS")
                    .font(.headline.weight(.bold))
            }
            .frame(maxWidth: .infinity, minHeight: 84)
            .background(Color.purple.opacity(0.18))
            .foregroundStyle(.purple)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .disabled(!keyerAvailable)
    }

    /// Show the empty slots as ghost buttons so the user has a tap target
    /// for programming when nothing is set up yet.
    private var emptySlotsRow: some View {
        LazyVGrid(columns: gridColumns, spacing: 10) {
            ForEach(coordinator.cwSlots.filter(\.isEmpty)) { slot in
                Button {
                    editingSlot = slot
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: "plus.circle").font(.title3)
                        Text("Slot \(slot.id)")
                            .font(.headline.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity, minHeight: 72)
                    .background(Color.gray.opacity(0.12))
                    .foregroundStyle(Color.secondary)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }
        }
        .padding(.top, 8)
    }

    private func slotButton(_ slot: RemoteCWSlot) -> some View {
        let preview = slot.text.trimmingCharacters(in: .whitespacesAndNewlines)
        return Button {
            // Send empty context — Sweep expands macros from its live Quick
            // Entry box. If a macro is missing, Sweep returns ack with detail
            // and we surface that via coordinator.lastError.
            Task { await coordinator.cwPlaySlot(slot.id) }
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                Text(displayLabel(for: slot))
                    .font(.title3.weight(.bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(preview)
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 84, alignment: .topLeading)
            .background(Color.orange.opacity(0.15))
            .foregroundStyle(.orange)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .opacity(sendingSlot == slot.id ? 0.5 : 1.0)
        .disabled(!keyerAvailable)
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.5).onEnded { _ in
                editingSlot = slot
            }
        )
    }

    /// Push every slot in the preset to Sweep sequentially. Sequential (not
    /// concurrent) because the keyer service writes one slot at a time and
    /// rebroadcasts `cw.slots` after each — running them in parallel would
    /// trigger redundant snapshots and races on the bridge memory writes.
    private func applyPreset(_ preset: CWKeyerPreset) {
        Task {
            for entry in preset.slots {
                _ = await coordinator.cwSetSlot(entry.id, label: entry.label, text: entry.text)
            }
        }
    }

    private func displayLabel(for slot: RemoteCWSlot) -> String {
        let trimmed = slot.label.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty {
            return trimmed
        }
        let firstWord = slot.text
            .trimmingCharacters(in: .whitespaces)
            .components(separatedBy: .whitespaces)
            .first ?? ""
        let stripped = firstWord
            .replacingOccurrences(of: "{", with: "")
            .replacingOccurrences(of: "}", with: "")
        if !stripped.isEmpty {
            return stripped
        }
        return "Slot \(slot.id)"
    }

    private func sendCustom() {
        let text = String(customText.prefix(100))
        guard !text.isEmpty else {
            return
        }
        Task { await coordinator.cwSendText(text) }
        customText = ""
    }

    private func formatFrequency(_ hz: UInt64) -> String {
        let mhz = Double(hz) / 1_000_000
        return String(format: "%.5f", mhz)
    }
}

// MARK: - RemoteCWSlotEditor

private struct RemoteCWSlotEditor: View {
    // MARK: Internal

    let slot: RemoteCWSlot
    let onSave: (String, String) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("Label") {
                    TextField("Optional short label", text: $label)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.characters)
                }
                Section("Text") {
                    TextEditor(text: $text)
                        .frame(minHeight: 80)
                        .font(.system(.body, design: .monospaced))
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.characters)
                }
                Section("Macros") {
                    Text("{MYCALL}, {CALL}, {NR}, {RST}, {NAME}, {EXCH} are expanded by Sweep at play time.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Slot \(slot.id)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(label, text)
                        dismiss()
                    }
                }
            }
            .onAppear {
                label = slot.label
                text = slot.text
            }
        }
    }

    // MARK: Private

    @Environment(\.dismiss) private var dismiss
    @State private var label = ""
    @State private var text = ""
}
