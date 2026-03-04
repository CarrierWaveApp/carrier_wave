//
//  FT8ActiveQSOCard.swift
//  CarrierWave
//

import CarrierWaveData
import SwiftUI

struct FT8ActiveQSOCard: View {
    // MARK: Internal

    let stateMachine: FT8QSOStateMachine
    let distanceMiles: Int?
    let dxccEntity: String?
    let onAbort: () -> Void

    var body: some View {
        if let call = stateMachine.theirCallsign,
           stateMachine.state != .idle,
           stateMachine.state != .complete
        {
            VStack(alignment: .leading, spacing: 6) {
                headerLine(call)
                stepIndicator
                HStack {
                    Spacer()
                    Button("Abort", action: onAbort)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            .padding(12)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    // MARK: Private

    private var stepIndex: Int {
        switch stateMachine.state {
        case .idle: 0
        case .calling: 1
        case .reportSent: 2
        case .reportReceived,
             .complete: 3
        }
    }

    private var stateLabel: String {
        switch stateMachine.state {
        case .idle: "Idle"
        case .calling: "Calling..."
        case .reportSent: "Report Sent"
        case .reportReceived: "Confirming..."
        case .complete: "Complete!"
        }
    }

    private var stepIndicator: some View {
        HStack(spacing: 4) {
            stepDot(label: "Call", filled: stepIndex >= 1)
            stepConnector
            stepDot(label: "Rpt", filled: stepIndex >= 2)
            stepConnector
            stepDot(label: "73", filled: stepIndex >= 3)
        }
    }

    private var stepConnector: some View {
        Rectangle()
            .fill(Color(.systemGray4))
            .frame(height: 1)
            .frame(maxWidth: 20)
            .padding(.bottom, 12)
    }

    private func headerLine(_ call: String) -> some View {
        HStack {
            Text(call)
                .font(.title3.bold().monospaced())

            if let grid = stateMachine.theirGrid {
                Text(grid)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }

            if let report = stateMachine.theirReport {
                Text("\(report) dB")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            if let miles = distanceMiles {
                Text("\u{00B7}")
                    .foregroundStyle(.tertiary)
                Text("\(miles.formatted()) mi")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(stateLabel)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func stepDot(label: String, filled: Bool) -> some View {
        VStack(spacing: 2) {
            RoundedRectangle(cornerRadius: 2)
                .fill(filled ? Color.orange : Color(.systemGray4))
                .frame(width: 12, height: 12)
            Text(label)
                .font(.system(size: 8))
                .foregroundStyle(filled ? .primary : .tertiary)
        }
    }
}
