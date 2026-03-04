import CarrierWaveCore
import CoreLocation
import SwiftUI

// MARK: - LoggerCallsignCard

/// Displays callsign lookup information in the logger
struct LoggerCallsignCard: View {
    // MARK: Internal

    let info: CallsignInfo
    var previousQSOCount: Int = 0
    var myGrid: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(info.callsign)
                            .font(.title2.weight(.bold).monospaced())

                        notesDisplay
                    }

                    if let name = info.displayName {
                        Text(name)
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                    }
                }

                Spacer()

                if let flag = CallsignFlagHelper.countryFlag(for: info.callsign) {
                    Text(flag)
                        .font(.largeTitle)
                }
            }

            if hasDetails {
                detailChips
            }

            if let note = info.note, !note.isEmpty {
                noteSection(note)
            }

            if let previousCall = info.previousCallsign {
                previousCallsignSection(previousCall)
            }

            if let changeNote = info.callsignChangeNote {
                callsignChangeSection(changeNote)
            }

            sourceIndicator
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: Private

    @AppStorage("callsignNotesDisplayMode") private var notesDisplayMode = "emoji"

    private var hasDetails: Bool {
        info.qth != nil || info.grid != nil || info.state != nil || info.country != nil
            || previousQSOCount > 0 || distanceKm != nil
    }

    /// Distance in km from user's grid to station's grid
    private var distanceKm: Double? {
        guard let myGrid, !myGrid.isEmpty,
              let theirGrid = info.grid, !theirGrid.isEmpty,
              let myCoord = MaidenheadConverter.coordinate(from: myGrid),
              let theirCoord = MaidenheadConverter.coordinate(from: theirGrid)
        else {
            return nil
        }
        let myLoc = CLLocation(latitude: myCoord.latitude, longitude: myCoord.longitude)
        let theirLoc = CLLocation(latitude: theirCoord.latitude, longitude: theirCoord.longitude)
        return myLoc.distance(from: theirLoc) / 1_000.0
    }

    /// Bearing in degrees from user's grid to station's grid
    private var bearingDegrees: Double? {
        guard let myGrid, !myGrid.isEmpty,
              let theirGrid = info.grid, !theirGrid.isEmpty,
              let myCoord = MaidenheadConverter.coordinate(from: myGrid),
              let theirCoord = MaidenheadConverter.coordinate(from: theirGrid)
        else {
            return nil
        }
        return Self.bearing(from: myCoord, to: theirCoord)
    }

    private var sourceLabel: String {
        switch info.source {
        case .poloNotes:
            "from Polo Notes"
        case .qrz:
            "from QRZ"
        case .hamdb:
            "from HamDB"
        }
    }

    @ViewBuilder
    private var notesDisplay: some View {
        if notesDisplayMode == "sources" {
            // Show source names as chips
            if let sources = info.matchingSources, !sources.isEmpty {
                HStack(spacing: 4) {
                    ForEach(sources, id: \.self) { source in
                        Text(source)
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.2))
                            .clipShape(Capsule())
                    }
                }
            }
        } else {
            // Show combined emoji
            if let emoji = info.combinedEmoji {
                Text(emoji)
                    .font(.title2)
            }
        }
    }

    private var detailChips: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                if let qth = info.qth {
                    DetailChip(text: qth)
                }

                if let state = info.state {
                    DetailChip(text: state)
                }

                if let grid = info.grid {
                    DetailChip(text: grid)
                }

                if let country = info.country {
                    DetailChip(text: country)
                }
            }

            if distanceKm != nil || previousQSOCount > 0 {
                HStack(spacing: 8) {
                    if let km = distanceKm {
                        DetailChip(
                            text: UnitFormatter.distance(km),
                            icon: "arrow.triangle.swap"
                        )
                    }

                    if let deg = bearingDegrees {
                        DetailChip(
                            text: "\(Int(deg.rounded()))\u{00B0}",
                            icon: "location.north.fill",
                            iconRotation: deg
                        )
                    }

                    if previousQSOCount > 0 {
                        ContactCountBadge(count: previousQSOCount, showLabel: true)
                    }
                }
            }
        }
    }

    private var sourceIndicator: some View {
        HStack {
            Spacer()
            Text(sourceLabel)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    private func previousCallsignSection(_ previousCall: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.right.arrow.left")
                .foregroundStyle(.secondary)
                .font(.caption)

            Text("Previously \(previousCall)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 4)
    }

    private func callsignChangeSection(_ note: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .foregroundStyle(.orange)
                .font(.caption)

            Text(note)
                .font(.caption)
                .foregroundStyle(.orange)
        }
        .padding(.top, 4)
    }

    private func noteSection(_ note: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "note.text")
                .foregroundStyle(.secondary)
                .font(.caption)

            Text(CallsignInfo.parseNoteMarkdown(note))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 4)
    }

    /// Great-circle initial bearing between two coordinates
    private static func bearing(
        from: CLLocationCoordinate2D,
        to: CLLocationCoordinate2D
    ) -> Double {
        let lat1 = from.latitude * .pi / 180
        let lat2 = to.latitude * .pi / 180
        let dLon = (to.longitude - from.longitude) * .pi / 180
        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        let radians = atan2(y, x)
        return (radians * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
    }
}

// MARK: - DetailChip

struct DetailChip: View {
    let text: String
    var icon: String?
    var iconRotation: Double = 0

    var body: some View {
        HStack(spacing: 4) {
            if let icon {
                Image(systemName: icon)
                    .font(.caption2)
                    .rotationEffect(.degrees(iconRotation))
            }
            Text(text)
        }
        .font(.caption)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(.tertiarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

// MARK: - CompactCallsignBar

/// A compact single-line callsign info display for use above the keyboard
struct CompactCallsignBar: View {
    let info: CallsignInfo

    var body: some View {
        HStack(spacing: 8) {
            if let emoji = info.combinedEmoji {
                Text(emoji)
                    .font(.body)
            }

            if let name = info.displayName {
                Text(name)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
            }

            if let state = info.state {
                Text(state)
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color(.tertiarySystemBackground))
                    .clipShape(Capsule())
            }

            if let grid = info.grid {
                Text(grid.prefix(4))
                    .font(.caption.monospaced())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.blue.opacity(0.2))
                    .clipShape(Capsule())
            }

            Spacer()

            if let flag = CallsignFlagHelper.countryFlag(for: info.callsign) {
                Text(flag)
                    .font(.body)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(.secondarySystemBackground))
    }
}

// MARK: - CallsignLookupErrorBanner

/// Displays callsign lookup errors with actionable suggestions
struct CallsignLookupErrorBanner: View {
    // MARK: Internal

    let error: CallsignLookupError

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(iconColor)
                .font(.title3)

            VStack(alignment: .leading, spacing: 2) {
                Text(error.errorDescription ?? "Lookup failed")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)

                if let suggestion = error.recoverySuggestion {
                    Text(suggestion)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()
        }
        .padding()
        .background(backgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    /// Shared helpers for both banner and compact bar
    static func icon(for error: CallsignLookupError) -> String {
        switch error {
        case .noQRZApiKey,
             .noSourcesConfigured:
            "gear.badge.questionmark"
        case .qrzAuthFailed:
            "key.slash"
        case .networkError:
            "wifi.slash"
        case .notFound:
            "magnifyingglass"
        }
    }

    static func iconColor(for error: CallsignLookupError) -> Color {
        switch error {
        case .noQRZApiKey,
             .noSourcesConfigured:
            .orange
        case .qrzAuthFailed:
            .red
        case .networkError:
            .yellow
        case .notFound:
            .secondary
        }
    }

    static func backgroundColor(for error: CallsignLookupError) -> Color {
        switch error {
        case .noQRZApiKey,
             .noSourcesConfigured:
            Color.orange.opacity(0.15)
        case .qrzAuthFailed:
            Color.red.opacity(0.15)
        case .networkError:
            Color.yellow.opacity(0.15)
        case .notFound:
            Color(.secondarySystemGroupedBackground)
        }
    }

    // MARK: Private

    private var icon: String {
        CallsignLookupErrorBanner.icon(for: error)
    }

    private var iconColor: Color {
        CallsignLookupErrorBanner.iconColor(for: error)
    }

    private var backgroundColor: Color {
        CallsignLookupErrorBanner.backgroundColor(for: error)
    }
}

// MARK: - CompactLookupErrorBar

/// Compact error display for use above the keyboard
struct CompactLookupErrorBar: View {
    let error: CallsignLookupError

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: CallsignLookupErrorBanner.icon(for: error))
                .foregroundStyle(CallsignLookupErrorBanner.iconColor(for: error))
                .font(.subheadline)

            VStack(alignment: .leading, spacing: 2) {
                Text(error.errorDescription ?? "Lookup failed")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                if let suggestion = error.recoverySuggestion {
                    Text(suggestion)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(CallsignLookupErrorBanner.backgroundColor(for: error))
    }
}

// MARK: - CallsignFlagHelper

/// Shared country flag lookup from callsign prefix
enum CallsignFlagHelper {
    // MARK: Internal

    static func countryFlag(for callsign: String) -> String? {
        let cs = callsign.uppercased()
        for (prefix, flag) in prefixFlags where cs.hasPrefix(prefix) {
            return flag
        }
        return nil
    }

    // MARK: Private

    /// Ordered longest prefix first so 2-char prefixes match before 1-char
    private static let prefixFlags: [(prefix: String, flag: String)] = [
        ("VE", "🇨🇦"), ("VA", "🇨🇦"),
        ("DL", "🇩🇪"), ("DA", "🇩🇪"), ("DB", "🇩🇪"), ("DC", "🇩🇪"),
        ("JA", "🇯🇵"), ("JH", "🇯🇵"), ("JR", "🇯🇵"),
        ("VK", "🇦🇺"), ("ZL", "🇳🇿"), ("EA", "🇪🇸"),
        ("PA", "🇳🇱"), ("PD", "🇳🇱"), ("PE", "🇳🇱"),
        ("ON", "🇧🇪"), ("OZ", "🇩🇰"),
        ("SM", "🇸🇪"), ("SA", "🇸🇪"),
        ("LA", "🇳🇴"), ("OH", "🇫🇮"),
        ("W", "🇺🇸"), ("K", "🇺🇸"), ("N", "🇺🇸"), ("A", "🇺🇸"),
        ("G", "🇬🇧"), ("M", "🇬🇧"),
        ("F", "🇫🇷"), ("I", "🇮🇹"),
    ]
}

// MARK: - Preview

#Preview {
    VStack(spacing: 16) {
        LoggerCallsignCard(
            info: CallsignInfo(
                callsign: "W1AW",
                name: "ARRL Headquarters Station",
                note: "Official ARRL station - always great to work!",
                emoji: "🏛️",
                qth: "Newington",
                state: "CT",
                country: "United States",
                grid: "FN31pr",
                source: .poloNotes
            ),
            myGrid: "CN87"
        )

        LoggerCallsignCard(
            info: CallsignInfo(
                callsign: "DL1ABC",
                name: "Hans Mueller",
                note: nil,
                emoji: nil,
                qth: "Berlin",
                country: "Germany",
                grid: "JO31",
                source: .qrz
            ),
            myGrid: "CN87"
        )

        CallsignLookupErrorBanner(error: .noQRZApiKey)
        CallsignLookupErrorBanner(error: .qrzAuthFailed)
        CallsignLookupErrorBanner(error: .networkError("Connection timed out"))
    }
    .padding()
    .background(Color(.systemGroupedBackground))
}
