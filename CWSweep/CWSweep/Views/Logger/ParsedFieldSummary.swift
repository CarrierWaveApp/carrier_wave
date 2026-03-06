import CarrierWaveCore
import SwiftUI

// MARK: - ParsedFieldSummary

/// Real-time display of parsed fields below the entry text field.
struct ParsedFieldSummary: View {
    let result: QuickEntryResult?
    let radioManager: RadioManager
    var contestResult: ContestParseResult?
    var dupeStatus: DupeStatus?

    var body: some View {
        HStack(spacing: 12) {
            if let result {
                FieldChip(label: "Call", value: result.callsign.uppercased(), color: .blue)

                if let freq = result.frequency {
                    FieldChip(label: "Freq", value: String(format: "%.3f", freq), color: .green)
                } else if radioManager.frequency > 0 {
                    FieldChip(
                        label: "Freq",
                        value: String(format: "%.3f", radioManager.frequency),
                        color: .green.opacity(0.5)
                    )
                }

                if !radioManager.mode.isEmpty {
                    FieldChip(label: "Mode", value: radioManager.mode, color: .purple)
                }

                if let sent = result.rstSent {
                    FieldChip(label: "Sent", value: sent, color: .orange)
                }

                if let rcvd = result.rstReceived {
                    FieldChip(label: "Rcvd", value: rcvd, color: .orange)
                }

                if let park = result.theirPark {
                    FieldChip(label: "Park", value: park.uppercased(), color: .green)
                }

                if let grid = result.theirGrid {
                    FieldChip(label: "Grid", value: grid.uppercased(), color: .teal)
                }

                if let state = result.state {
                    FieldChip(label: "State", value: state.uppercased(), color: .indigo)
                }

                // Contest exchange fields
                if let contestResult {
                    ForEach(Array(contestResult.fields.sorted(by: { $0.key < $1.key })), id: \.key) { key, value in
                        FieldChip(label: key.capitalized, value: value, color: .mint)
                    }

                    if let serial = contestResult.serialReceived {
                        FieldChip(label: "Serial", value: "#\(serial)", color: .mint)
                    }
                }

                // Dupe status chip
                if let dupeStatus {
                    switch dupeStatus {
                    case let .newMultiplier(value, _):
                        FieldChip(label: "Mult", value: value, color: .green)
                    case .newStation:
                        EmptyView()
                    case .dupe:
                        FieldChip(label: "DUPE", value: "!", color: .red)
                    }
                }
            }

            Spacer()
        }
        .font(.caption)
    }
}

// MARK: - FieldChip

struct FieldChip: View {
    let label: String
    let value: String
    let color: Color

    var body: some View {
        HStack(spacing: 2) {
            Text(label)
                .foregroundStyle(.secondary)
            Text(value)
                .fontWeight(.medium)
                .foregroundStyle(color)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(color.opacity(0.1), in: Capsule())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }
}
