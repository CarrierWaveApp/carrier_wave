import SwiftUI

/// Root view that switches between idle and active session modes.
/// Polls App Group data on appear and listens for WatchConnectivity updates.
struct ContentView: View {
    // MARK: Internal

    var body: some View {
        Group {
            if let live = WatchSessionDelegate.shared.liveSession {
                ActiveSessionView(liveSession: live)
            } else if let session, session.isActive {
                ActiveSessionView(session: session)
            } else {
                IdleView()
            }
        }
        .onAppear {
            refreshData()
            startRefreshTimer()
        }
        .onDisappear {
            refreshTimer?.invalidate()
        }
    }

    // MARK: Private

    @State private var session: WatchSessionSnapshot?
    @State private var liveSession: WatchLiveSession?
    @State private var refreshTimer: Timer?

    private func refreshData() {
        session = SharedDataReader.readSession()
    }

    private func startRefreshTimer() {
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { _ in
            MainActor.assumeIsolated {
                refreshData()
            }
        }
    }
}
