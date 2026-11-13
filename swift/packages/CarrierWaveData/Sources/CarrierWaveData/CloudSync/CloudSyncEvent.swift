// CarrierWaveData/Sources/CarrierWaveData/CloudSync/CloudSyncEvent.swift
import Foundation

// MARK: - CloudSyncEvent

/// A single sync event for the activity log. Stored as JSON, not SwiftData.
public struct CloudSyncEvent: Codable, Sendable, Identifiable {
    // MARK: Lifecycle

    public init(
        timestamp: Date = Date(),
        category: Category,
        entityType: String? = nil,
        detail: String,
        recordCount: Int? = nil,
        duration: TimeInterval? = nil,
        byteCount: Int64? = nil,
        journalTailCount: Int? = nil
    ) {
        id = UUID()
        self.timestamp = timestamp
        self.category = category
        self.entityType = entityType
        self.detail = detail
        self.recordCount = recordCount
        self.duration = duration
        self.byteCount = byteCount
        self.journalTailCount = journalTailCount
    }

    // MARK: Public

    public let id: UUID
    public let timestamp: Date
    public let category: Category
    public let entityType: String?
    public let detail: String
    public let recordCount: Int?
    public let duration: TimeInterval?

    /// Size in bytes (e.g., snapshot file size)
    public let byteCount: Int64?

    /// Number of journal entries replayed after snapshot bootstrap
    public let journalTailCount: Int?
}

// MARK: CloudSyncEvent.Category

public extension CloudSyncEvent {
    enum Category: String, Codable, Sendable {
        case fetch
        case upload
        case conflict
        case error
        case accountChange
        case processing
    }
}
