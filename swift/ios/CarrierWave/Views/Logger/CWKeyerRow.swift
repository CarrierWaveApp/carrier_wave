import CarrierWaveCore
import SwiftUI

// MARK: - CWKeyerRow

/// Keyer button strip shown above the logger command row.
/// Displays radio status and scrollable CW memory slot buttons.
struct CWKeyerRow: View {
    // MARK: Internal

    let keyerService: CWKeyerService
    let onPlay: (Int, [String: String]) -> Void
    let onStop: () -> Void
    let onSendText: (String) -> Void
    let onEdit: (Int) -> Void
    let onSpeedChange: (UInt8) -> Void
    let context: () -> [String: String]

    var body: some View {
        VStack(spacing: 0) {
            statusLine
            Divider()
            keyerButtons
        }
        .background(Color(.secondarySystemBackground))
        .alert("Send CW", isPresented: $showCustomAlert) {
            TextField("CW text", text: $customText)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.characters)
            Button("Send") {
                let text = String(customText.prefix(100))
                guard !text.isEmpty else {
                    return
                }
                onSendText(text)
                customText = ""
            }
            Button("Cancel", role: .cancel) {
                customText = ""
            }
        } message: {
            Text("Enter freeform text to send (max 100 chars)")
        }
    }

    // MARK: Private

    @State private var radioService = RadioService.shared
    @State private var showSpeedPopover = false
    @State private var showCustomAlert = false
    @State private var customText = ""

    private var isYaesu: Bool {
        radioService.bridgeDetectedRadio?.hasPrefix("Yaesu") == true
    }

    private var statusLine: some View {
        HStack(spacing: 4) {
            Spacer()
            if let freq = radioService.radioFrequencyMHz {
                Text(FrequencyFormatter.format(freq))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text("·")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if let mode = radioService.radioMode {
                Text(mode)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text("·")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Button {
                showSpeedPopover = true
            } label: {
                Text("\(keyerService.wpm) WPM")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.orange)
            }
            .popover(isPresented: $showSpeedPopover) {
                wpmStepper
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }

    private var wpmStepper: some View {
        Stepper(
            "WPM: \(keyerService.wpm)",
            value: Binding(
                get: { keyerService.wpm },
                set: { newVal in
                    keyerService.wpm = newVal
                    onSpeedChange(UInt8(newVal))
                }
            ),
            in: 5 ... 60
        )
        .padding()
        .presentationCompactAdaptation(.popover)
    }

    private var keyerButtons: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(keyerService.programmedSlots) { slot in
                    slotButton(slot)
                }
                stopButton
                customButton
            }
            .padding(.horizontal, 8)
        }
        .padding(.vertical, 6)
    }

    private var stopButton: some View {
        Button {
            onStop()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "stop.fill")
                Text("STOP")
            }
            .font(.system(size: 12, weight: .semibold))
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(isYaesu ? Color.gray.opacity(0.1) : Color.red.opacity(0.15))
            .foregroundStyle(isYaesu ? Color.secondary : Color.red)
            .clipShape(Capsule())
        }
        .disabled(isYaesu)
        .help(isYaesu ? "Stop not supported on Yaesu radios via CAT" : "Stop CW")
    }

    private var customButton: some View {
        Button {
            showCustomAlert = true
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "text.cursor")
                Text("CUSTOM")
            }
            .font(.system(size: 12, weight: .semibold))
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(Color.blue.opacity(0.15))
            .foregroundStyle(.blue)
            .clipShape(Capsule())
        }
    }

    private func slotButton(_ slot: CWSlot) -> some View {
        Button {
            onPlay(slot.id, context())
        } label: {
            Text(slot.displayLabel)
                .font(.system(size: 12, weight: .semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(Color.orange.opacity(0.15))
                .foregroundStyle(.orange)
                .clipShape(Capsule())
        }
        .opacity(radioService.cwSendingSlot == slot.id ? 0.5 : 1.0)
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.5).onEnded { _ in
                onEdit(slot.id)
            }
        )
    }
}
