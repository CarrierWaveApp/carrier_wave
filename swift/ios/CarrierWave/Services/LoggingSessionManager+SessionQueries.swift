import CarrierWaveData
import SwiftData
import UIKit

// MARK: - Session list queries

extension LoggingSessionManager {
    /// Get recent sessions for resuming
    func getRecentSessions(limit: Int = 10) -> [LoggingSession] {
        let descriptor = FetchDescriptor<LoggingSession>(
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )

        do {
            var fetchDescriptor = descriptor
            fetchDescriptor.fetchLimit = limit
            return try modelContext.fetch(fetchDescriptor)
        } catch {
            return []
        }
    }

    /// Get all active or paused sessions (not completed), excluding the current active session
    func fetchActiveSessions() -> [LoggingSession] {
        var descriptor = FetchDescriptor<LoggingSession>(
            predicate: #Predicate {
                $0.statusRawValue == "active" || $0.statusRawValue == "paused"
            },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 50

        let sessions = (try? modelContext.fetch(descriptor)) ?? []
        let activeId = activeSession?.id
        return sessions.filter { $0.id != activeId }
    }
}
