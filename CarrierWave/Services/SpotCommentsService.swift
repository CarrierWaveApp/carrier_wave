// Spot comments polling service
//
// Polls POTA for spot comments during an active POTA activation,
// allowing activators to see hunter feedback in real-time.

import CarrierWaveCore
import Foundation
import SwiftUI

// MARK: - SpotCommentsService

/// Service that polls for POTA spot comments during an activation
@MainActor
@Observable
final class SpotCommentsService {
    // MARK: Lifecycle

    init() {
        potaClient = POTAClient(authService: POTAAuthService())
    }

    // MARK: Internal

    /// Current spot comments
    private(set) var comments: [POTASpotComment] = []

    /// Number of new (unread) comments
    private(set) var newCommentCount: Int = 0

    /// Whether currently polling
    private(set) var isPolling: Bool = false

    /// Last error (if any)
    private(set) var lastError: String?

    /// Callback when new comments are received (comments that haven't been seen before)
    var onNewComments: (([POTASpotComment]) -> Void)?

    /// Start polling for spot comments
    /// - Parameters:
    ///   - activator: The activator's callsign
    ///   - parkRef: The park reference (e.g., "K-1234")
    ///   - sessionStart: Only show comments after this time (filters out stale comments)
    func startPolling(activator: String, parkRef: String, sessionStart: Date = Date()) {
        stopPolling()

        self.activator = activator
        self.parkRef = parkRef
        sessionStartTime = sessionStart
        isPolling = true
        lastError = nil

        // Fetch immediately
        Task {
            await fetchComments()
        }

        // Schedule recurring fetches every 60 seconds
        pollTimer = Timer.scheduledTimer(
            withTimeInterval: pollInterval,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor in
                await self?.fetchComments()
            }
        }

        SyncDebugLog.shared.info(
            "Started spot comments polling for \(activator) at \(parkRef)",
            service: .pota
        )
    }

    /// Stop polling for spot comments
    func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
        isPolling = false
        activator = nil
        parkRef = nil

        SyncDebugLog.shared.info("Stopped spot comments polling", service: .pota)
    }

    /// Mark all comments as read
    func markAllRead() {
        seenSpotIds = Set(comments.map(\.spotId))
        newCommentCount = 0
    }

    /// Clear all comments (e.g., when session ends)
    func clear() {
        comments = []
        newCommentCount = 0
        seenSpotIds = []
        reportedSpotIds = []
        lastError = nil
    }

    // MARK: Private

    private let potaClient: POTAClient
    private var pollTimer: Timer?
    private var activator: String?
    private var parkRef: String?
    private var seenSpotIds: Set<Int64> = []

    /// Session start time - only show comments after this time
    private var sessionStartTime = Date()

    /// Poll interval in seconds
    private let pollInterval: TimeInterval = 60

    /// Track which comment IDs have been reported via callback
    private var reportedSpotIds: Set<Int64> = []

    private func fetchComments() async {
        guard let activator, let parkRef else {
            return
        }

        do {
            let fetchedComments = try await potaClient.fetchSpotComments(
                activator: activator,
                parkRef: parkRef
            )

            // Filter to only comments after session start, then sort by timestamp (most recent first)
            let filtered = fetchedComments.filter { comment in
                guard let timestamp = comment.timestamp else {
                    return false
                }
                return timestamp >= sessionStartTime
            }

            let sorted = filtered.sorted { c1, c2 in
                (c1.timestamp ?? .distantPast) > (c2.timestamp ?? .distantPast)
            }

            // Calculate new comments
            let newIds = Set(sorted.map(\.spotId)).subtracting(seenSpotIds)
            newCommentCount = newIds.count

            comments = sorted
            lastError = nil

            // Report truly new comments via callback (ones we haven't reported before)
            let unreportedComments = sorted.filter { !reportedSpotIds.contains($0.spotId) }
            if !unreportedComments.isEmpty {
                reportedSpotIds.formUnion(unreportedComments.map(\.spotId))
                onNewComments?(unreportedComments)
            }

            if !newIds.isEmpty {
                SyncDebugLog.shared.info(
                    "Received \(newIds.count) new spot comments",
                    service: .pota
                )
            }
        } catch {
            lastError = error.localizedDescription
            SyncDebugLog.shared.warning(
                "Spot comments fetch failed: \(error.localizedDescription)",
                service: .pota
            )
        }
    }
}
