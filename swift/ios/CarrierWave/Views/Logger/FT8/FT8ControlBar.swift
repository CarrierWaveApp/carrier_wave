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
    let previousDayQSOCount: Int?
    let txState: FT8TXState
    let parkReference: String?
    /// CQ modifier inferred from the active session's activation/contest type
    /// (e.g. "POTA", "SOTA", "WWFF", "TOTA", "TEST"). `nil` when there is no
    /// active activation; in that case the button calls a plain "CQ".
    let suggestedCQModifier: String?
    let onStart: () -> Void
    let onStop: () -> Void
    var onRequestCQ: ((String?) -> Void)?

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                modeButton("Listen", mode: .listen, systemImage: "headphones")
                    .disabled(!isReceiving)

                cqButton
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
        if let suggestedCQModifier {
            return "Call CQ \(suggestedCQModifier)"
        }
        return "Call CQ"
    }

    private var cqButton: some View {
        Button {
            deferRequestCQ(modifier: suggestedCQModifier)
        } label: {
            Label(cqLabel, systemImage: "antenna.radiowaves.left.and.right")
                .font(.caption.bold())
        }
        .buttonStyle(.bordered)
        .tint(isCQSelected ? .accentColor : .secondary)
    }

    private var potaCounter: some View {
        HStack(spacing: 6) {
            if let prevCount = previousDayQSOCount {
                previousDayBadge(count: prevCount)
                Text("·")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            currentDayBadge
        }
    }

    @ViewBuilder
    private var currentDayBadge: some View {
        let isValid = qsoCount >= 10
        let label = previousDayQSOCount != nil ? "Today: " : ""
        HStack(spacing: 4) {
            if isValid {
                Text("\(label)\(qsoCount)")
                    .font(.caption.bold().monospacedDigit())
                    .foregroundStyle(.green)
                Image(systemName: "tree.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
            } else {
                Text("\(label)\(qsoCount)/10")
                    .font(.caption.bold().monospacedDigit())
                    .foregroundStyle(.secondary)
                Image(systemName: "tree.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func previousDayBadge(count: Int) -> some View {
        HStack(spacing: 4) {
            Text("Yesterday: \(count)")
                .font(.caption.bold().monospacedDigit())
                .foregroundStyle(count >= 10 ? .green : .orange)
            if count >= 10 {
                Image(systemName: "checkmark.circle.fill")
                    .font(.caption2)
                    .foregroundStyle(.green)
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

    /// Defer the CQ request to the next main-actor turn. Without this, the
    /// state mutation that drives the channel-picker sheet races with the
    /// Menu's own dismissal animation on iOS 18+ and the sheet silently fails
    /// to present.
    private func deferRequestCQ(modifier: String?) {
        Task { @MainActor in
            if let onRequestCQ {
                onRequestCQ(modifier)
            } else {
                operatingMode = .callCQ(modifier: modifier)
            }
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
