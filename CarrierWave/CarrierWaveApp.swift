import SwiftData
import SwiftUI
import UniformTypeIdentifiers

// MARK: - CarrierWaveApp

@main
struct CarrierWaveApp: App {
    // MARK: Internal

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            QSO.self,
            ServicePresence.self,
            UploadDestination.self,
            POTAUploadAttempt.self,
            ActivationMetadata.self,
            ChallengeSource.self,
            ChallengeDefinition.self,
            ChallengeParticipation.self,
            LeaderboardCache.self,
            Friendship.self,
            Club.self,
            ActivityItem.self,
            LoggingSession.self,
            CallsignNotesSource.self,
            DismissedSuggestion.self,
        ])
        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false
        )

        do {
            return try ModelContainer(
                for: schema,
                configurations: [modelConfiguration]
            )
        } catch {
            // If schema migration fails, log and crash
            // In production, you might want to handle this more gracefully
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView(tourState: tourState)
                .task {
                    // Preload caches on app launch (loads from disk, refreshes in background)
                    await POTAParksCache.shared.ensureLoaded()
                    // Fetch sources on main actor, then pass to cache actor
                    let sources = NotesSourceInfo.fetchAll(
                        modelContext: sharedModelContainer.mainContext
                    )
                    await CallsignNotesCache.shared.ensureLoaded(sources: sources)
                }
                .onOpenURL { url in
                    handleURL(url)
                }
        }
        .modelContainer(sharedModelContainer)
    }

    // MARK: Private

    @State private var tourState = TourState()

    private func handleURL(_ url: URL) {
        // Check if it's a challenge invite link
        if url.scheme == "carrierwave", url.host == "challenge" {
            handleChallengeURL(url)
            return
        }

        // Check if it's a friend invite link (carrierwave://invite/{token})
        if url.scheme == "carrierwave", url.host == "invite" {
            handleFriendInviteURL(url)
            return
        }

        // Check for HTTPS friend invite link (https://*.carrierwave.app/invite/{token})
        if let host = url.host, host.hasSuffix("carrierwave.app"),
           url.pathComponents.count >= 2, url.pathComponents[1] == "invite"
        {
            handleFriendInviteURL(url)
            return
        }

        // Otherwise treat as ADIF file
        NotificationCenter.default.post(
            name: .didReceiveADIFFile,
            object: url
        )
    }

    private func handleFriendInviteURL(_ url: URL) {
        // Parse invite token from URL
        // Formats:
        // - carrierwave://invite/{token}
        // - https://*.carrierwave.app/invite/{token}
        let pathComponents = url.pathComponents.filter { $0 != "/" }

        var token: String?

        if url.scheme == "carrierwave" {
            // carrierwave://invite/{token} - token is in host or first path component
            if let host = url.host, host != "invite" {
                token = host
            } else if let first = pathComponents.first {
                token = first
            }
        } else {
            // https://*.carrierwave.app/invite/{token}
            if let inviteIndex = pathComponents.firstIndex(of: "invite"),
               inviteIndex + 1 < pathComponents.count
            {
                token = pathComponents[inviteIndex + 1]
            }
        }

        guard let inviteToken = token, !inviteToken.isEmpty else {
            return
        }

        NotificationCenter.default.post(
            name: .didReceiveFriendInvite,
            object: nil,
            userInfo: ["token": inviteToken]
        )
    }

    private func handleChallengeURL(_ url: URL) {
        // Parse carrierwave://challenge/join?source=...&id=...&token=...
        guard url.path == "/join" else {
            return
        }

        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let queryItems = components?.queryItems ?? []

        var params: [String: String] = [:]
        for item in queryItems {
            if let value = item.value {
                params[item.name] = value
            }
        }

        guard let source = params["source"],
              let idString = params["id"],
              let challengeId = UUID(uuidString: idString)
        else {
            return
        }

        let token = params["token"]

        NotificationCenter.default.post(
            name: .didReceiveChallengeInvite,
            object: nil,
            userInfo: [
                "source": source,
                "challengeId": challengeId,
                "token": token as Any,
            ]
        )
    }
}

extension Notification.Name {
    static let didReceiveADIFFile = Notification.Name("didReceiveADIFFile")
    static let didReceiveChallengeInvite = Notification.Name("didReceiveChallengeInvite")
    static let didReceiveFriendInvite = Notification.Name("didReceiveFriendInvite")
    static let didSyncQSOs = Notification.Name("didSyncQSOs")
    static let didDetectActivities = Notification.Name("didDetectActivities")
    static let didClearQSOs = Notification.Name("didClearQSOs")
}
