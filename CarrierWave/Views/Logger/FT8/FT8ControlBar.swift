//
//  FT8ControlBar.swift
//  CarrierWave
//

import CarrierWaveData
import SwiftUI

struct FT8ControlBar: View {
    // MARK: Internal

    let isReceiving: Bool
    @Binding var operatingMode: FT8OperatingMode

    let qsoCount: Int
    let txState: FT8TXState
    let parkReference: String?
    let onStart: () -> Void
    let onStop: () -> Void
    var onRequestCQ: ((String?) -> Void)?

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                modeButton("Listen", mode: .listen, systemImage: "headphones")
                    .disabled(!isReceiving)

                cqMenu
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
                if txState != .idle {
                    FT8TXStatusLine(txState: txState)
                } else if parkReference != nil {
                    potaCounter
                } else {
                    Label("\(qsoCount) QSOs", systemImage: "list.bullet")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal)
        }
        .padding(.vertical, 8)
        .background(Color(.systemBackground))
    }

    // MARK: Private

    private var isCQSelected: Bool {
        if case .callCQ = operatingMode {
            return true
        }
        return false
    }

    private var cqLabel: String {
        if case let .callCQ(modifier) = operatingMode, let modifier {
            return "CQ \(modifier)"
        }
        return "Call CQ"
    }

    private var cqMenu: some View {
        Menu {
            Button("CQ") { requestCQ(modifier: nil) }
            Button("CQ POTA") { requestCQ(modifier: "POTA") }
            Button("CQ DX") { requestCQ(modifier: "DX") }
            Button("CQ SOTA") { requestCQ(modifier: "SOTA") }
        } label: {
            Label(cqLabel, systemImage: "antenna.radiowaves.left.and.right")
                .font(.caption.bold())
        }
        .buttonStyle(.bordered)
        .tint(isCQSelected ? .accentColor : .secondary)
    }

    @ViewBuilder
    private var potaCounter: some View {
        let isValid = qsoCount >= 10
        HStack(spacing: 4) {
            if isValid {
                Text("\(qsoCount)")
                    .font(.caption.bold().monospacedDigit())
                    .foregroundStyle(.green)
                Image(systemName: "tree.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
            } else {
                Text("\(qsoCount)/10")
                    .font(.caption.bold().monospacedDigit())
                    .foregroundStyle(.secondary)
                Image(systemName: "tree.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func modeButton(
        _ title: String,
        mode: FT8OperatingMode,
        systemImage: String
    ) -> some View {
        Button {
            operatingMode = mode
        } label: {
            Label(title, systemImage: systemImage)
                .font(.caption.bold())
        }
        .buttonStyle(.bordered)
        .tint(isSelected(mode) ? .accentColor : .secondary)
    }

    private func requestCQ(modifier: String?) {
        if let onRequestCQ {
            onRequestCQ(modifier)
        } else {
            operatingMode = .callCQ(modifier: modifier)
        }
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
