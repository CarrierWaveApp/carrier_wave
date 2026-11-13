import UIKit

// MARK: - SettingsSearchDestination

enum SettingsSearchDestination: Hashable {
    // Top-level category views
    case appearance
    case logger
    case potaActivations
    case syncSources
    case dataTools
    case aboutMe
    // Nested views reachable from categories
    case tabConfiguration
    case dashboardMetrics
    case onAirNow
    case huntP2P
    case contestCalendar
    case experiments
    case keyboardRow
    case commandRow
    case keyboardRows
    case prefixRow
    case webSDRRecordings
    case webSDRFavorites
    case activityLogSettings
    case myEquipment
    case qrzCallbook
    case callsignNotes
    case externalData
    case attributions
    case syncDebug
    case hiddenQSOs
    case spotlightDebug
    // Sync source detail views
    case qrzLogbook
    case pota
    case lofi
    case hamrs
    case lotw
    case clublog
    case eqsl
    case icloud
    case tota
    case activities
    case amt
    case wsjtx
    case callsignAliases
    case backups
}
