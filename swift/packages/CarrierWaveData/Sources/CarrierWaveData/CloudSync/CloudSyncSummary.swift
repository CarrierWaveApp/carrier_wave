// CarrierWaveData/Sources/CarrierWaveData/CloudSync/CloudSyncSummary.swift
import Foundation

/// Dashboard summary computed from recent sync events.
public struct CloudSyncSummary: Sendable {
    public static let empty = CloudSyncSummary(
        lastFetchDate: nil, lastFetchDuration: nil,
        lastFetchRecordCount: nil, lastFetchByteCount: nil,
        lastFetchJournalTailCount: nil,
        lastUploadDate: nil, lastUploadDuration: nil,
        lastUploadRecordCount: nil, lastUploadByteCount: nil,
        conflictsToday: 0, errorsToday: 0
    )

    public let lastFetchDate: Date?
    public let lastFetchDuration: TimeInterval?
    public let lastFetchRecordCount: Int?
    public let lastFetchByteCount: Int64?
    public let lastFetchJournalTailCount: Int?
    public let lastUploadDate: Date?
    public let lastUploadDuration: TimeInterval?
    public let lastUploadRecordCount: Int?
    public let lastUploadByteCount: Int64?
    public let conflictsToday: Int
    public let errorsToday: Int

    public static func from(events: [CloudSyncEvent]) -> CloudSyncSummary {
        let todayStart = Calendar.current.startOfDay(for: Date())

        let lastFetch = events.last { $0.category == .fetch }
        let lastUpload = events.last { $0.category == .upload }

        let conflicts = events.reduce(into: 0) { count, event in
            if event.category == .conflict, event.timestamp >= todayStart {
                count += 1
            }
        }
        let errors = events.reduce(into: 0) { count, event in
            if event.category == .error, event.timestamp >= todayStart {
                count += 1
            }
        }

        return CloudSyncSummary(
            lastFetchDate: lastFetch?.timestamp,
            lastFetchDuration: lastFetch?.duration,
            lastFetchRecordCount: lastFetch?.recordCount,
            lastFetchByteCount: lastFetch?.byteCount,
            lastFetchJournalTailCount: lastFetch?.journalTailCount,
            lastUploadDate: lastUpload?.timestamp,
            lastUploadDuration: lastUpload?.duration,
            lastUploadRecordCount: lastUpload?.recordCount,
            lastUploadByteCount: lastUpload?.byteCount,
            conflictsToday: conflicts,
            errorsToday: errors
        )
    }
}
