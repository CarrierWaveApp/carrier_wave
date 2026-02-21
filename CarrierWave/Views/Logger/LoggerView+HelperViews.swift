import CarrierWaveCore
import SwiftData
import SwiftUI

// MARK: - POTACallsignStatus

/// Status of a callsign within a POTA session
enum POTACallsignStatus {
    /// First contact with this callsign
    case firstContact
    /// Contact on a new band (valid for POTA)
    case newBand(previousBands: [String])
    /// Duplicate on the same band (not valid for POTA)
    case duplicateBand(band: String)
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
    /// All QSOs for the UTC day at any park (for POTA duplicate detection across sessions)
    var utcDayQSOs: [QSO] = []
    /// Whether this is a POTA session
    var isPOTASession: Bool = false
    /// Callback when QSO is deleted (hidden)
    var onQSODeleted: ((QSO) -> Void)?
    /// Callback when callsign is tapped for quick edit
    var onEditCallsign: ((QSO) -> Void)?

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

    /// Determine the POTA status of this QSO's callsign
    private var potaStatus: POTACallsignStatus {
        let callsign = qso.callsign.uppercased()
        let thisBand = qso.band

        // Search all QSOs for the UTC day at the same park (not just this session).
        // POTA contacts are unique per callsign + band + park + UTC day.
        let qsoPark = qso.parkReference?.uppercased()
        let previousQSOs = utcDayQSOs.filter { other in
            other.callsign.uppercased() == callsign
                && other.timestamp < qso.timestamp
                && other.parkReference?.uppercased() == qsoPark
        }

        if previousQSOs.isEmpty {
            return .firstContact
        }

        let previousBands = Set(previousQSOs.map(\.band))

        if previousBands.contains(thisBand) {
            return .duplicateBand(band: thisBand)
        } else {
            return .newBand(previousBands: Array(previousBands).sorted())
        }
    }

    /// Color for the callsign based on POTA status
    private var callsignColor: Color {
        guard isPOTASession else {
            return .green
        }

        switch potaStatus {
        case .firstContact:
            return .green
        case .newBand:
            return .blue
        case .duplicateBand:
            return .orange
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

                // Show POTA status badges
                if isPOTASession {
                    potaStatusBadge
                }
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
                // Frequency or band
                if let freq = qso.frequency {
                    Text(FrequencyFormatter.format(freq))
                        .font(isRegularWidth ? .subheadline.monospaced() : .caption.monospaced())
                        .foregroundStyle(.secondary)
                } else {
                    Text(qso.band)
                        .font(isRegularWidth ? .subheadline.monospaced() : .caption.monospaced())
                        .foregroundStyle(.secondary)
                }

                Text("\(qso.rstSent ?? "599")/\(qso.rstReceived ?? "599")")
                    .font(isRegularWidth ? .caption.monospaced() : .caption2.monospaced())
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, isRegularWidth ? 10 : 6)
    }

    /// Badge showing POTA status
    @ViewBuilder
    private var potaStatusBadge: some View {
        switch potaStatus {
        case .firstContact:
            EmptyView()
        case let .newBand(previousBands):
            Text("NEW BAND")
                .font(isRegularWidth ? .caption.weight(.bold) : .caption2.weight(.bold))
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(Color.blue)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 3))
                .help("Previously worked on: \(previousBands.joined(separator: ", "))")
        case .duplicateBand:
            Text("DUPE")
                .font(isRegularWidth ? .caption.weight(.bold) : .caption2.weight(.bold))
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(Color.orange)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 3))
        }
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

        if updated {
            try? modelContext.save()
        }
    }

    /// Count all-time QSOs with a callsign (excludes hidden and metadata modes)
    private func fetchTotalContactCount(for callsign: String) -> Int {
        let upper = callsign.uppercased()
        return
            (try? modelContext.fetchCount(
                FetchDescriptor<QSO>(
                    predicate: #Predicate<QSO> { qso in
                        qso.callsign == upper
                            && !qso.isHidden
                            && qso.mode != "WEATHER"
                            && qso.mode != "SOLAR"
                            && qso.mode != "NOTE"
                    }
                )
            )) ?? 0
    }
}

// MARK: - POTAStatusBanner

/// Banner showing POTA duplicate or new band status before logging
struct POTAStatusBanner: View {
    let status: POTACallsignStatus

    var body: some View {
        switch status {
        case .firstContact:
            EmptyView()

        case let .newBand(previousBands):
            HStack(spacing: 8) {
                Image(systemName: "star.fill")
                    .foregroundStyle(.blue)
                VStack(alignment: .leading, spacing: 2) {
                    Text("New Band!")
                        .font(.subheadline.weight(.semibold))
                    Text("Previously worked on \(previousBands.joined(separator: ", "))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding()
            .background(Color.blue.opacity(0.15))
            .clipShape(RoundedRectangle(cornerRadius: 12))

        case let .duplicateBand(band):
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Duplicate on \(band)")
                        .font(.subheadline.weight(.semibold))
                    Text("Already worked this callsign on this band")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding()
            .background(Color.orange.opacity(0.15))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
}

// MARK: - SwipeToDismissPanel

/// Wrapper that adds swipe-to-dismiss gesture to a panel
struct SwipeToDismissPanel<Content: View>: View {
    // MARK: Internal

    @Binding var isPresented: Bool

    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .offset(y: dragOffset)
            .gesture(
                DragGesture()
                    .onChanged { value in
                        // Only allow dragging down
                        if value.translation.height > 0 {
                            dragOffset = value.translation.height
                        }
                    }
                    .onEnded { value in
                        // Dismiss if dragged more than 80 points or with velocity
                        if value.translation.height > 80
                            || value.predictedEndTranslation.height > 150
                        {
                            withAnimation(.easeOut(duration: 0.2)) {
                                isPresented = false
                            }
                        }
                        // Reset offset
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            dragOffset = 0
                        }
                    }
            )
    }

    // MARK: Private

    @State private var dragOffset: CGFloat = 0
}
