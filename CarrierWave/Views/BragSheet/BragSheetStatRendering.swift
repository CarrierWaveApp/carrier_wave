import SwiftUI

// MARK: - Subtitle Display

extension BragSheetStatValue {
    /// Secondary text displayed below the hero value.
    var subtitleDisplay: String? {
        switch self {
        case .count: "contacts"
        case let .distance(km): UnitFormatter.distance(km)
        case let .duration(seconds): formatDurationSpelled(seconds)
        case let .rate(_, label): label
        case let .contact(_, distKm, band):
            contactSubtitle(distanceKm: distKm, band: band)
        case let .power(_, call, distKm, band):
            powerSubtitle(callsign: call, distanceKm: distKm, band: band)
        case let .efficiency(_, detail): detail
        case let .progress(_, total): "of \(total) worked"
        case let .streak(_, longest): "Best: \(longest)d"
        case .bandTable: nil
        case let .dayOfWeek(_, count): "\(count) QSOs"
        case let .callsignCount(_, count): "\(count) contacts"
        case .timeOfDay: nil
        case let .parkDetail(_, date, count):
            parkDetailSubtitle(date: date, count: count)
        case .modeStreakList: nil
        case .wpm: "WPM"
        case let .rst(_, detail): detail
        case .noData: nil
        }
    }

    private func contactSubtitle(distanceKm: Double?, band: String?) -> String {
        var parts: [String] = []
        if let band {
            parts.append(band)
        }
        if let distKm = distanceKm {
            parts.append(UnitFormatter.distance(distKm))
        }
        return parts.joined(separator: " · ")
    }

    private func powerSubtitle(
        callsign: String, distanceKm: Double?, band: String?
    ) -> String {
        var parts = [callsign]
        if let band {
            parts.append(band)
        }
        if let distKm = distanceKm {
            parts.append(UnitFormatter.distance(distKm))
        }
        return parts.joined(separator: " · ")
    }

    private func parkDetailSubtitle(date: Date?, count: Int) -> String {
        var parts: [String] = []
        if let date {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .none
            parts.append(formatter.string(from: date))
        }
        parts.append("\(count) QSOs")
        return parts.joined(separator: " · ")
    }

    private func formatDurationSpelled(_ seconds: TimeInterval) -> String {
        let totalMinutes = Int(seconds / 60)
        if totalMinutes < 60 {
            return "\(totalMinutes) minutes"
        }
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if minutes == 0 {
            return "\(hours) hours"
        }
        return "\(hours)h \(minutes)m"
    }
}

// MARK: - BragInlineTableCell

/// Renders inline content for bandTable and modeStreakList values
/// that don't fit the standard hero/subtitle pattern.
struct BragInlineTableCell: View {
    // MARK: Internal

    let value: BragSheetStatValue

    var body: some View {
        switch value {
        case let .bandTable(entries):
            bandTableView(entries: Array(entries.prefix(3)))
        case let .modeStreakList(entries):
            modeStreakView(entries: entries)
        default:
            EmptyView()
        }
    }

    // MARK: Private

    // MARK: - Band Table

    @ViewBuilder
    private func bandTableView(entries: [BandTableEntry]) -> some View {
        if entries.isEmpty {
            Text("--")
                .foregroundStyle(.secondary)
        } else {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(entries) { entry in
                    HStack(spacing: 8) {
                        Text(entry.band)
                            .font(.caption)
                            .fontWeight(.medium)
                            .frame(width: 40, alignment: .leading)
                        Text(entry.callsign)
                            .font(.caption)
                            .fontDesign(.monospaced)
                        Spacer()
                        Text(UnitFormatter.distanceCompact(entry.distanceKm))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    // MARK: - Mode Streaks

    @ViewBuilder
    private func modeStreakView(entries: [ModeStreakEntry]) -> some View {
        if entries.isEmpty {
            Text("--")
                .foregroundStyle(.secondary)
        } else {
            FlowLayout(spacing: 6) {
                ForEach(entries) { entry in
                    modeChip(entry)
                }
            }
        }
    }

    private func modeChip(_ entry: ModeStreakEntry) -> some View {
        HStack(spacing: 4) {
            Text(entry.mode)
                .font(.caption2)
                .fontWeight(.medium)
            Text("\(entry.current)d")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(.systemGray5))
        .clipShape(Capsule())
    }
}

// Uses existing FlowLayout from SpotFilterSheet.swift
