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

        // Otherwise treat as ADIF file
        NotificationCenter.default.post(
            name: .didReceiveADIFFile,
            object: url
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
    static let didSyncQSOs = Notification.Name("didSyncQSOs")
    static let didDetectActivities = Notification.Name("didDetectActivities")
}
