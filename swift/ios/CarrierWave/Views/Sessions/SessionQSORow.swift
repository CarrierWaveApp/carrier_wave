import CarrierWaveData
import SwiftData
import SwiftUI

// MARK: - SessionQSORow

/// Compact QSO row used in session detail views.
/// Tap-to-edit and swipe-to-delete handled by parent.
struct SessionQSORow: View {
    // MARK: Internal

    let qso: QSO
    var isSpotted: Bool = false
    var myGrid: String?
    var sessionCallsign: String?
    var sessionPark: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            primaryLine
            metadataLine
        }
        .contentShape(Rectangle())
        .task { await lookupCallsign() }
    }

    // MARK: Private

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()

    @Environment(\.modelContext) private var modelContext
    @State private var lookupInfo: CallsignInfo?

    private var showMyCallsign: Bool {
        guard let sessionCallsign else {
            return false
        }
        return qso.myCallsign.uppercased() != sessionCallsign.uppercased()
    }

    private var showMyPark: Bool {
        guard let sessionPark, let qsoPark = qso.parkReference else {
            return false
        }
        return qsoPark.uppercased() != sessionPark.uppercased()
    }

    /// Callsign notes from Polo notes cache
    private var notesInfo: CallsignInfo? {
        CallsignNotesCache.shared.infoSync(for: qso.callsign)
    }

    /// Display name: prefer enriched QRZ lookup (nickname/firstName),
    /// then Polo notes, then first name from stored full name
    private var displayName: String? {
        if let lookupName = lookupInfo?.displayName {
            return lookupName
        }
        if let notesName = notesInfo?.displayName {
            return notesName
        }
        // Extract first name from stored full name (e.g., "TIMOTHY D HALE" → "Timothy")
        guard let fullName = qso.name, !fullName.isEmpty else {
            return nil
        }
        let firstName = fullName.split(separator: " ").first.map(String.init)
        return firstName?.capitalized
    }

    /// Compact RST: "S/R" format, nil if both missing
    private var compactRST: String? {
        let sent = qso.rstSent
        let rcvd = qso.rstReceived
        guard sent != nil || rcvd != nil else {
            return nil
        }
        return "\(sent ?? "-")/\(rcvd ?? "-")"
    }

    // MARK: Layout

    /// Line 1: spot icon, callsign + emoji, name (flexible/truncates), RST, time.
    /// Everything except the name is `fixedSize` so it can't be squeezed/wrapped.
    private var primaryLine: some View {
        HStack(spacing: 6) {
            if isSpotted {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.caption)
                    .foregroundStyle(.teal)
                    .fixedSize()
            }

            Text(qso.callsign)
                .font(.subheadline.monospaced().weight(.semibold))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)

            if let emoji = notesInfo?.combinedEmoji {
                Text(emoji)
                    .font(.caption)
                    .fixedSize()
            }

            if let name = displayName {
                Text(name)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Spacer(minLength: 4)

            if let rst = compactRST {
                Text(rst)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.orange)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }

            Text(Self.timeFormatter.string(from: qso.timestamp))
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
    }

    /// Line 2: band/mode + optional my-callsign/park/P2P/grid pills, optional note.
    /// Sync-status dots intentionally omitted — Logs tab is the canonical place for them.
    /// All pills are `fixedSize` so SwiftUI cannot break mid-token (no more "CM8\n7VL").
    private var metadataLine: some View {
        HStack(spacing: 6) {
            pill(qso.band, color: .blue)
            pill(qso.mode, color: .green)

            if showMyCallsign {
                pill(qso.myCallsign, color: .cyan)
            }

            if showMyPark, let park = qso.parkReference {
                pill(park, color: .mint)
            }

            if let theirPark = qso.theirParkReference, !theirPark.isEmpty {
                pill("P2P", color: .orange)
            }

            if let grid = myGrid {
                pill(grid, color: .purple)
            }

            if let note = notesInfo?.note, !note.isEmpty {
                Text(note)
                    .font(.caption2)
                    .foregroundStyle(.blue)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .layoutPriority(-1)
            }

            Spacer(minLength: 4)
        }
    }

    private func pill(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption.weight(.medium))
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .badgePill(color.opacity(0.15))
    }

    /// Look up callsign from QRZ/HamDB for nickname if not already available
    private func lookupCallsign() async {
        // Skip if notes cache already has enriched data (nickname/firstName)
        if let info = notesInfo, info.nickname != nil || info.firstName != nil {
            return
        }
        // Skip if QSO already has a stored name and no lookup service available
        guard lookupInfo == nil else {
            return
        }
        let service = CallsignLookupService(modelContext: modelContext)
        guard let info = await service.lookup(qso.callsign) else {
            return
        }
        lookupInfo = info
    }
}
