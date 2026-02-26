//
//  FT8DebugPanel.swift
//  CarrierWave
//

import SwiftUI

/// Compact always-visible debug panel showing audio level, decode stats, and input picker.
struct FT8DebugPanel: View {
    // MARK: Internal

    let ft8Manager: FT8SessionManager

    var body: some View {
        VStack(spacing: 6) {
            audioLevelMeter
            HStack {
                decodeStats
                Spacer()
                inputPicker
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(.secondarySystemBackground))
    }

    // MARK: Private

    private var meterGradient: LinearGradient {
        LinearGradient(
            colors: [.green, .yellow, .orange, .red],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    private var selectedInputName: String {
        ft8Manager.availableAudioInputs.first(where: \.isSelected)?.portName ?? "Default"
    }

    private var audioLevelMeter: some View {
        GeometryReader { geo in
            let level = CGFloat(ft8Manager.audioLevel)
            // Scale RMS (typically 0-0.3) to fill the bar
            let scaled = min(level * 4, 1.0)

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color(.systemGray5))

                RoundedRectangle(cornerRadius: 3)
                    .fill(meterGradient)
                    .frame(width: scaled * geo.size.width)
                    .animation(.easeOut(duration: 0.08), value: scaled)
            }
        }
        .frame(height: 8)
    }

    private var decodeStats: some View {
        HStack(spacing: 12) {
            Label(
                "\(ft8Manager.currentCycleDecodes.count)",
                systemImage: "waveform"
            )
            Label(
                "\(ft8Manager.decodeResults.count)",
                systemImage: "list.number"
            )
        }
        .font(.caption.monospacedDigit())
        .foregroundStyle(.secondary)
    }

    private var inputPicker: some View {
        Menu {
            ForEach(ft8Manager.availableAudioInputs) { input in
                Button {
                    ft8Manager.selectAudioInput(uid: input.uid)
                } label: {
                    HStack {
                        Text(input.portName)
                        if input.isSelected {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            Label(selectedInputName, systemImage: "mic")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
