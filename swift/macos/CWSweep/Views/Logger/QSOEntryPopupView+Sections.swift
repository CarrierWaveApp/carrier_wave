import CarrierWaveCore
import CarrierWaveData
import SwiftData
import SwiftUI

// MARK: - QSOEntryPopupView + View Sections

extension QSOEntryPopupView {
    var headerSection: some View {
        HStack(spacing: 12) {
            Image(systemName: "plus.message")
                .font(.system(size: 24))
                .foregroundStyle(.blue)

            VStack(alignment: .leading, spacing: 2) {
                Text("Add QSO")
                    .font(.headline)
                if logCount > 0 {
                    Text("\(logCount) logged this session")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if let last = lastLoggedCallsign {
                Label("Last: \(last)", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
            }
        }
        .padding()
    }

    var quickEntrySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Quick Entry")
                .font(.subheadline.bold())
                .foregroundStyle(.secondary)

            HStack {
                Image(systemName: "chevron.right")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)

                TextField(
                    "Callsign RST Freq Mode Park...",
                    text: $quickEntryText
                )
                .textFieldStyle(.plain)
                .font(.system(.body, design: .monospaced))
                .focused($isQuickEntryFocused)
                .onSubmit { logQSO() }
                .onChange(of: quickEntryText) { _, newValue in
                    parseQuickEntry(newValue)
                }
                .onKeyPress(.escape) {
                    clearAll()
                    return .handled
                }
                .onKeyPress(.upArrow) {
                    recallHistory(direction: .up)
                    return .handled
                }
                .onKeyPress(.downArrow) {
                    recallHistory(direction: .down)
                    return .handled
                }
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(.background)
                    .shadow(color: .black.opacity(0.1), radius: 2, y: 1)
            )

            if !quickEntryText.isEmpty, let result = parsedResult {
                parsedFieldChips(result)
            }
        }
    }

    @ViewBuilder
    var callsignInfoSection: some View {
        if hasCallsignDetails {
            VStack(alignment: .leading, spacing: 4) {
                Divider()
                HStack(spacing: 8) {
                    if let emoji = combinedEmoji {
                        Text(emoji)
                    }
                    if let opName = callsignInfo?.operatorName {
                        Text(opName).fontWeight(.medium)
                    }
                    if let location = callsignInfo?.location {
                        Text(location).foregroundStyle(.secondary)
                    }
                    if let licClass = callsignInfo?.licenseClass {
                        Text(licClass).foregroundStyle(.secondary)
                    }
                    if let prevCall = callsignInfo?.previousCallsign {
                        Text("ex \(prevCall)")
                            .foregroundStyle(.orange)
                    }
                    if let entry = poloEntry, let note = entry.note {
                        Text("· \(note)").foregroundStyle(.secondary)
                    }
                    if let info = callsignInfo, info.previousQSOCount > 0 {
                        Text("· \(info.previousQSOCount) prev")
                            .foregroundStyle(.tertiary)
                    }
                    if let changeNote = callsignInfo?.callsignChangeNote {
                        Text("· \(changeNote)")
                            .foregroundStyle(.orange)
                    }
                    ForEach(memberships, id: \.sourceSlug) { membership in
                        SweepMembershipChip(membership: membership)
                    }
                    Spacer()
                }
                .font(.caption)
            }
        } else if let status = lookupStatus {
            VStack(alignment: .leading, spacing: 4) {
                Divider()
                Text(status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    var footerSection: some View {
        HStack {
            Button("Clear") { clearAll() }
                .keyboardShortcut(.escape, modifiers: [])

            Spacer()

            Button("Log QSO") { logQSO() }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return, modifiers: [])
                .disabled(!canLog)
        }
        .padding()
    }

    func parsedFieldChips(
        _ result: QuickEntryResult
    ) -> some View {
        HStack(spacing: 8) {
            FieldChip(
                label: "Call",
                value: result.callsign.uppercased(),
                color: .blue
            )
            if let freq = result.frequency {
                FieldChip(
                    label: "Freq",
                    value: String(format: "%.3f", freq),
                    color: .green
                )
            }
            if let sent = result.rstSent {
                FieldChip(label: "Sent", value: sent, color: .orange)
            }
            if let rcvd = result.rstReceived {
                FieldChip(label: "Rcvd", value: rcvd, color: .orange)
            }
            if let park = result.theirPark {
                FieldChip(
                    label: "Park",
                    value: park.uppercased(),
                    color: .green
                )
            }
            if let grid = result.theirGrid {
                FieldChip(
                    label: "Grid",
                    value: grid.uppercased(),
                    color: .teal
                )
            }
            if let entity = entryDXCCEntity {
                FieldChip(label: "DXCC", value: entity, color: .cyan)
            }
            Spacer()
        }
        .font(.caption)
    }
}
