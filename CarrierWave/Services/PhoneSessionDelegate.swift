import CarrierWaveData
import Foundation
import WatchConnectivity

// MARK: - WatchMessage

/// Messages exchanged between iPhone and Watch via WatchConnectivity
enum WatchMessage {
    /// Keys for message dictionaries
    enum Key: Sendable {
        nonisolated static let type = "type"
        nonisolated static let payload = "payload"
    }

    /// Message types
    enum MessageType: String {
        case sessionUpdate
        case sessionEnd
        case startSessionRequest
        case startSessionResponse
    }
}

// MARK: - WatchSessionUpdate

/// Session state sent from iPhone → Watch on every change
struct WatchSessionUpdate: Codable, Sendable {
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
    // Rove
    let currentStopPark: String?
    let stopNumber: Int?
    let totalStops: Int?
    let currentStopQSOs: Int?
}

// MARK: - WatchStartSessionRequest

/// Request from Watch → iPhone to start a session
struct WatchStartSessionRequest: Codable, Sendable {
    let myCallsign: String
    let mode: String
    let activationType: String
    let parkReference: String?
    let frequency: Double?
}

// MARK: - PhoneSessionDelegate

/// iPhone-side WatchConnectivity delegate. Receives session start requests
/// from Watch and sends session updates.
@MainActor
@Observable
final class PhoneSessionDelegate: NSObject, WCSessionDelegate {
    // MARK: Lifecycle

    override init() {
        super.init()
    }

    // MARK: Internal

    static let shared = PhoneSessionDelegate()

    /// Callback invoked when Watch requests a new session start
    var onStartSessionRequest: ((WatchStartSessionRequest) -> Void)?

    /// Whether Watch is reachable for live messaging
    var isWatchReachable: Bool {
        WCSession.default.isReachable
    }

    /// Activate WatchConnectivity session. Call once at app startup.
    func activate() {
        guard WCSession.isSupported() else {
            return
        }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    /// Send a session update to the Watch
    func sendSessionUpdate(_ update: WatchSessionUpdate) {
        guard WCSession.default.isReachable,
              let data = try? JSONEncoder().encode(update)
        else {
            return
        }

        let message: [String: Any] = [
            WatchMessage.Key.type: WatchMessage.MessageType.sessionUpdate.rawValue,
            WatchMessage.Key.payload: data,
        ]
        WCSession.default.sendMessage(message, replyHandler: nil) { _ in }
    }

    /// Notify Watch that session has ended
    func sendSessionEnd() {
        guard WCSession.default.isReachable else {
            return
        }

        let message: [String: Any] = [
            WatchMessage.Key.type: WatchMessage.MessageType.sessionEnd.rawValue,
        ]
        WCSession.default.sendMessage(message, replyHandler: nil) { _ in }
    }

    // MARK: - WCSessionDelegate

    nonisolated func session(
        _: WCSession, activationDidCompleteWith _: WCSessionActivationState,
        error _: Error?
    ) {}

    nonisolated func sessionDidBecomeInactive(_: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    nonisolated func session(
        _: WCSession, didReceiveMessage message: [String: Any],
        replyHandler: @escaping ([String: Any]) -> Void
    ) {
        guard let typeString = message[WatchMessage.Key.type] as? String,
              let type = WatchMessage.MessageType(rawValue: typeString)
        else {
            replyHandler(["error": "unknown message type"])
            return
        }

        switch type {
        case .startSessionRequest:
            handleStartRequest(message: message, replyHandler: replyHandler)
        default:
            replyHandler(["error": "unhandled message type"])
        }
    }

    // MARK: Private

    nonisolated private func handleStartRequest(
        message: [String: Any],
        replyHandler: @escaping ([String: Any]) -> Void
    ) {
        // Extract raw data before crossing isolation boundary
        guard let data = message[WatchMessage.Key.payload] as? Data else {
            replyHandler(["error": "invalid payload"])
            return
        }

        // Bridge the non-Sendable WCSession reply handler across isolation boundary
        nonisolated(unsafe) let sendableReply = replyHandler

        Task { @MainActor in
            guard let request = try? JSONDecoder().decode(
                WatchStartSessionRequest.self, from: data
            ) else {
                sendableReply(["error": "invalid payload"])
                return
            }
            self.onStartSessionRequest?(request)
            NotificationCenter.default.post(
                name: .didReceiveWatchStartSession,
                object: nil,
                userInfo: ["request": request]
            )
            sendableReply(["status": "ok"])
        }
    }
}
