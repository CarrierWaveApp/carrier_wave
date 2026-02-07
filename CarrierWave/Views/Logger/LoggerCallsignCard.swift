// swiftlint:disable cyclomatic_complexity
import CarrierWaveCore
import SwiftUI

// MARK: - LoggerCallsignCard

/// Displays callsign lookup information in the logger
struct LoggerCallsignCard: View {
    // MARK: Internal

    let info: CallsignInfo
    var previousQSOCount: Int = 0

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

                if let flag = countryFlag(for: info) {
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

            sourceIndicator
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: Private

    @AppStorage("callsignNotesDisplayMode") private var notesDisplayMode = "emoji"

    private var hasDetails: Bool {
        info.grid != nil || info.state != nil || info.country != nil || previousQSOCount > 0
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
        HStack(spacing: 8) {
            if let state = info.state {
                DetailChip(text: state)
            }

            if let grid = info.grid {
                DetailChip(text: grid)
            }

            if let country = info.country {
                DetailChip(text: country)
            }

            if previousQSOCount > 0 {
                DetailChip(
                    text: "\(previousQSOCount) prev QSO\(previousQSOCount == 1 ? "" : "s")"
                )
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

    private func noteSection(_ note: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "note.text")
                .foregroundStyle(.secondary)
                .font(.caption)

            Group {
                if let attributed = try? AttributedString(markdown: note) {
                    Text(attributed)
                } else {
                    Text(note)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(2)
        }
        .padding(.top, 4)
    }

    private func countryFlag(for info: CallsignInfo) -> String? {
        // Try to determine country from callsign prefix
        let callsign = info.callsign.uppercased()

        // Common prefixes to flags
        if callsign.hasPrefix("W") || callsign.hasPrefix("K") || callsign.hasPrefix("N")
            || callsign.hasPrefix("A")
        {
            return "🇺🇸"
        } else if callsign.hasPrefix("VE") || callsign.hasPrefix("VA") {
            return "🇨🇦"
        } else if callsign.hasPrefix("G") || callsign.hasPrefix("M") {
            return "🇬🇧"
        } else if callsign.hasPrefix("DL") || callsign.hasPrefix("DA") || callsign.hasPrefix("DB")
            || callsign.hasPrefix("DC")
        {
            return "🇩🇪"
        } else if callsign.hasPrefix("F") {
            return "🇫🇷"
        } else if callsign.hasPrefix("JA") || callsign.hasPrefix("JH") || callsign.hasPrefix("JR") {
            return "🇯🇵"
        } else if callsign.hasPrefix("VK") {
            return "🇦🇺"
        } else if callsign.hasPrefix("ZL") {
            return "🇳🇿"
        } else if callsign.hasPrefix("EA") {
            return "🇪🇸"
        } else if callsign.hasPrefix("I") {
            return "🇮🇹"
        } else if callsign.hasPrefix("PA") || callsign.hasPrefix("PD") || callsign.hasPrefix("PE") {
            return "🇳🇱"
        } else if callsign.hasPrefix("ON") {
            return "🇧🇪"
        } else if callsign.hasPrefix("OZ") {
            return "🇩🇰"
        } else if callsign.hasPrefix("SM") || callsign.hasPrefix("SA") {
            return "🇸🇪"
        } else if callsign.hasPrefix("LA") {
            return "🇳🇴"
        } else if callsign.hasPrefix("OH") {
            return "🇫🇮"
        }

        return nil
    }
}

// MARK: - DetailChip

struct DetailChip: View {
    let text: String

    var body: some View {
        Text(text)
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
    // MARK: Internal

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

            if let flag = countryFlag(for: info) {
                Text(flag)
                    .font(.body)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(.secondarySystemBackground))
    }

    // MARK: Private

    private func countryFlag(for info: CallsignInfo) -> String? {
        let callsign = info.callsign.uppercased()

        if callsign.hasPrefix("W") || callsign.hasPrefix("K") || callsign.hasPrefix("N")
            || callsign.hasPrefix("A")
        {
            return "🇺🇸"
        } else if callsign.hasPrefix("VE") || callsign.hasPrefix("VA") {
            return "🇨🇦"
        } else if callsign.hasPrefix("G") || callsign.hasPrefix("M") {
            return "🇬🇧"
        } else if callsign.hasPrefix("DL") || callsign.hasPrefix("DA") || callsign.hasPrefix("DB")
            || callsign.hasPrefix("DC")
        {
            return "🇩🇪"
        } else if callsign.hasPrefix("F") {
            return "🇫🇷"
        } else if callsign.hasPrefix("JA") || callsign.hasPrefix("JH") || callsign.hasPrefix("JR") {
            return "🇯🇵"
        } else if callsign.hasPrefix("VK") {
            return "🇦🇺"
        } else if callsign.hasPrefix("ZL") {
            return "🇳🇿"
        }

        return nil
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

// MARK: - Preview

#Preview {
    VStack(spacing: 16) {
        LoggerCallsignCard(
            info: CallsignInfo(
                callsign: "W1AW",
                name: "ARRL Headquarters Station",
                note: "Official ARRL station - always great to work!",
                emoji: "🏛️",
                state: "CT",
                country: "United States",
                grid: "FN31pr",
                source: .poloNotes
            )
        )

        LoggerCallsignCard(
            info: CallsignInfo(
                callsign: "DL1ABC",
                name: "Hans Mueller",
                note: nil,
                emoji: nil,
                country: "Germany",
                grid: "JO31",
                source: .qrz
            )
        )

        CallsignLookupErrorBanner(error: .noQRZApiKey)
        CallsignLookupErrorBanner(error: .qrzAuthFailed)
        CallsignLookupErrorBanner(error: .networkError("Connection timed out"))
    }
    .padding()
    .background(Color(.systemGroupedBackground))
}
