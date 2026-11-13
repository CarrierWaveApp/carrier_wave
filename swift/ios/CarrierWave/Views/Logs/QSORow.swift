import CarrierWaveData
import SwiftData
import SwiftUI

// MARK: - QSORow

/// One Logbook row, rendered from a `QSORowSnapshot` (backend-agnostic). The
/// contact-count badge and the callsign/park caches key off snapshot fields and
/// read the live SwiftData context, which is always present regardless of
/// `cwStoreQSOMode`.
struct QSORow: View {
    // MARK: Internal

    let snapshot: QSORowSnapshot
    let serviceConfig: ServiceConfiguration

    var body: some View {
        Group {
            if isLandscape {
                landscapeRow
            } else {
                portraitRow
            }
        }
        .padding(.vertical, isRegularWidth ? 8 : 4)
        .task {
            if let park = snapshot.parkReference {
                parkName = await POTAParksCache.shared.name(for: park)
            }
            callsignInfo = await CallsignNotesCache.shared.info(for: snapshot.callsign)
            totalContactCount = fetchTotalContactCount(for: snapshot.callsign)
        }
        .onReceive(NotificationCenter.default.publisher(for: .didSyncQSOs)) { _ in
            totalContactCount = fetchTotalContactCount(for: snapshot.callsign)
        }
        .onAppear {
            // Refresh count when row re-appears (e.g., after tab switch)
            // fetchCount is cheap — no object materialization
            let fresh = fetchTotalContactCount(for: snapshot.callsign)
            if fresh != totalContactCount {
                totalContactCount = fresh
            }
        }
    }

    // MARK: Private

    private static let utcFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d HH:mm"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.modelContext) private var modelContext

    @State private var parkName: String?
    @State private var callsignInfo: CallsignInfo?
    @State private var totalContactCount: Int = 0

    private var band: String {
        snapshot.band ?? ""
    }

    private var mode: String {
        snapshot.mode ?? ""
    }

    private var isRegularWidth: Bool {
        horizontalSizeClass == .regular
    }

    private var isLandscape: Bool {
        verticalSizeClass == .compact
    }

    /// Display name from callsign notes (prefers nickname), fallback to QSO stored name
    private var displayName: String? {
        callsignInfo?.displayName ?? snapshot.name?.capitalized
    }

    private var formattedTimestamp: String {
        Self.utcFormatter.string(from: snapshot.timestamp) + "Z"
    }

    /// One badge per service type — collapses POTA per-park records and any duplicate records
    private var sortedPresence: [PresenceSummary] {
        let filtered = snapshot.presence
            .filter { summary in
                guard let type = ServiceType(rawValue: summary.serviceTypeRawValue) else {
                    return false
                }
                let configured = serviceConfig.isConfigured(type)
                return configured || summary.isPresent || summary.isSubmitted
            }

        // Group by service type, pick the best-status record from each group
        let grouped = Dictionary(grouping: filtered) { $0.serviceTypeRawValue }
        return grouped.values
            .compactMap { records -> PresenceSummary? in
                records.first(where: \.isPresent)
                    ?? records.first(where: \.isSubmitted)
                    ?? records.first
            }
            .sorted { $0.serviceTypeRawValue < $1.serviceTypeRawValue }
    }

    /// Compact single-line row for landscape mode
    private var landscapeRow: some View {
        HStack(spacing: 8) {
            Text(snapshot.callsign)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)

            if let freq = snapshot.frequency {
                Text(FrequencyFormatter.format(freq))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(band)
                .font(.caption.weight(.medium))
                .foregroundStyle(BandColors.color(for: band))
            Text(mode)
                .font(.caption)
                .foregroundStyle(.secondary)

            if let rstSent = snapshot.rstSent {
                Text("S:\(rstSent)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let grid = snapshot.theirGrid {
                Text(grid)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let park = snapshot.parkReference {
                Text(park)
                    .font(.caption)
                    .foregroundStyle(.green)
            }

            Spacer()

            Text(formattedTimestamp)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    /// Full multi-line row for portrait mode
    private var portraitRow: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 2)
                .fill(BandColors.color(for: band))
                .frame(width: 4)

            portraitContent
        }
    }

    private var portraitContent: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(snapshot.callsign)
                    .font(.headline)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)

                if let name = displayName {
                    Text(name)
                        .font(isRegularWidth ? .body : .subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                if let emoji = callsignInfo?.combinedEmoji {
                    Text(emoji)
                        .font(.caption)
                }

                if totalContactCount > 1 {
                    ContactCountBadge(count: totalContactCount)
                }

                Spacer()

                Text(formattedTimestamp)
                    .font(isRegularWidth ? .subheadline : .caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }

            HStack(spacing: 6) {
                if let freq = snapshot.frequency {
                    Label(FrequencyFormatter.format(freq), systemImage: "waveform")
                        .font(isRegularWidth ? .subheadline : .caption)
                        .foregroundStyle(.secondary)
                }

                Text(band)
                    .font((isRegularWidth ? Font.caption : Font.caption2).weight(.medium))
                    .badgePill(BandColors.color(for: band).opacity(0.2))
                    .foregroundStyle(BandColors.color(for: band))

                Text(mode)
                    .font((isRegularWidth ? Font.caption : Font.caption2).weight(.medium))
                    .badgePill(Color(.systemGray4).opacity(0.5))
                    .foregroundStyle(.secondary)

                if let park = snapshot.parkReference {
                    if let name = parkName {
                        Label("\(park) - \(name)", systemImage: "tree")
                            .foregroundStyle(.green)
                            .lineLimit(1)
                    } else {
                        Label(park, systemImage: "tree")
                            .foregroundStyle(.green)
                    }
                }

                Spacer()
            }
            .font(isRegularWidth ? .subheadline : .caption)

            HStack(spacing: 8) {
                ForEach(sortedPresence, id: \.serviceTypeRawValue) { summary in
                    if let type = ServiceType(rawValue: summary.serviceTypeRawValue) {
                        ServicePresenceBadge(
                            summary: summary,
                            serviceType: type,
                            lotwConfirmed: snapshot.lotwConfirmed,
                            qrzConfirmed: snapshot.qrzConfirmed,
                            isServiceConfigured: serviceConfig.isConfigured(type)
                        )
                    }
                }
            }
        }
    }

    /// Count all-time QSOs with a callsign (excludes hidden and metadata modes)
    private func fetchTotalContactCount(for callsign: String) -> Int {
        let upper = callsign.uppercased()
        return (try? modelContext.boundedCount(
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

// MARK: - QSORow from a live QSO

extension QSORow {
    /// Convenience for callers that still hold a live `QSO` (e.g. day-summary
    /// previews). Maps it to a snapshot so there is one row implementation.
    init(qso: QSO, serviceConfig: ServiceConfiguration) {
        self.init(snapshot: QSORowSnapshot(qso: qso), serviceConfig: serviceConfig)
    }
}

// MARK: - ServicePresenceBadge

struct ServicePresenceBadge: View {
    // MARK: Internal

    let summary: PresenceSummary
    let serviceType: ServiceType
    let lotwConfirmed: Bool
    let qrzConfirmed: Bool
    let isServiceConfigured: Bool

    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: iconName)
            Text(serviceType.displayName)
                .lineLimit(1)
        }
        .font(isRegularWidth ? .caption : .caption2)
        .fixedSize()
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(backgroundColor.opacity(0.2))
        .foregroundStyle(backgroundColor)
        .clipShape(Capsule())
    }

    // MARK: Private

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var isRegularWidth: Bool {
        horizontalSizeClass == .regular
    }

    private var isBidirectional: Bool {
        switch serviceType {
        case .qrz,
             .pota,
             .hamrs,
             .clublog,
             .eqsl:
            true
        case .lofi,
             .lotw:
            false
        }
    }

    private var isConfirmed: Bool {
        switch serviceType {
        case .lotw:
            lotwConfirmed
        case .qrz:
            qrzConfirmed
        default:
            false
        }
    }

    private var iconName: String {
        if summary.isPresent, isConfirmed {
            return "star.fill"
        }

        if isBidirectional {
            if summary.isPresent, !summary.needsUpload {
                return "checkmark"
            } else if summary.isPresent, summary.needsUpload {
                return "arrow.down"
            }
        }

        if summary.isPresent {
            return "checkmark"
        }

        if summary.isSubmitted {
            return "clock.arrow.circlepath"
        }

        return "clock"
    }

    private var backgroundColor: Color {
        if summary.isPresent {
            .green
        } else if summary.isSubmitted {
            .blue
        } else if isServiceConfigured {
            .orange
        } else {
            .gray
        }
    }
}

// MARK: - ServicePresenceBadge from a live ServicePresence

extension ServicePresenceBadge {
    /// Convenience for the QSO detail view, which still holds a live
    /// `ServicePresence` + `QSO`. Maps them to the summary the badge renders.
    init(presence: ServicePresence, qso: QSO, isServiceConfigured: Bool) {
        self.init(
            summary: PresenceSummary(
                serviceTypeRawValue: presence.serviceTypeRawValue,
                isPresent: presence.isPresent,
                isSubmitted: presence.isSubmitted,
                needsUpload: presence.needsUpload
            ),
            serviceType: presence.serviceType,
            lotwConfirmed: qso.lotwConfirmed,
            qrzConfirmed: qso.qrzConfirmed,
            isServiceConfigured: isServiceConfigured
        )
    }
}
