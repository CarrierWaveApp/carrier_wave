// Shared visual treatment for all session brag sheets — TOTA, POTA, contests,
// casual sessions. Both `SessionBragSheetCard` (activity-feed, ActivityItem-
// driven) and `TOTABragSheetView` (detail/end-flow, LoggingSession-driven)
// use this so the cards look consistent in every surface.

import SwiftUI

// MARK: - BragSheetTheme

enum BragSheetTheme {
    /// Card gradient — purple-violet, slightly brighter than the prior
    /// dark-navy treatment. Matches the TOTA brag sheet that operators
    /// liked.
    static var cardBackground: some ShapeStyle {
        LinearGradient(
            colors: [
                Color(red: 0.16, green: 0.10, blue: 0.32),
                Color(red: 0.28, green: 0.14, blue: 0.45),
                Color(red: 0.16, green: 0.10, blue: 0.32),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    /// Pale background for inset stat strips and chip rows on the dark card.
    static var insetBackground: Color {
        Color.white.opacity(0.06)
    }

    /// Background for chip pills.
    static var chipBackground: Color {
        Color.white.opacity(0.12)
    }

    /// Card border.
    static var border: Color {
        Color.white.opacity(0.10)
    }
}

// MARK: - BragSheetChip

/// Pill chip used for bonus flags / badges on dark brag-sheet backgrounds.
struct BragSheetChip: View {
    let label: String
    var icon: String?

    var body: some View {
        HStack(spacing: 4) {
            if let icon {
                Image(systemName: icon)
                    .font(.caption2)
            }
            Text(label)
                .font(.caption2.weight(.medium))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .foregroundStyle(.white)
        .background(BragSheetTheme.chipBackground)
        .clipShape(Capsule())
    }
}

// MARK: - BragSheetStatColumn

/// Single value/label column for the inset stat strip.
struct BragSheetStatColumn: View {
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.subheadline.monospacedDigit().weight(.semibold))
                .foregroundStyle(.white)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.6))
        }
        .frame(maxWidth: .infinity)
    }
}
