import Foundation
import WatchConnectivity

// MARK: - WatchMessageKey

/// Message keys matching the iPhone-side PhoneSessionDelegate
private enum WatchMessageKey {
    static let type = "type"
    static let payload = "payload"
}

private enum WatchMessageType: String {
    case sessionUpdate
    case sessionEnd
    case startSessionRequest
    case startSessionResponse
}

// MARK: - WatchSessionUpdate

/// Session state received from iPhone during active logging
struct WatchLiveSession: Codable, Sendable {
    let qsoCount: Int
    let lastCallsign: String?
    let frequency: String?
    let band: String?
    let mode: String?
    let parkReference: String?
    let activationType: String?
    let isPaused: Bool
    let startedAt: Date?
    let myCallsign: String?
    let currentStopPark: String?
    let stopNumber: Int?
    let totalStops: Int?
    let currentStopQSOs: Int?
}

// MARK: - WatchStartRequest

/// Request to start a session on the iPhone
struct WatchStartRequest: Codable, Sendable {
    let myCallsign: String
    let mode: String
    let activationType: String
    let parkReference: String?
    let frequency: Double?
}

// MARK: - WatchSessionDelegate

/// Watch-side WatchConnectivity delegate. Receives session updates from
/// iPhone and sends session start requests.
@MainActor
@Observable
final class WatchSessionDelegate: NSObject, @preconcurrency WCSessionDelegate {
    // MARK: Lifecycle

    override init() {
        super.init()
    }

    // MARK: Internal

    static let shared = WatchSessionDelegate()

    /// Live session data from iPhone (nil when no session active)
    private(set) var liveSession: WatchLiveSession?

    /// Whether iPhone is reachable
    var isPhoneReachable: Bool {
        WCSession.default.isReachable
    }

    /// Activate WatchConnectivity. Call once at Watch app startup.
    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    /// Request iPhone to start a logging session
    func requestStartSession(_ request: WatchStartRequest) async -> Bool {
        guard WCSession.default.isReachable,
              let data = try? JSONEncoder().encode(request)
        else { return false }

        let message: [String: Any] = [
            WatchMessageKey.type: WatchMessageType.startSessionRequest.rawValue,
            WatchMessageKey.payload: data,
        ]

        return await withCheckedContinuation { continuation in
            WCSession.default.sendMessage(message, replyHandler: { reply in
                let success = reply["status"] as? String == "ok"
                continuation.resume(returning: success)
            }, errorHandler: { _ in
                continuation.resume(returning: false)
            })
        }
    }

    // MARK: - WCSessionDelegate

    nonisolated func session(
        _: WCSession, activationDidCompleteWith _: WCSessionActivationState,
        error _: Error?
    ) {}

    nonisolated func session(
        _: WCSession, didReceiveMessage message: [String: Any]
    ) {
        guard let typeString = message[WatchMessageKey.type] as? String,
              let type = WatchMessageType(rawValue: typeString)
        else { return }

        Task { @MainActor in
            switch type {
            case .sessionUpdate:
                if let data = message[WatchMessageKey.payload] as? Data,
                   let update = try? JSONDecoder().decode(WatchLiveSession.self, from: data)
                {
                    self.liveSession = update
                }
            case .sessionEnd:
                self.liveSession = nil
            default:
                break
            }
        }
    }
}
