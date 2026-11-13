import SwiftUI

// MARK: - ActivityGridColors

/// Colours shared by the Field and CW Sweep activity grids.
public enum ActivityGridColors {
    /// Green for activations (POTA sessions) — matches original grid color
    public static let activation = Color.green
    /// Blue for hunter QSOs (not part of an activation session) — system color, adapts to dark mode
    public static let activityLog = Color.blue
    /// Purple for Another Morse Trainer practice days — the one hue the grid
    /// and streak palette (green activation, blue hunter, teal/orange streak
    /// icons, cyan CW mode) leave free, and distinct from both QSO kinds
    public static let amtPractice = Color.purple
    // Empty cell
    #if canImport(UIKit)
        public static let empty = Color(.systemGray5)
    #else
        public static let empty = Color(nsColor: .quaternarySystemFill)
    #endif
}

// MARK: - ActivityGridCell

/// One day of the activity grid. QSO colouring (green activation / blue hunter,
/// diagonal split when both) with Another Morse Trainer practice layered on: a
/// practice-only day is a solid purple cell shaded by AMT's level; a day with
/// both QSOs and practice keeps the QSO colouring and gains a purple corner dot.
public struct ActivityGridCell: View {
    // MARK: Lifecycle

    public init(activationCount: Int, activityLogCount: Int, amt: AMTDayActivity?, maxCount: Int) {
        self.activationCount = activationCount
        self.activityLogCount = activityLogCount
        self.amt = amt
        self.maxCount = maxCount
    }

    // MARK: Public

    public var body: some View {
        if let amt, activationCount == 0, activityLogCount == 0 {
            RoundedRectangle(cornerRadius: 2)
                .fill(ActivityGridColors.amtPractice.opacity(amt.intensity))
        } else if let amt {
            ZStack(alignment: .bottomTrailing) {
                qsoCell
                Circle()
                    .fill(ActivityGridColors.amtPractice.opacity(amt.intensity))
                    .frame(width: 5, height: 5)
                    .padding(1.5)
            }
        } else {
            qsoCell
        }
    }

    // MARK: Internal

    let activationCount: Int
    let activityLogCount: Int
    let amt: AMTDayActivity?
    let maxCount: Int

    // MARK: Private

    @ViewBuilder
    private var qsoCell: some View {
        if activationCount == 0, activityLogCount == 0 {
            RoundedRectangle(cornerRadius: 2)
                .fill(ActivityGridColors.empty)
        } else if activationCount > 0, activityLogCount > 0 {
            // Diagonal split: activation top-left, hunter bottom-right
            Canvas { context, size in
                var topLeft = Path()
                topLeft.move(to: .zero)
                topLeft.addLine(to: CGPoint(x: size.width, y: 0))
                topLeft.addLine(to: CGPoint(x: 0, y: size.height))
                topLeft.closeSubpath()
                context.fill(
                    topLeft,
                    with: .color(
                        ActivityGridColors.activation
                            .opacity(intensityFor(count: activationCount, max: maxCount))
                    )
                )

                var bottomRight = Path()
                bottomRight.move(to: CGPoint(x: size.width, y: 0))
                bottomRight.addLine(to: CGPoint(x: size.width, y: size.height))
                bottomRight.addLine(to: CGPoint(x: 0, y: size.height))
                bottomRight.closeSubpath()
                context.fill(
                    bottomRight,
                    with: .color(
                        ActivityGridColors.activityLog
                            .opacity(intensityFor(count: activityLogCount, max: maxCount))
                    )
                )
            }
        } else if activationCount > 0 {
            RoundedRectangle(cornerRadius: 2)
                .fill(
                    ActivityGridColors.activation
                        .opacity(intensityFor(count: activationCount, max: maxCount))
                )
        } else {
            RoundedRectangle(cornerRadius: 2)
                .fill(
                    ActivityGridColors.activityLog
                        .opacity(intensityFor(count: activityLogCount, max: maxCount))
                )
        }
    }

    private func intensityFor(count: Int, max maxCount: Int) -> Double {
        guard count > 0 else {
            return 0
        }
        return 0.3 + min(Double(count) / Double(max(maxCount, 1)), 1.0) * 0.7
    }
}
