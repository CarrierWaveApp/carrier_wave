import CarrierWaveData
import Foundation

// MARK: - StatsReport

/// Structured diagnostic bundle for stats accuracy reporting.
/// Contains all information needed to debug why a statistic is wrong.
struct StatsReport: Codable {
    let version: Int
    let generatedAt: Date
    let appVersion: String
    let userReport: UserReport
    let statsSnapshot: StatsSnapshot
    let matchingQSOs: [QSODiagnostic]
    let excludedQSOs: [QSODiagnostic]
    let filterTrace: FilterTrace
    let environment: EnvironmentContext
}

// MARK: - UserReport

struct UserReport: Codable {
    let category: String
    let identifier: String?
    let computedValue: Int
    let expectedValue: Int
    let flaggedCallsigns: [String]
    let comment: String
}

// MARK: - StatsSnapshot

struct StatsSnapshot: Codable {
    let totalRealQSOs: Int
    let totalSnapshots: Int
    let hiddenQSOCount: Int
    let metadataExcludedCount: Int
    let deduplicatedCount: Int
    let categoryItems: [CategoryItemSnapshot]
}

// MARK: - CategoryItemSnapshot

struct CategoryItemSnapshot: Codable {
    let identifier: String
    let description: String
    let count: Int
    let qsoIds: [String]
}

// MARK: - QSODiagnostic

/// Detailed QSO record for diagnostic purposes.
struct QSODiagnostic: Codable {
    let id: String
    let callsign: String
    let mode: String
    let band: String
    let frequency: Double?
    let timestamp: Date
    let parkReference: String?
    let gridSquare: String?
    let isHidden: Bool
    let isMetadata: Bool
    let qrzConfirmed: Bool
    let lotwConfirmed: Bool
    let dxccNumber: Int?
    let dxccEntity: String?
    let loggingSessionId: String?
    let importSource: String
    let exclusionReason: String?
}

// MARK: - FilterTrace

struct FilterTrace: Codable {
    let summary: String
    let totalMatched: Int
    let totalExcluded: Int
    let excludedByReason: [String: Int]
    let details: [FilterTraceEntry]
}

// MARK: - FilterTraceEntry

struct FilterTraceEntry: Codable {
    let qsoId: String
    let callsign: String
    let timestamp: Date
    let decision: String
    let reason: String
}

// MARK: - EnvironmentContext

struct EnvironmentContext: Codable {
    let appVersion: String
    let buildNumber: String
    let totalQSOCount: Int
    let realQSOCount: Int
    let hiddenQSOCount: Int
    let deduplicationCount: Int
    let computationTimestamp: Date?
    let computationGeneration: Int
}
