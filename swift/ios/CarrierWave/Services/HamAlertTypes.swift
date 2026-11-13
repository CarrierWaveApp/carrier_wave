// HamAlert Types
//
// Shared types for the HamAlert exporter: triggers, conditions,
// results, and error types.

import Foundation

// MARK: - TriggerEntry

nonisolated struct TriggerEntry: Decodable {
    enum CodingKeys: String, CodingKey {
        // swiftlint:disable:next identifier_name
        case _id
        case name
    }

    // swiftlint:disable:next identifier_name
    let _id: String
    let name: String

    var id: String {
        _id
    }
}

// MARK: - HamAlertConditions

nonisolated struct HamAlertConditions: Codable {
    let callsign: String?
    let state: String?
    let mode: String?
}

// MARK: - HamAlertTrigger

nonisolated struct HamAlertTrigger: Codable {
    let name: String
    let conditions: HamAlertConditions
    let comment: String?
    let actions: [String]
}

// MARK: - HamAlertExportResult

nonisolated struct HamAlertExportResult {
    let triggersCreated: Int
    let triggersDeleted: Int
    let totalNeeds: Int
}

// MARK: - HamAlertRestoreResult

nonisolated struct HamAlertRestoreResult {
    let triggersRestored: Int
    let triggersDeleted: Int
    let totalInBackup: Int
}

// MARK: - HamAlertError

nonisolated enum HamAlertError: Error, LocalizedError {
    case invalidURL
    case loginFailed
    case createFailed
    case noCredentials
    case restoreFailed

    // MARK: Internal

    var errorDescription: String? {
        switch self {
        case .invalidURL: "Invalid HamAlert API URL"
        case .loginFailed: "HamAlert login failed — check username/password"
        case .createFailed: "Failed to create HamAlert trigger"
        case .noCredentials: "HamAlert credentials not configured"
        case .restoreFailed: "Failed to read backup data"
        }
    }
}
