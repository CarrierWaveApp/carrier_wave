//
//  FT8ControlBar.swift
//  CarrierWave
//

import SwiftUI

struct FT8ControlBar: View {
    // MARK: Internal

    let isReceiving: Bool
    @Binding var operatingMode: FT8OperatingMode

    let qsoCount: Int
    let parkReference: String?
    let onStart: () -> Void
    let onStop: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                modeButton("Listen", mode: .listen, systemImage: "headphones")
                    .disabled(!isReceiving)
                modeButton(
                    "Call CQ",
                    mode: .callCQ(modifier: nil),
                    systemImage: "antenna.radiowaves.left.and.right"
                )
                .disabled(!isReceiving)

                if isReceiving {
                    Button(action: onStop) {
                        Label("Stop", systemImage: "stop.fill")
                            .font(.caption.bold())
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                } else {
                    Button(action: onStart) {
                        Label("Start", systemImage: "play.fill")
                            .font(.caption.bold())
                    }
                    .buttonStyle(.bordered)
                    .tint(.green)
                }
            }

            HStack {
                Label("\(qsoCount) QSOs", systemImage: "list.bullet")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let park = parkReference {
                    Spacer()
                    Text(park)
                        .font(.caption.bold())
                        .foregroundStyle(.orange)
                }
                Spacer()
            }
            .padding(.horizontal)
        }
        .padding(.vertical, 8)
        .background(Color(.systemBackground))
    }

    // MARK: Private

    private func modeButton(
        _ title: String,
        mode: FT8OperatingMode,
        systemImage: String
    ) -> some View {
        Button {
            // When re-selecting callCQ, preserve the current modifier
            if case .callCQ = mode, case .callCQ = operatingMode {
                return
            }
            operatingMode = mode
        } label: {
            Label(title, systemImage: systemImage)
                .font(.caption.bold())
        }
        .buttonStyle(.bordered)
        .tint(isSelected(mode) ? .accentColor : .secondary)
    }

    private func isSelected(_ mode: FT8OperatingMode) -> Bool {
        switch (operatingMode, mode) {
        case (.listen, .listen): true
        case (.callCQ, .callCQ): true
        case (.searchAndPounce, .searchAndPounce): true
        default: false
        }
    }
}
