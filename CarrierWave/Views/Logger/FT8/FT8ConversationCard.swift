//
//  FT8ConversationCard.swift
//  CarrierWave
//

import CarrierWaveData
import SwiftUI

// MARK: - FT8ConversationCard

struct FT8ConversationCard: View {
    // MARK: Internal

    let stateMachine: FT8QSOStateMachine
    let txEvents: [FT8TXEvent]
    let rxMessages: [FT8DecodeResult]
    let distanceMiles: Int?
    let dxccEntity: String?
    let txAudioFrequency: Double
    let isTXHalted: Bool
    let onHaltResume: () -> Void
    let onAbort: () -> Void
    let onOverride: (String) -> Void

    var body: some View {
        if let call = stateMachine.theirCallsign,
           stateMachine.state != .idle
        {
            VStack(alignment: .leading, spacing: 8) {
                headerSection(call)
                transcriptSection
                nextTXSection
                controlsSection
            }
            .padding(12)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    // MARK: Private

    private struct TranscriptEntry: Identifiable {
        let id = UUID()
        let message: String
        let timestamp: Date
        let isTX: Bool
    }

    // MARK: - Helpers

    private var stepIndex: Int {
        switch stateMachine.state {
        case .idle: 0
        case .calling: 1
        case .reportSent: 2
        case .reportReceived: 3
        case .completing,
             .complete: 4
        }
    }

    private var totalSteps: Int {
        4
    }

    // MARK: - Transcript

    private var transcriptSection: some View {
        let entries = buildTranscript()
        return VStack(spacing: 0) {
            ForEach(entries.suffix(4)) { entry in
                FT8TranscriptRow(
                    message: entry.message,
                    timestamp: entry.timestamp,
                    isTX: entry.isTX
                )
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    // MARK: - Next TX

    private var nextTXSection: some View {
        let options = buildOverrideOptions()
        return FT8NextTXRow(
            nextMessage: stateMachine.nextTXMessage,
            stepIndex: stepIndex,
            totalSteps: totalSteps,
            isOverrideActive: false,
            allMessages: options,
            onOverride: onOverride
        )
    }

    // MARK: - Controls

    private var controlsSection: some View {
        HStack {
            Spacer()
            Button(isTXHalted ? "Resume TX" : "Halt TX", action: onHaltResume)
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Abort QSO", action: onAbort)
                .font(.caption)
                .foregroundStyle(.red)
        }
    }

    // MARK: - Header

    private func headerSection(_ call: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(call)
                    .font(.headline.monospaced())

                if let grid = stateMachine.theirGrid {
                    Text(grid)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }

                if let entity = dxccEntity {
                    Text("\u{00B7}")
                        .foregroundStyle(.tertiary)
                    Text(entity)
                        .font(.caption)
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
            }

            HStack(spacing: 6) {
                if let report = stateMachine.theirReport {
                    Text("\(report) dB")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Text("\(Int(txAudioFrequency)) Hz")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func buildTranscript() -> [TranscriptEntry] {
        var entries: [TranscriptEntry] = []

        for tx in txEvents {
            entries.append(TranscriptEntry(
                message: tx.message,
                timestamp: tx.timestamp,
                isTX: true
            ))
        }
        for rx in rxMessages {
            entries.append(TranscriptEntry(
                message: rx.rawText,
                timestamp: Date(),
                isTX: false
            ))
        }

        return entries.sorted { $0.timestamp < $1.timestamp }
    }

    private func buildOverrideOptions() -> [FT8NextTXRow.MessageOption] {
        guard let their = stateMachine.theirCallsign else {
            return []
        }
        let my = stateMachine.myCallsign
        let grid = stateMachine.myGrid
        let autoMsg = stateMachine.nextTXMessage

        var options: [FT8NextTXRow.MessageOption] = []

        if let msg = autoMsg {
            options.append(.init(
                message: msg,
                label: "auto",
                isAutoSelected: true
            ))
        }

        let gridMsg = "\(their) \(my) \(grid)"
        if gridMsg != autoMsg {
            options.append(.init(
                message: gridMsg,
                label: "grid",
                isAutoSelected: false
            ))
        }

        let rr73Msg = "\(their) \(my) RR73"
        if rr73Msg != autoMsg {
            options.append(.init(
                message: rr73Msg,
                label: "end",
                isAutoSelected: false
            ))
        }

        let endMsg = "\(their) \(my) 73"
        if endMsg != autoMsg {
            options.append(.init(
                message: endMsg,
                label: "bye",
                isAutoSelected: false
            ))
        }

        return options
    }
}
