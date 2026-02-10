import SwiftUI

// MARK: - ActivityShareCardView

/// Share card for daily activity log stats.
/// Uses the existing ShareCardView + ShareCardContent infrastructure.
struct ActivityShareCardView: View {
    let content: ShareCardContent

    var body: some View {
        ShareCardView(content: content)
    }
}

// MARK: - ShareCardContent + ActivityLog

extension ShareCardContent {
    /// Create a share card for a day's activity log stats
    static func forDailyActivity(
        callsign: String,
        date: Date,
        qsoCount: Int,
        bands: Set<String>,
        modes: Set<String>
    ) -> ShareCardContent {
        let dateString = date.formatted(date: .abbreviated, time: .omitted)

        var stats: [ShareCardStat] = [
            ShareCardStat(label: "QSOs", value: "\(qsoCount)"),
            ShareCardStat(label: "Bands", value: "\(bands.count)"),
        ]

        if modes.count > 1 {
            stats.append(ShareCardStat(label: "Modes", value: "\(modes.count)"))
        } else if let mode = modes.first {
            stats.append(ShareCardStat(label: "Mode", value: mode))
        }

        let headline = if qsoCount >= 50 {
            "Monster Day on the Air!"
        } else if qsoCount >= 20 {
            "Great Day on the Air!"
        } else {
            "Day on the Air"
        }

        return ShareCardContent(
            iconName: "scope",
            headline: headline,
            subheadline: "\(qsoCount) QSOs across \(bands.count) band\(bands.count == 1 ? "" : "s")",
            stats: stats,
            callsign: callsign,
            dateRange: dateString
        )
    }
}
