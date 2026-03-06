import Foundation

/// Manages N1MM+ broadcast and WSJT-X listener services.
@MainActor
@Observable
final class InteropManager {
    // MARK: Internal

    private(set) var n1mmEnabled = false
    private(set) var wsjtxEnabled = false
    private(set) var wsjtxConnected = false
    private(set) var recentDecodes: [WSJTXDecode] = []

    func enableN1MM() async {
        n1mmEnabled = true
        await n1mmService.start()
    }

    func disableN1MM() async {
        n1mmEnabled = false
        await n1mmService.stop()
    }

    func enableWSJTX() async {
        wsjtxEnabled = true
        try? await wsjtxService.start()
        wsjtxConnected = await wsjtxService.isConnected

        // Start listening for decodes
        decodeTask?.cancel()
        decodeTask = Task {
            for await decode in await wsjtxService.decodedMessages {
                if Task.isCancelled {
                    break
                }
                recentDecodes.append(decode)
                // Keep only last 100 decodes
                if recentDecodes.count > 100 {
                    recentDecodes.removeFirst()
                }
            }
        }
    }

    func disableWSJTX() async {
        wsjtxEnabled = false
        decodeTask?.cancel()
        await wsjtxService.stop()
        wsjtxConnected = false
    }

    func broadcastContact(
        callsign: String,
        band: String,
        mode: String,
        frequency: Double,
        rstSent: String,
        rstReceived: String,
        exchangeSent: String,
        exchangeReceived: String,
        myCallsign: String,
        contestName: String,
        score: ContestScoreSnapshot
    ) async {
        guard n1mmEnabled else {
            return
        }
        await n1mmService.broadcastContact(
            callsign: callsign,
            band: band,
            mode: mode,
            frequency: frequency,
            rstSent: rstSent,
            rstReceived: rstReceived,
            exchangeSent: exchangeSent,
            exchangeReceived: exchangeReceived,
            myCallsign: myCallsign,
            contestName: contestName,
            score: score
        )
    }

    func broadcastRadioInfo(
        frequency: Double,
        mode: String,
        myCallsign: String,
        contestName: String
    ) async {
        guard n1mmEnabled else {
            return
        }
        await n1mmService.broadcastRadioInfo(
            frequency: frequency,
            mode: mode,
            myCallsign: myCallsign,
            contestName: contestName
        )
    }

    // MARK: Private

    private let n1mmService = N1MMBroadcastService()
    private let wsjtxService = WSJTXListenerService()
    private var decodeTask: Task<Void, Never>?
}
