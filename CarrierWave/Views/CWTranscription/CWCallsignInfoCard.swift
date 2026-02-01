import SwiftUI

// MARK: - CWCallsignInfoCard

/// Displays callsign information in an expandable card format
struct CWCallsignInfoCard: View {
    // MARK: Internal

    let info: CallsignInfo

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header row with callsign and source badge
            HStack {
                // Emoji (if from Polo notes)
                if let emoji = info.emoji {
                    Text(emoji)
                        .font(.title3)
                }

                Text(info.callsign)
                    .font(.headline.monospaced())

                // License class badge
                if let licenseClass = info.licenseClass {
                    Text(licenseClass)
                        .font(.caption2.weight(.medium))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.2))
                        .clipShape(Capsule())
                }

                Spacer()

                // Source indicator
                sourceBadge
            }

            // Name
            if let name = info.displayName {
                Text(name)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
            }

            // Note from Polo notes
            if let note = info.note {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Location info (grid, QTH)
            if info.grid != nil || info.fullLocation != nil {
                HStack(spacing: 12) {
                    if let grid = info.grid {
                        Label(grid, systemImage: "grid")
                            .font(.caption)
                    }

                    if let location = info.fullLocation {
                        Label(location, systemImage: "mappin")
                            .font(.caption)
                            .lineLimit(1)
                    }
                }
                .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: Private

    @ViewBuilder
    private var sourceBadge: some View {
        switch info.source {
        case .poloNotes:
            Image(systemName: "list.bullet.rectangle")
                .font(.caption)
                .foregroundStyle(.blue)

        case .qrz:
            Text("QRZ")
                .font(.caption2.weight(.medium))
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(Color.orange.opacity(0.2))
                .foregroundStyle(.orange)
                .clipShape(RoundedRectangle(cornerRadius: 4))

        case .hamdb:
            Text("HamDB")
                .font(.caption2.weight(.medium))
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(Color.green.opacity(0.2))
                .foregroundStyle(.green)
                .clipShape(RoundedRectangle(cornerRadius: 4))
        }
    }
}

// MARK: - CWCallsignInfoChip

/// Compact inline display of callsign info (name only)
struct CWCallsignInfoChip: View {
    let info: CallsignInfo

    var body: some View {
        HStack(spacing: 4) {
            if let emoji = info.emoji {
                Text(emoji)
                    .font(.caption)
            }

            if let name = info.displayName {
                Text(name)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 16) {
        // Polo notes entry with full info
        CWCallsignInfoCard(
            info: CallsignInfo(
                callsign: "K4SWL",
                name: "Thomas",
                note: "POTA activator extraordinaire",
                emoji: "🌳",
                qth: "Nashville",
                state: "TN",
                country: nil,
                grid: "EM66",
                licenseClass: "Extra",
                source: .poloNotes
            )
        )

        // QRZ entry
        CWCallsignInfoCard(
            info: CallsignInfo(
                callsign: "W1AW",
                name: "ARRL HQ",
                note: nil,
                emoji: nil,
                qth: "Newington",
                state: "CT",
                country: "USA",
                grid: "FN31",
                licenseClass: nil,
                source: .qrz
            )
        )

        // Minimal entry
        CWCallsignInfoCard(
            info: CallsignInfo(
                callsign: "N9HO",
                name: nil,
                note: nil,
                emoji: nil,
                qth: nil,
                state: nil,
                country: nil,
                grid: nil,
                licenseClass: nil,
                source: .poloNotes
            )
        )

        // Chip example
        HStack {
            Text("K4SWL")
                .font(.body.monospaced())
            CWCallsignInfoChip(
                info: CallsignInfo(
                    callsign: "K4SWL",
                    name: "Thomas",
                    note: nil,
                    emoji: "🌳",
                    qth: nil,
                    state: nil,
                    country: nil,
                    grid: nil,
                    licenseClass: nil,
                    source: .poloNotes
                )
            )
        }
    }
    .padding()
}
