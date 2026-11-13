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
            refreshTask?.cancel()
        }
    }

    // MARK: Private

    @State private var session: WatchSessionSnapshot?
    @State private var liveSession: WatchLiveSession?
    @State private var refreshTask: Task<Void, Never>?

    private func refreshData() {
        session = SharedDataReader.readSession()
    }

    private func startRefreshTimer() {
        refreshTask?.cancel()
        refreshTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled else {
                    break
                }
                refreshData()
            }
        }
    }
}
