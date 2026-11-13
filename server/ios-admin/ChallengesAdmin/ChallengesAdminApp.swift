import SwiftUI

@main
struct ChallengesAdminApp: App {
    // MARK: Internal

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(serverConfig)
        }
    }

    // MARK: Private

    @StateObject private var serverConfig = ServerConfig()
}
