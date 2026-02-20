import SwiftUI

@main
struct CarrierWaveWatchApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .task {
                    WatchSessionDelegate.shared.activate()
                }
        }
    }
}
