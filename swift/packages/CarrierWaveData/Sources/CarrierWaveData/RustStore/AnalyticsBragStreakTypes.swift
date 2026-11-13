import Foundation

// Streak-shaped brag-sheet DTOs (mirror cw-store `BragStreaks` / `StreakValue` / `ModeStreak`).
// See AnalyticsReadSource+BragStreaks.swift.

// MARK: - StreakValueRow

/// A current/longest streak pair in calendar days (mirrors cw-store `StreakValue`).
public struct StreakValueRow: Equatable, Sendable {
    // MARK: Lifecycle

    public init(current: Int, longest: Int) {
        self.current = current
        self.longest = longest
    }

    // MARK: Public

    public let current: Int
    public let longest: Int
}

// MARK: - ModeStreakRow

/// A per-mode-family day streak (mirrors cw-store `ModeStreak`). `mode` ∈ "CW"/"Phone"/"Digital".
public struct ModeStreakRow: Equatable, Sendable {
    // MARK: Lifecycle

    public init(mode: String, current: Int, longest: Int) {
        self.mode = mode
        self.current = current
        self.longest = longest
    }

    // MARK: Public

    public let mode: String
    public let current: Int
    public let longest: Int
}

// MARK: - BragStreaksResult

/// Streak-shaped brag-sheet stats (mirrors cw-store `BragStreaks` /
/// `BragSheetComputationActor+Records`'s streak math). All day-bucketing is UTC. `activation`
/// is `nil` when no day has a successful (≥ 10 unique-QSO) activation (the `.noData` case).
public struct BragStreaksResult: Equatable, Sendable {
    // MARK: Lifecycle

    public init(onAir: StreakValueRow, activation: StreakValueRow?, modes: [ModeStreakRow]) {
        self.onAir = onAir
        self.activation = activation
        self.modes = modes
    }

    // MARK: Public

    /// Consecutive UTC days with any visible QSO (on-air streak).
    public let onAir: StreakValueRow
    /// Consecutive UTC days with a successful park activation, or `nil` when none qualify.
    public let activation: StreakValueRow?
    /// Per mode-family (CW/Phone/Digital order) day streaks; families with ≥ 1 QSO only.
    public let modes: [ModeStreakRow]
}
