import CarrierWaveData
import Foundation

// MARK: - ActivityType

enum ActivityType: String, Codable, CaseIterable {
    case challengeTierUnlock
    case challengeCompletion
    case newDXCCEntity
    case newBand
    case newMode
    case dxContact
    case potaActivation
    case sotaActivation
    case dailyStreak
    case potaDailyStreak
    case personalBest
    case workedFriend
    case sessionCompleted

    // MARK: Internal

    var icon: String {
        switch self {
        case .challengeTierUnlock: "trophy.fill"
        case .challengeCompletion: "flag.checkered"
        case .newDXCCEntity: "globe"
        case .newBand: "antenna.radiowaves.left.and.right"
        case .newMode: "waveform"
        case .dxContact: "location.circle"
        case .potaActivation: "leaf.fill"
        case .sotaActivation: "mountain.2.fill"
        case .dailyStreak: "flame.fill"
        case .potaDailyStreak: "flame.fill"
        case .personalBest: "chart.line.uptrend.xyaxis"
        case .workedFriend: "person.line.dotted.person.fill"
        case .sessionCompleted: "checkmark.seal.fill"
        }
    }

    var displayName: String {
        switch self {
        case .challengeTierUnlock: "Tier Unlocked"
        case .challengeCompletion: "Challenge Complete"
        case .newDXCCEntity: "New DXCC Entity"
        case .newBand: "New Band"
        case .newMode: "New Mode"
        case .dxContact: "DX Contact"
        case .potaActivation: "POTA Activation"
        case .sotaActivation: "SOTA Activation"
        case .dailyStreak: "Daily Streak"
        case .potaDailyStreak: "POTA Streak"
        case .personalBest: "Personal Best"
        case .workedFriend: "Worked Friend"
        case .sessionCompleted: "Session Complete"
        }
    }

    /// Short noun for "Hide this ___" menu labels
    var feedItemName: String {
        switch self {
        case .challengeTierUnlock,
             .challengeCompletion: "achievement"
        case .newDXCCEntity,
             .newBand,
             .newMode: "milestone"
        case .dxContact,
             .workedFriend: "contact"
        case .potaActivation,
             .sotaActivation: "activation"
        case .dailyStreak,
             .potaDailyStreak: "streak"
        case .personalBest: "record"
        case .sessionCompleted: "session"
        }
    }
}
