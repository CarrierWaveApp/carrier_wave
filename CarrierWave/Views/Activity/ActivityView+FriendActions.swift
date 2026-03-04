import CarrierWaveData
import SwiftUI

// MARK: - ActivityView+FriendActions

extension ActivityView {
    /// Periodically refresh the activity feed while the tab is visible.
    /// Uses cooperative cancellation — SwiftUI cancels this task on disappear.
    func periodicFeedRefresh() async {
        // Wait 60 seconds before first refresh (initial load already happened)
        try? await Task.sleep(for: .seconds(60))

        while !Task.isCancelled {
            if let feedService = feedSyncService {
                try? await feedService.syncFeed(
                    sourceURL: "https://activities.carrierwave.app"
                )
                loadActivityItems()
            }
            try? await Task.sleep(for: .seconds(60))
        }
    }

    func syncFeedQuietly() async {
        guard let feedService = feedSyncService else {
            return
        }
        try? await feedService.syncFeed(sourceURL: "https://activities.carrierwave.app")
        loadActivityItems()
    }

    func syncFriendsQuietly() async {
        if friendsSyncService == nil {
            friendsSyncService = FriendsSyncService(modelContext: modelContext)
        }
        guard let service = friendsSyncService else {
            return
        }
        do {
            try await service.syncFriends(sourceURL: "https://activities.carrierwave.app")
        } catch {
            // Non-critical — don't show error for background friend sync
        }
    }

    func handleFriendInviteNotification(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let token = userInfo["token"] as? String
        else {
            return
        }

        pendingFriendInviteToken = token
        showingFriendInviteSheet = true
    }

    func acceptFriendInvite() {
        guard let token = pendingFriendInviteToken,
              let service = friendsSyncService
        else {
            return
        }

        isProcessingFriendInvite = true

        Task {
            do {
                try await service.sendFriendRequestWithInvite(
                    inviteToken: token,
                    sourceURL: "https://activities.carrierwave.app"
                )
                showingFriendInviteSheet = false
                pendingFriendInviteToken = nil
            } catch {
                errorMessage = error.localizedDescription
                showingError = true
            }
            isProcessingFriendInvite = false
        }
    }
}
