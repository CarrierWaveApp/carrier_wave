//
//  FT8SetupWizardView.swift
//  CarrierWave
//

import CarrierWaveCore
import SwiftUI

// MARK: - FT8SetupWizardView

/// Multi-step setup wizard for first-time FT8 configuration.
/// Guides through audio connection, radio setup, and audio verification.
struct FT8SetupWizardView: View {
    // MARK: Internal

    @Binding var isPresented: Bool

    @AppStorage("ft8SetupComplete") var ft8SetupComplete = false
    @AppStorage("ft8ConnectionType") var connectionType = "usb"
    @AppStorage("ft8DefaultBand") var selectedBand = "20m"

    @State var currentStep = 0
    @State var checklistItems: Set<String> = []

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                stepIndicator

                TabView(selection: $currentStep) {
                    audioConnectionStep.tag(0)
                    radioSetupStep.tag(1)
                    verifyAudioStep.tag(2)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.easeInOut(duration: 0.3), value: currentStep)

                navigationButtons
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("FT8 Setup")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Skip") {
                        isPresented = false
                    }
                }
            }
        }
    }

    // MARK: Private

    private var stepIndicator: some View {
        HStack(spacing: 8) {
            ForEach(0 ..< 3, id: \.self) { step in
                Capsule()
                    .fill(step <= currentStep ? Color.blue : Color(.systemGray4))
                    .frame(height: 4)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(currentStep + 1) of 3")
    }

    private var navigationButtons: some View {
        HStack {
            if currentStep > 0 {
                Button {
                    currentStep -= 1
                } label: {
                    Label("Back", systemImage: "chevron.left")
                        .font(.subheadline.weight(.medium))
                }
                .buttonStyle(.bordered)
            }

            Spacer()

            if currentStep < 2 {
                Button {
                    currentStep += 1
                } label: {
                    Label("Next", systemImage: "chevron.right")
                        .font(.subheadline.weight(.medium))
                        .labelStyle(TrailingIconLabelStyle())
                }
                .buttonStyle(.borderedProminent)
            } else {
                Button {
                    ft8SetupComplete = true
                    isPresented = false
                } label: {
                    Text("Get Started")
                        .font(.headline)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
            }
        }
        .padding()
        .background(Color(.systemGroupedBackground))
    }
}

// MARK: - Step 1: Audio Connection

extension FT8SetupWizardView {
    var audioConnectionStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Audio Connection")
                    .font(.title2.weight(.bold))

                Text(
                    "FT8 requires a direct audio connection between "
                        + "your iPhone and radio. Choose your connection method:"
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)

                connectionCard(
                    id: "usb",
                    icon: "cable.connector",
                    title: "USB Audio Interface",
                    description: "Digirig, SignaLink, or similar USB interface",
                    recommended: true
                )

                connectionCard(
                    id: "trrs",
                    icon: "cable.coaxial",
                    title: "TRRS Cable",
                    description: "Direct cable between radio and phone audio jack",
                    recommended: false
                )

                connectionCard(
                    id: "speaker",
                    icon: "speaker.wave.2",
                    title: "Speaker-Mic",
                    description: "Hold phone near radio speaker/mic. Not recommended for TX.",
                    recommended: false
                )
            }
            .padding()
        }
    }

    private func connectionCard(
        id: String,
        icon: String,
        title: String,
        description: String,
        recommended: Bool
    ) -> some View {
        Button {
            connectionType = id
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(connectionType == id ? Color.blue : Color.secondary)
                    .frame(width: 32)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(title)
                            .font(.subheadline.weight(.semibold))

                        if recommended {
                            Text("Recommended")
                                .font(.caption2.weight(.bold))
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Color.green.opacity(0.2))
                                .clipShape(RoundedRectangle(cornerRadius: 3))
                        }
                    }

                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: connectionType == id ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(connectionType == id ? Color.blue : Color(.systemGray4))
                    .accessibilityHidden(true)
            }
            .padding()
            .background(
                connectionType == id
                    ? Color.blue.opacity(0.08)
                    : Color(.systemGray6)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(
                        connectionType == id ? Color.blue.opacity(0.3) : .clear,
                        lineWidth: 1.5
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title). \(description)\(recommended ? ". Recommended" : "")")
        .accessibilityAddTraits(connectionType == id ? [.isSelected] : [])
    }
}

// MARK: - Step 2: Radio Setup

extension FT8SetupWizardView {
    var radioSetupStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Radio Setup")
                    .font(.title2.weight(.bold))

                Text("Configure your radio with these settings before starting FT8:")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                bandSelectionRow

                VStack(spacing: 0) {
                    checklistRow(id: "mode", label: "Mode: USB (Upper Sideband)")
                    Divider().padding(.leading, 44)
                    checklistRow(id: "frequency", label: dialFrequencyLabel)
                    Divider().padding(.leading, 44)
                    checklistRow(id: "power", label: "Power: 5\u{2013}20W recommended for FT8")
                    Divider().padding(.leading, 44)
                    checklistRow(id: "vox", label: "VOX: Enable if using audio interface")
                    Divider().padding(.leading, 44)
                    checklistRow(id: "agc", label: "AGC: OFF or slow")
                    Divider().padding(.leading, 44)
                    checklistRow(id: "filter", label: "Filter: Widest available (2.4 kHz+)")
                }
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding()
        }
    }

    private var dialFrequencyLabel: String {
        if let freq = FT8Constants.dialFrequency(forBand: selectedBand) {
            return "Frequency: \(String(format: "%.3f", freq)) MHz (\(selectedBand))"
        }
        return "Frequency: Select band above"
    }

    private var bandSelectionRow: some View {
        HStack {
            Text("Default Band")
                .font(.subheadline.weight(.semibold))

            Spacer()

            Picker("Band", selection: $selectedBand) {
                ForEach(FT8Constants.supportedBands, id: \.self) { band in
                    if let freq = FT8Constants.dialFrequency(forBand: band) {
                        Text("\(band) (\(String(format: "%.3f", freq)))")
                            .tag(band)
                    }
                }
            }
            .pickerStyle(.menu)
        }
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func checklistRow(id: String, label: String) -> some View {
        Button {
            if checklistItems.contains(id) {
                checklistItems.remove(id)
            } else {
                checklistItems.insert(id)
            }
        } label: {
            HStack(spacing: 12) {
                Image(
                    systemName: checklistItems.contains(id)
                        ? "checkmark.circle.fill"
                        : "circle"
                )
                .font(.title3)
                .foregroundStyle(
                    checklistItems.contains(id)
                        ? .green
                        : Color(.systemGray3)
                )
                .accessibilityHidden(true)

                Text(label)
                    .font(.subheadline)
                    .foregroundStyle(Color(.label))

                Spacer()
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
            .frame(minHeight: 44)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityValue(checklistItems.contains(id) ? "Checked" : "Unchecked")
    }
}

// MARK: - Step 3: Verify Audio

extension FT8SetupWizardView {
    var verifyAudioStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Verify Audio")
                    .font(.title2.weight(.bold))

                Text(
                    "After dismissing this wizard, your FT8 session "
                        + "will start automatically. Tune your radio to "
                        + "the FT8 frequency and check for signals."
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)

                verifyInfoCard(
                    icon: "antenna.radiowaves.left.and.right",
                    title: "Tune to FT8 Frequency",
                    description: dialFrequencyLabel
                )

                verifyInfoCard(
                    icon: "waveform",
                    title: "Watch for Decodes",
                    description: "If audio is connected, decoded callsigns will "
                        + "appear in the session view within 15 seconds."
                )

                verifyInfoCard(
                    icon: "slider.horizontal.3",
                    title: "Adjust Audio Levels",
                    description: "Set radio volume so the audio meter shows "
                        + "moderate levels. Too high causes distortion; "
                        + "too low misses weak signals."
                )

                tipsCard
            }
            .padding()
        }
    }

    private func verifyInfoCard(
        icon: String,
        title: String,
        description: String
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(Color.blue)
                .frame(width: 32)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))

                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var tipsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Tips", systemImage: "lightbulb")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.orange)

            Text(
                "FT8 signals are loudest around the start of each "
                    + "15-second cycle. Activity peaks during "
                    + "gray-line and contest periods."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding()
        .background(Color.orange.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - TrailingIconLabelStyle

/// Label style that places the icon after the text (for "Next >" buttons)
private struct TrailingIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.title
            configuration.icon
        }
    }
}
