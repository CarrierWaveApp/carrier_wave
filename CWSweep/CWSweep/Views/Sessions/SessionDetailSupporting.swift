import CarrierWaveData
import SwiftUI

// MARK: - SessionQSODisplayRow

/// Lightweight display-only snapshot of a QSO for session detail rendering.
struct SessionQSODisplayRow: Identifiable, Sendable {
    // MARK: Lifecycle

    init(from qso: QSO) {
        id = qso.id
        callsign = qso.callsign
        band = qso.band
        mode = qso.mode
        rstSent = qso.rstSent
        theirGrid = qso.theirGrid
        timestamp = qso.timestamp
        parkReference = qso.parkReference
        state = qso.state
    }

    // MARK: Internal

    let id: UUID
    let callsign: String
    let band: String
    let mode: String
    let rstSent: String?
    let theirGrid: String?
    let timestamp: Date
    let parkReference: String?
    let state: String?
}

// MARK: - RoveParkGroup

/// Grouped QSOs for a rove park
struct RoveParkGroup {
    let parkReference: String
    let rows: [SessionQSODisplayRow]
}

// MARK: - SessionDetailQSORow

/// Compact QSO row for the session detail
struct SessionDetailQSORow: View {
    // MARK: Internal

    let row: SessionQSODisplayRow

    var body: some View {
        HStack(spacing: 8) {
            Text(row.callsign)
                .font(.subheadline.monospaced().weight(.semibold))

            Spacer()

            pill(row.band, color: .blue)
            pill(row.mode, color: .green)

            if let rst = row.rstSent {
                Text(rst)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }

            if let grid = row.theirGrid {
                Text(grid)
                    .font(.caption.monospaced())
                    .foregroundStyle(.purple)
            }

            Text(Self.timeFormatter.string(from: row.timestamp))
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
    }

    // MARK: Private

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()

    private func pill(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15))
            .clipShape(Capsule())
    }
}

// MARK: - RoveStopRow

/// Timeline row showing a single rove stop
struct RoveStopRow: View {
    // MARK: Internal

    let stop: RoveStop

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(stop.isActive ? Color.green : Color.secondary.opacity(0.3))
                .frame(width: 10, height: 10)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                let parks = ParkReference.split(stop.parkReference)
                ForEach(parks, id: \.self) { park in
                    Text(park)
                        .font(.subheadline.monospaced().weight(.semibold))
                        .foregroundStyle(.green)
                }

                HStack(spacing: 8) {
                    Text(timeRange)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)

                    Text("\(stop.qsoCount) QSOs")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let grid = stop.myGrid {
                        Text(grid)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    // MARK: Private

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()

    private var timeRange: String {
        let start = Self.timeFormatter.string(from: stop.startedAt)
        if let endedAt = stop.endedAt {
            let end = Self.timeFormatter.string(from: endedAt)
            return "\(start)\u{2013}\(end) UTC"
        }
        return "\(start)\u{2013}now UTC"
    }
}

// MARK: - SessionMapPin

/// Small map pin marker
struct SessionMapPin: View {
    let color: Color
    var size: CGFloat = 9

    var body: some View {
        VStack(spacing: 0) {
            Circle()
                .fill(color.opacity(0.8))
                .frame(width: size, height: size)
            Rectangle()
                .fill(color.opacity(0.7))
                .frame(width: max(1.5, size * 0.17), height: max(6, size * 0.67))
        }
    }
}

// MARK: - MetadataItem

struct MetadataItem {
    let icon: String
    let label: String
}

// MARK: - Details Section

extension SessionDetailView {
    @ViewBuilder
    var detailsSection: some View {
        let hasEquipment = session.myRig != nil || session.myAntenna != nil
            || session.myKey != nil || session.myMic != nil
            || session.extraEquipment != nil
        let hasNotes = session.attendees != nil || session.notes != nil

        if hasEquipment || hasNotes {
            Section {
                DisclosureGroup("Details") {
                    if hasEquipment {
                        equipmentRows
                    }
                    if hasNotes {
                        notesRows
                    }
                }
            }
        }
    }

    @ViewBuilder
    var equipmentRows: some View {
        if let rig = session.myRig {
            Label(rig, systemImage: "radio")
        }
        if let antenna = session.myAntenna {
            Label(antenna, systemImage: "antenna.radiowaves.left.and.right")
        }
        if let key = session.myKey {
            Label(key, systemImage: "pianokeys")
        }
        if let mic = session.myMic {
            Label(mic, systemImage: "mic")
        }
        if let extra = session.extraEquipment {
            Text(extra)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    var notesRows: some View {
        if let attendees = session.attendees {
            LabeledContent("Attendees") {
                Text(attendees)
                    .font(.subheadline.monospaced())
            }
        }
        if let notes = session.notes {
            Text(notes)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}
