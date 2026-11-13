import CarrierWaveCore
import CarrierWaveData
import SwiftData
import SwiftUI

// MARK: - CallsignDuplicateStatus

/// Duplicate status of a callsign within the current UTC day
enum CallsignDuplicateStatus {
    /// First contact with this callsign today
    case firstContact
    /// Previously worked but current band unknown — informational only
    case previouslyWorked(previousBands: [String])
    /// Contact on a new band (worked before today on other bands)
    case newBand(previousBands: [String])
    /// Same band but different mode family — valid new QSO
    case newMode(band: String, previousModes: [String])
    /// Duplicate on the same band and mode today. `isPOTA` controls banner messaging.
    case duplicateBand(band: String, isPOTA: Bool)
}

extension CallsignDuplicateStatus {
    /// Map the shared Rust classification (`FfiDuplicateStatus`, the 1:1 port of
    /// this enum) into the view's type. The activation logger's dupe classification
    /// runs in Rust (`FieldStore.activationDuplicateStatus`); this is the display
    /// bridge.
    init(ffi: FfiDuplicateStatus) {
        switch ffi {
        case .firstContact:
            self = .firstContact
        case let .previouslyWorked(previousBands):
            self = .previouslyWorked(previousBands: previousBands)
        case let .newBand(previousBands):
            self = .newBand(previousBands: previousBands)
        case let .newMode(band, previousModes):
            self = .newMode(band: band, previousModes: previousModes)
        case let .duplicateBand(band, isPota):
            self = .duplicateBand(band: band, isPOTA: isPota)
        }
    }
}

// MARK: - LoggerNoteRow

/// A row displaying a session note
struct LoggerNoteRow: View {
    let note: SessionNoteEntry

    var body: some View {
        HStack(spacing: 12) {
            Text(note.displayTime)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .frame(width: 50, alignment: .leading)

            Image(systemName: "note.text")
                .font(.caption)
                .foregroundStyle(.purple)

            Text(note.text)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .lineLimit(2)

            Spacer()
        }
        .padding(.vertical, 6)
    }
}

// MARK: - LoggerQSORow

/// A row displaying a logged QSO
struct LoggerQSORow: View {
    // MARK: Internal

    let qso: QSO
    /// All QSOs for the UTC day (for duplicate detection across sessions)
    var utcDayQSOs: [QSO] = []
    /// Whether this is a POTA session (scopes dupe detection by park)
    var isPOTASession: Bool = false
    /// Callback when QSO is deleted (hidden)
    var onQSODeleted: ((QSO) -> Void)?
    /// Callback when callsign is tapped for quick edit
    var onEditCallsign: ((QSO) -> Void)?
    /// Callback when QSO is recalled (populate form for new QSO)
    var onRecall: ((QSO) -> Void)?
    /// Callback when delete is requested from context menu (triggers confirmation)
    var onRequestDelete: ((QSO) -> Void)?

    var body: some View {
        Button {
            showEditSheet = true
        } label: {
            rowContent
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showEditSheet) {
            LoggerQSOEditSheet(qso: qso, onDelete: { onQSODeleted?(qso) })
        }
        .onAppear {
            // Use QSO's stored data if available (from pre-fetch during logging)
            if callsignInfo == nil, qso.name != nil || qso.theirGrid != nil {
                callsignInfo = CallsignInfo(
                    callsign: qso.callsign,
                    name: qso.name,
                    qth: qso.qth,
                    state: qso.state,
                    country: qso.country,
                    grid: qso.theirGrid,
                    licenseClass: qso.theirLicenseClass,
                    source: .qrz
                )
            }
        }
        .contextMenu {
            Button {
                onRecall?(qso)
            } label: {
                Label("Recall", systemImage: "arrow.counterclockwise")
            }

            Button {
                onEditCallsign?(qso)
            } label: {
                Label("Edit", systemImage: "pencil")
            }

            Divider()

            Button(role: .destructive) {
                onRequestDelete?(qso)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .task(id: qso.id) {
            await lookupCallsign()
            totalContactCount = fetchTotalContactCount(for: qso.callsign)
        }
    }

    // MARK: Private

    /// Shared UTC time formatter - created once, reused for all rows
    private static let utcTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.modelContext) private var modelContext

    @State private var callsignInfo: CallsignInfo?
    @State private var showEditSheet = false
    @State private var totalContactCount: Int = 0

    private var isRegularWidth: Bool {
        horizontalSizeClass == .regular
    }

    /// Display name from callsign lookup (prefers nickname), fallback to QSO stored name
    private var displayName: String? {
        callsignInfo?.displayName ?? qso.name?.capitalized
    }

    /// Display location from QSO or callsign lookup
    private var displayLocation: String? {
        if let state = qso.state {
            return state
        }
        if let info = callsignInfo {
            let parts = [info.state, info.country].compactMap { $0 }
            if !parts.isEmpty {
                return parts.joined(separator: ", ")
            }
        }
        return nil
    }

    /// Determine the duplicate status of this QSO's callsign for the UTC day.
    /// POTA sessions scope by park; all others just match callsign + band.
    private var duplicateStatus: CallsignDuplicateStatus {
        let callsign = qso.callsign.uppercased()
        let thisBand = qso.band

        let previousQSOs: [QSO]
        if isPOTASession {
            let qsoPark = qso.parkReference?.uppercased()
            previousQSOs = utcDayQSOs.filter { other in
                other.callsign.uppercased() == callsign
                    && other.timestamp < qso.timestamp
                    && other.parkReference?.uppercased() == qsoPark
            }
        } else {
            previousQSOs = utcDayQSOs.filter { other in
                other.callsign.uppercased() == callsign
                    && other.timestamp < qso.timestamp
            }
        }

        if previousQSOs.isEmpty {
            return .firstContact
        }

        let previousBands = Set(previousQSOs.map(\.band))

        if previousBands.contains(thisBand) {
            let thisMode = qso.mode
            let sameBandQSOs = previousQSOs.filter { $0.band == thisBand }
            let hasEquivalentMode = sameBandQSOs.contains { other in
                ModeEquivalence.areEquivalent(other.mode, thisMode)
            }
            if hasEquivalentMode {
                return .duplicateBand(band: thisBand, isPOTA: isPOTASession)
            } else {
                let previousModes = ModeEquivalence.deduplicatedModes(
                    sameBandQSOs.map(\.mode)
                )
                return .newMode(band: thisBand, previousModes: previousModes)
            }
        } else {
            return .newBand(previousBands: Array(previousBands).sorted())
        }
    }

    /// Color for the callsign based on duplicate status
    private var callsignColor: Color {
        switch duplicateStatus {
        case .firstContact:
            .green
        case .previouslyWorked:
            .primary
        case .newBand:
            .blue
        case .newMode:
            .green
        case .duplicateBand:
            .orange
        }
    }

    private var rowContent: some View {
        HStack(spacing: 12) {
            Text(Self.utcTimeFormatter.string(from: qso.timestamp))
                .font(isRegularWidth ? .subheadline.monospaced() : .caption.monospaced())
                .foregroundStyle(.secondary)
                .frame(width: isRegularWidth ? 60 : 50, alignment: .leading)

            HStack(spacing: 4) {
                // Callsign is tappable for quick edit
                Button {
                    onEditCallsign?(qso)
                } label: {
                    Text(qso.callsign)
                        .font(
                            isRegularWidth
                                ? .headline.weight(.semibold).monospaced()
                                : .subheadline.weight(.semibold).monospaced()
                        )
                        .foregroundStyle(callsignColor)
                        .fixedSize(horizontal: true, vertical: false)
                }
                .buttonStyle(.plain)

                if let emoji = callsignInfo?.combinedEmoji {
                    Text(emoji)
                        .font(.caption)
                }

                // P2P indicator (logged with a `theirParkReference`)
                if qso.theirParkReference != nil {
                    Image(systemName: "tree.fill")
                        .font(.caption2)
                        .foregroundStyle(.green)
                }

                // S2S indicator (logged with a contacted-station summit ref)
                if let s2s = qso.sotaRef, !s2s.isEmpty {
                    Image(systemName: "mountain.2.fill")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                        .accessibilityLabel("Summit-to-summit with \(s2s)")
                }

                // Callsign change indicator
                if callsignInfo?.callsignChangeNote != nil || qso.callsignChangeNote != nil {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }

                duplicateStatusBadge
            }
            .fixedSize(horizontal: true, vertical: false)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    if let name = displayName {
                        Text(name)
                            .font(isRegularWidth ? .subheadline : .caption)
                            .lineLimit(1)
                    }
                    if totalContactCount > 1 {
                        Text("\u{00d7}\(totalContactCount)")
                            .font(isRegularWidth ? .caption.weight(.medium) : .caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                }
                if let note = callsignInfo?.note, !note.isEmpty {
                    Text(note)
                        .font(isRegularWidth ? .caption : .caption2)
                        .foregroundStyle(.blue)
                        .lineLimit(1)
                } else if let location = displayLocation {
                    Text(location)
                        .font(isRegularWidth ? .caption : .caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                // Frequency or band + mode
                HStack(spacing: 4) {
                    if let freq = qso.frequency {
                        Text(FrequencyFormatter.format(freq))
                            .font(
                                isRegularWidth
                                    ? .subheadline.monospaced()
                                    : .caption.monospaced()
                            )
                            .foregroundStyle(.secondary)
                    } else {
                        Text(qso.band)
                            .font(
                                isRegularWidth
                                    ? .subheadline.monospaced()
                                    : .caption.monospaced()
                            )
                            .foregroundStyle(.secondary)
                    }
                    Text(qso.mode)
                        .font(isRegularWidth ? .caption : .caption2)
                        .foregroundStyle(.tertiary)
                }

                Text("\(qso.rstSent ?? "599")/\(qso.rstReceived ?? "599")")
                    .font(isRegularWidth ? .caption.monospaced() : .caption2.monospaced())
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, isRegularWidth ? 10 : 6)
    }

    private var duplicateStatusBadge: some View {
        DuplicateStatusBadge(status: duplicateStatus, isRegularWidth: isRegularWidth)
    }

    private func lookupCallsign() async {
        // Skip if we already have callsign info from logging or previous lookup
        guard callsignInfo == nil,
              qso.name == nil, qso.theirGrid == nil
        else {
            return
        }

        let service = CallsignLookupService(modelContext: modelContext)
        guard let info = await service.lookup(qso.callsign) else {
            return
        }

        callsignInfo = info

        // Update QSO with enriched data (background fill-in for fast logging)
        var updated = false
        if qso.name == nil, let name = info.name {
            qso.name = name
            updated = true
        }
        if qso.theirGrid == nil, let grid = info.grid {
            qso.theirGrid = grid
            updated = true
        }
        if qso.state == nil, let state = info.state {
            qso.state = state
            updated = true
        }
        if qso.country == nil, let country = info.country {
            qso.country = country
            updated = true
        }
        if qso.qth == nil, let qth = info.qth {
            qso.qth = qth
            updated = true
        }
        if qso.theirLicenseClass == nil, let licenseClass = info.licenseClass {
            qso.theirLicenseClass = licenseClass
            updated = true
        }
        if qso.callsignChangeNote == nil, let changeNote = info.callsignChangeNote {
            qso.callsignChangeNote = changeNote
            updated = true
        }

        if updated {
            try? modelContext.save()
        }
    }

    /// Count all-time QSOs with a callsign (excludes hidden and metadata modes)
    private func fetchTotalContactCount(for callsign: String) -> Int {
        let upper = callsign.uppercased()
        return
            (try? modelContext.boundedCount(
                QSO.self,
                predicate: #Predicate<QSO> { qso in
                    qso.callsign == upper
                        && !qso.isHidden
                        && qso.mode != "WEATHER"
                        && qso.mode != "SOLAR"
                        && qso.mode != "NOTE"
                }
            )) ?? 0
    }
}
