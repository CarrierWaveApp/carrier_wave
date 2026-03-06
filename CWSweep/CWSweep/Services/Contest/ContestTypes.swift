import CarrierWaveData
import Foundation

// MARK: - DupeStatus

/// Result of checking whether a QSO is a dupe
enum DupeStatus: Sendable, Equatable {
    case newMultiplier(value: String, MultiplierType)
    case newStation
    case dupe
}

// MARK: - QSOContestSnapshot

/// Lightweight Sendable snapshot of a QSO for contest engine processing
struct QSOContestSnapshot: Sendable {
    var callsign: String
    var band: String
    var mode: String
    var timestamp: Date
    var rstSent: String
    var rstReceived: String
    var exchangeSent: String
    var exchangeReceived: String
    var serialSent: Int?
    var serialReceived: Int?
    var country: String?
    var dxcc: Int?
    var cqZone: Int?
    var ituZone: Int?
    var state: String?
    var arrlSection: String?
    var county: String?
    var wpxPrefix: String?
}

// MARK: - ContestScoreSnapshot

/// Current contest score state
struct ContestScoreSnapshot: Sendable, Equatable {
    var totalQSOs: Int = 0
    var totalPoints: Int = 0
    var multiplierCount: Int = 0
    var finalScore: Int = 0
    var qsosByBand: [String: Int] = [:]
    var pointsByBand: [String: Int] = [:]
    var multsByBand: [String: Int] = [:]
    var dupeCount: Int = 0
}

// MARK: - ContestOperatingMode

/// CQ (calling) vs Search & Pounce
enum ContestOperatingMode: String, Sendable {
    case cq
    case sp
}
