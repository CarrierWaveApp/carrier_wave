import CarrierWaveCore
import Foundation

// Re-export from CarrierWaveCore
public typealias StreakResult = CarrierWaveCore.StreakResult
public typealias StreakCalculator = CarrierWaveCore.StreakCalculator

// MARK: - StreakCategory

enum StreakCategory: String, Identifiable, CaseIterable {
    case daily = "Daily QSOs"
    case pota = "POTA Activations"
    case hunter = "Park Hunts"
    case mode = "Mode"
    case band = "Band"

    // MARK: Internal

    var id: String {
        rawValue
    }

    var icon: String {
        switch self {
        case .daily: "flame.fill"
        case .pota: "leaf.fill"
        case .hunter: "binoculars.fill"
        case .mode: "waveform.path"
        case .band: "antenna.radiowaves.left.and.right"
        }
    }
}

// MARK: - StreakInfo

struct StreakInfo: Identifiable {
    /// Placeholder for loading states
    static let placeholder = StreakInfo(
        id: "placeholder",
        category: .daily,
        subcategory: nil,
        currentStreak: 0,
        longestStreak: 0,
        currentStartDate: nil,
        longestStartDate: nil,
        longestEndDate: nil,
        lastActiveDate: nil
    )

    let id: String
    let category: StreakCategory
    let subcategory: String? // Mode name or band name for specific streaks
    let currentStreak: Int
    let longestStreak: Int
    let currentStartDate: Date?
    let longestStartDate: Date?
    let longestEndDate: Date?
    let lastActiveDate: Date?

    /// True if active yesterday but not today (streak at risk of ending)
    var isAtRisk: Bool {
        guard let lastActive = lastActiveDate else {
            return false
        }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
        return calendar.isDate(lastActive, inSameDayAs: yesterday)
    }

    /// Display name combining category and subcategory
    var displayName: String {
        if let subcategory {
            return "\(subcategory) \(category.rawValue)"
        }
        return category.rawValue
    }
}
