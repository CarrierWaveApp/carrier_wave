import CarrierWaveCore
import SwiftUI

// MARK: - ParsedFieldSummary

/// Real-time display of parsed fields below the entry text field.
struct ParsedFieldSummary: View {
    // MARK: Internal

    let result: QuickEntryResult?
    let radioManager: RadioManager
    var dxccEntity: String?
    var neededStatus: NeededStatus = .unknown
    var callsignInfo: CallsignInfo?
    var poloEntry: PoloNotesEntry?
    var combinedEmoji: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            parsedFieldsRow
            callsignInfoRow
        }
        .font(.caption)
    }

    // MARK: Private

    private var hasCallsignDetails: Bool {
        callsignInfo?.license != nil
            || callsignInfo?.qrzResult != nil
            || poloEntry != nil
            || combinedEmoji != nil
            || (callsignInfo?.previousQSOCount ?? 0) > 0
    }

    private var neededChipColor: Color {
        switch neededStatus {
        case .newEntity: .red
        case .newBandSlot: .orange
        case .workedNotConfirmed: .gray
        case .confirmed: .green
        case .unknown: .clear
        }
    }

    private var parsedFieldsRow: some View {
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

                if let entity = dxccEntity {
                    FieldChip(label: "DXCC", value: entity, color: .cyan)
                }

                if neededStatus != .unknown {
                    FieldChip(
                        label: neededStatus.label,
                        value: "",
                        color: neededChipColor
                    )
                }
            }

            Spacer()
        }
    }

    @ViewBuilder
    private var callsignInfoRow: some View {
        if hasCallsignDetails {
            HStack(spacing: 8) {
                if let emoji = combinedEmoji {
                    Text(emoji)
                }

                if let name = callsignInfo?.operatorName {
                    Text(name)
                        .fontWeight(.medium)
                }

                if let location = callsignInfo?.location {
                    Text(location)
                        .foregroundStyle(.secondary)
                }

                if let licClass = callsignInfo?.licenseClass {
                    Text(licClass)
                        .foregroundStyle(.secondary)
                }

                if let prevCall = callsignInfo?.previousCallsign {
                    Text("ex \(prevCall)")
                        .foregroundStyle(.orange)
                }

                if let entry = poloEntry {
                    poloNoteText(entry)
                }

                if let info = callsignInfo, info.previousQSOCount > 0 {
                    previousQSOText(info)
                }

                if let changeNote = callsignInfo?.callsignChangeNote {
                    Text("· \(changeNote)")
                        .foregroundStyle(.orange)
                }

                Spacer()
            }
            .lineLimit(1)
        }
    }

    @ViewBuilder
    private func poloNoteText(_ entry: PoloNotesEntry) -> some View {
        if let name = entry.name, callsignInfo?.operatorName == nil {
            Text(name)
                .fontWeight(.medium)
        }

        if let note = entry.note {
            Text("· \(note)")
                .foregroundStyle(.secondary)
        }
    }

    private func previousQSOText(_ info: CallsignInfo) -> some View {
        let lastText = info.lastWorked.map {
            $0.formatted(.dateTime.month(.abbreviated).day())
        } ?? ""
        return Text("· \(info.previousQSOCount) prev \(lastText)")
            .foregroundStyle(.tertiary)
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
