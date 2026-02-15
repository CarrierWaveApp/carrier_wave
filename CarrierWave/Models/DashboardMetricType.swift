import CarrierWaveCore
import Foundation

// MARK: - MetricDisplayValue

enum MetricDisplayValue {
    case streak(StreakInfo?)
    case count(Int)
}

// MARK: - DashboardMetricType

enum DashboardMetricType: String, CaseIterable, Codable, Identifiable {
    // Streaks
    case onAir
    case activation
    case hunter
    case cw
    case phone
    case digital

    // Counts
    case qsosWeek
    case qsosMonth
    case qsosYear
    case activationsMonth
    case activationsYear
    case huntsWeek
    case huntsMonth
    case newDXCCYear

    // MARK: Internal

    static var streakCases: [DashboardMetricType] {
        allCases.filter(\.isStreak)
    }

    static var countCases: [DashboardMetricType] {
        allCases.filter { !$0.isStreak }
    }

    var id: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .onAir: "On-Air Streak"
        case .activation: "Activation Streak"
        case .hunter: "Hunter Streak"
        case .cw: "CW Streak"
        case .phone: "Phone Streak"
        case .digital: "Digital Streak"
        case .qsosWeek: "QSOs This Week"
        case .qsosMonth: "QSOs This Month"
        case .qsosYear: "QSOs This Year"
        case .activationsMonth: "Activations This Month"
        case .activationsYear: "Activations This Year"
        case .huntsWeek: "Parks Hunted This Week"
        case .huntsMonth: "Parks Hunted This Month"
        case .newDXCCYear: "New DXCC This Year"
        }
    }

    var subtitle: String {
        switch self {
        case .onAir: "Days in a row with any contact"
        case .activation: "Days in a row with a valid activation"
        case .hunter: "Days in a row hunting a park"
        case .cw: "Consecutive days on CW"
        case .phone: "Consecutive days on voice"
        case .digital: "Consecutive days on digital"
        case .qsosWeek: "Last 7 days"
        case .qsosMonth: "This calendar month"
        case .qsosYear: "This calendar year"
        case .activationsMonth: "Valid activations this month"
        case .activationsYear: "Valid activations this year"
        case .huntsWeek: "Distinct parks in last 7 days"
        case .huntsMonth: "Distinct parks this month"
        case .newDXCCYear: "First worked this year"
        }
    }

    var icon: String {
        switch self {
        case .onAir: "flame.fill"
        case .activation: "leaf.fill"
        case .hunter: "binoculars.fill"
        case .cw: "waveform.path"
        case .phone: "mic.fill"
        case .digital: "desktopcomputer"
        case .qsosWeek,
             .qsosMonth,
             .qsosYear:
            "antenna.radiowaves.left.and.right"
        case .activationsMonth,
             .activationsYear: "leaf"
        case .huntsWeek,
             .huntsMonth: "binoculars"
        case .newDXCCYear: "globe"
        }
    }

    var isStreak: Bool {
        switch self {
        case .onAir,
             .activation,
             .hunter,
             .cw,
             .phone,
             .digital:
            true
        case .qsosWeek,
             .qsosMonth,
             .qsosYear,
             .activationsMonth,
             .activationsYear,
             .huntsWeek,
             .huntsMonth,
             .newDXCCYear:
            false
        }
    }
}
