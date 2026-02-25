//
//  FT8ActiveQSOCard.swift
//  CarrierWave
//

import CarrierWaveCore
import SwiftUI

struct FT8ActiveQSOCard: View {
    // MARK: Internal

    let stateMachine: FT8QSOStateMachine

    var body: some View {
        if let call = stateMachine.theirCallsign, stateMachine.state != .idle {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Active QSO")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(stateLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Text(call)
                        .font(.title3.bold())
                    if let grid = stateMachine.theirGrid {
                        Text(grid)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let report = stateMachine.theirReport {
                        Text("\(report) dB")
                            .font(.body.monospacedDigit())
                    }
                }

                ProgressView(value: stateProgress)
                    .tint(.orange)
            }
            .padding()
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal)
        }
    }

    // MARK: Private

    private var stateLabel: String {
        switch stateMachine.state {
        case .idle: "Idle"
        case .calling: "Calling..."
        case .reportSent: "Report Sent"
        case .reportReceived: "Confirming"
        case .complete: "Complete"
        }
    }

    private var stateProgress: Double {
        switch stateMachine.state {
        case .idle: 0
        case .calling: 0.2
        case .reportSent: 0.5
        case .reportReceived: 0.8
        case .complete: 1.0
        }
    }
}
