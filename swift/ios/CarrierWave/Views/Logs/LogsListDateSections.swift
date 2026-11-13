import CarrierWaveData
import SwiftUI

// MARK: - DateSection

/// A group of QSOs sharing the same UTC calendar day, for display in section headers.
struct DateSection {
    let key: String
    let label: String
    let qsos: [QSORowSnapshot]
}

// MARK: - DateSectionHeader

/// Sticky section header showing the date label and QSO count for a day group.
struct DateSectionHeader: View {
    let label: String
    let count: Int

    var body: some View {
        HStack {
            Text(label)
                .font(.subheadline.weight(.semibold))
            Spacer()
            Text("\(count)")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
        .background(Color(.systemBackground))
    }
}

// MARK: - Date Grouping

extension LogsListContentView {
    /// Formatter that produces a stable key per UTC calendar day (e.g. "2026-03-18").
    static let sectionDayFormatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        fmt.timeZone = TimeZone(identifier: "UTC")
        return fmt
    }()

    /// Formatter for display labels (e.g. "Mar 18, 2026").
    private static let sectionDisplayFormatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.dateFormat = "MMM d, yyyy"
        fmt.timeZone = TimeZone(identifier: "UTC")
        return fmt
    }()

    /// Returns a human-readable label like "Today", "Yesterday", or "Mar 15, 2026".
    static func relativeLabel(for date: Date) -> String {
        let utc = TimeZone(identifier: "UTC")!
        var calendar = Calendar.current
        calendar.timeZone = utc
        let now = Date()

        if calendar.isDateInToday(date) {
            return "Today"
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday"
        } else if let weekAgo = calendar.date(byAdding: .day, value: -6, to: now),
                  date >= calendar.startOfDay(for: weekAgo)
        {
            // Within last 7 days — show day name (e.g. "Tuesday")
            let dayFmt = DateFormatter()
            dayFmt.dateFormat = "EEEE"
            dayFmt.timeZone = utc
            return dayFmt.string(from: date)
        }
        return sectionDisplayFormatter.string(from: date)
    }

    /// Groups the loaded snapshots into date sections for display.
    /// Rows are already sorted reverse-chronologically, so we walk them in order
    /// and split on UTC day boundaries.
    var groupedByDate: [DateSection] {
        guard !snapshots.isEmpty else {
            return []
        }
        var sections: [DateSection] = []
        var currentKey = ""
        var currentLabel = ""
        var currentBatch: [QSORowSnapshot] = []

        for qso in snapshots {
            let key = Self.sectionDayFormatter.string(from: qso.timestamp)
            if key != currentKey {
                if !currentBatch.isEmpty {
                    sections.append(DateSection(
                        key: currentKey, label: currentLabel, qsos: currentBatch
                    ))
                }
                currentKey = key
                currentLabel = Self.relativeLabel(for: qso.timestamp)
                currentBatch = [qso]
            } else {
                currentBatch.append(qso)
            }
        }
        if !currentBatch.isEmpty {
            sections.append(DateSection(
                key: currentKey, label: currentLabel, qsos: currentBatch
            ))
        }
        return sections
    }
}
