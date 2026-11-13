// Event Timeline Bar
//
// Horizontal timeline showing event start → now → expiry with a
// filled progress bar and labeled timestamps. Used by space weather
// views to visualize event lifetime.

import SwiftUI

// MARK: - EventTimelineBar

struct EventTimelineBar: View {
    // MARK: Internal

    let startDate: Date
    let expiryDate: Date
    let accentColor: Color

    var body: some View {
        let now = Date()
        let totalDuration = expiryDate.timeIntervalSince(startDate)
        let elapsed = now.timeIntervalSince(startDate)
        let progress = totalDuration > 0
            ? min(max(elapsed / totalDuration, 0), 1)
            : 0

        VStack(spacing: 4) {
            // Timeline bar
            GeometryReader { proxy in
                let barWidth = proxy.size.width
                ZStack(alignment: .leading) {
                    // Track
                    Capsule()
                        .fill(Color(.systemGray4))
                        .frame(height: 6)

                    // Fill
                    Capsule()
                        .fill(accentColor.opacity(0.7))
                        .frame(
                            width: barWidth * progress,
                            height: 6
                        )

                    // "Now" indicator
                    Circle()
                        .fill(accentColor)
                        .frame(width: 10, height: 10)
                        .offset(x: barWidth * progress - 5)
                }
            }
            .frame(height: 10)

            // Time labels
            HStack {
                Text(Self.formatTime(startDate))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)

                Spacer()

                Text(Self.timeRemaining(until: expiryDate))
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(
                        progress > 0.8
                            ? .secondary
                            : accentColor
                    )

                Spacer()

                Text(Self.formatTime(expiryDate))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: Private

    private static func formatTime(_ date: Date) -> String {
        let fmt = DateFormatter()
        let cal = Calendar.current
        if cal.isDateInToday(date) {
            fmt.dateFormat = "HH:mm"
        } else {
            fmt.dateFormat = "MMM d, HH:mm"
        }
        return fmt.string(from: date)
    }

    private static func timeRemaining(until date: Date) -> String {
        let remaining = date.timeIntervalSince(Date())
        if remaining <= 0 {
            return "expired"
        }
        let hours = Int(remaining) / 3_600
        let minutes = (Int(remaining) % 3_600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m left"
        }
        return "\(minutes)m left"
    }
}
