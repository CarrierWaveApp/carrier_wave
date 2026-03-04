import SwiftUI

// MARK: - TourSessionStartSheet

/// Wrapper around SessionStartSheet for the tour.
/// Pre-fills mock data and intercepts the Start button.
struct TourSessionStartSheet: View {
    // MARK: Internal

    @Bindable var tourManager: LoggerTourManager

    var body: some View {
        NavigationStack {
            Form {
                tourCallsignSection
                tourModeSection
                tourFrequencySection
                tourPowerSection
                tourEquipmentSection
                tourActivationSection
                tourSDRSection
            }
            .navigationTitle("Start Session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        tourManager.skip()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Start") {
                        // Intercepted — advance tour instead of creating real session
                        withAnimation(reduceMotion ? .none : .easeInOut(duration: 0.3)) {
                            // Advance to activeSession (skip past remaining sheet steps)
                            while tourManager.showSessionSheet {
                                tourManager.advance()
                            }
                        }
                        dismiss()
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                tourSheetGuideBubble
            }
        }
    }

    // MARK: Private

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: - Form Sections (pre-filled mock data)

    private var session: MockTourSession {
        tourManager.mockSession
    }

    // MARK: - Tour Guide Bubble (inside sheet)

    @ViewBuilder
    private var tourSheetGuideBubble: some View {
        if let message = tourManager.currentMessage {
            TourGuideBubble(
                message: message,
                stepIndex: tourManager.currentStep.rawValue,
                totalSteps: LoggerTourStep.allCases.count,
                onNext: {
                    withAnimation(reduceMotion ? .none : .easeInOut(duration: 0.3)) {
                        tourManager.advance()
                        // Dismiss sheet when advancing past sheet steps
                        if !tourManager.showSessionSheet {
                            dismiss()
                        }
                    }
                },
                onSkip: {
                    tourManager.skip()
                    dismiss()
                }
            )
        }
    }

    private var tourCallsignSection: some View {
        Section("Station") {
            HStack {
                Text("Callsign")
                Spacer()
                Text(session.callsign)
                    .foregroundStyle(.secondary)
                    .font(.body.monospaced())
            }
            HStack {
                Text("Grid")
                Spacer()
                Text(session.grid)
                    .foregroundStyle(.secondary)
                    .font(.body.monospaced())
            }
        }
    }

    private var tourModeSection: some View {
        Section("Mode") {
            HStack {
                ForEach(["CW", "SSB", "FT8"], id: \.self) { mode in
                    Text(mode)
                        .font(.subheadline.weight(.medium))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(mode == session.mode ? Color.accentColor : Color(.systemGray5))
                        .foregroundStyle(mode == session.mode ? .white : .primary)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                Spacer()
            }
        }
    }

    private var tourFrequencySection: some View {
        Section("Frequency") {
            HStack {
                Text("Frequency")
                Spacer()
                Text("\(session.formattedFrequency) MHz")
                    .foregroundStyle(.secondary)
                    .font(.body.monospacedDigit())
            }
        }
    }

    private var tourPowerSection: some View {
        Section("Power") {
            HStack {
                Text("Transmit Power")
                Spacer()
                Text("\(session.power)W")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var tourEquipmentSection: some View {
        Section("Equipment") {
            tourEquipmentRow("Radio", value: session.radio, icon: "radio")
            tourEquipmentRow("Antenna", value: session.antenna, icon: "antenna.radiowaves.left.and.right")
            tourEquipmentRow("Key", value: session.key, icon: "pianokeys")
        }
        .listRowBackground(
            tourManager.currentStep == .pickEquipment
                ? Color.accentColor.opacity(0.08)
                : nil
        )
    }

    private var tourActivationSection: some View {
        Section("Activation") {
            HStack {
                Text("Program")
                Spacer()
                Text("POTA")
                    .font(.subheadline.weight(.medium))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.green.opacity(0.2))
                    .clipShape(Capsule())
            }
            HStack {
                Text("Park Reference")
                Spacer()
                Text(session.park)
                    .foregroundStyle(.secondary)
                    .font(.body.monospaced())
            }
            HStack {
                Text("")
                Spacer()
                Text(session.parkName)
                    .font(.caption)
                    .foregroundStyle(.green)
            }
        }
        .listRowBackground(
            tourManager.currentStep == .setPark
                ? Color.green.opacity(0.08)
                : nil
        )
    }

    private var tourSDRSection: some View {
        Section("WebSDR") {
            HStack {
                Text("Auto-start Recording")
                Spacer()
                Image(systemName: "checkmark")
                    .foregroundStyle(.green)
            }
            HStack {
                Text("Receiver")
                Spacer()
                Text("KiwiSDR Tucson")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func tourEquipmentRow(
        _ label: String,
        value: String,
        icon: String
    ) -> some View {
        HStack {
            Label(label, systemImage: icon)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}
