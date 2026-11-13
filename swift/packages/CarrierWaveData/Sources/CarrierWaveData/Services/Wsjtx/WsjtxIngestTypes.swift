//
//  WsjtxIngestTypes.swift
//  CarrierWaveData
//
//  Value types and the Rust→Swift callback bridge for `WsjtxIngestService`
//  (CAR-282).
//

import CarrierWaveCore
import Foundation

// MARK: - WsjtxIngestEvent

/// One line in the live feed shown by the WSJT-X settings surface.
public struct WsjtxIngestEvent: Identifiable, Sendable, Equatable {
    // MARK: Lifecycle

    public init(kind: Kind, text: String, date: Date = Date()) {
        id = UUID()
        self.date = date
        self.kind = kind
        self.text = text
    }

    // MARK: Public

    public enum Kind: Sendable, Equatable {
        case info
        case decode
        case qsoLogged
        case duplicate
        case error
    }

    public let id: UUID
    public let date: Date
    public let kind: Kind
    public let text: String
}

// MARK: - WsjtxIngestOutcome

/// Result of offering one mapped QSO to the log.
public enum WsjtxIngestOutcome: Equatable, Sendable {
    /// A new row was inserted with this id.
    case inserted(UUID)
    /// An equivalent row already existed (same id or same dedup key); nothing written.
    case duplicate(UUID)
    /// The insert failed; the message is user-presentable.
    case failed(String)
}

// MARK: - WsjtxStatusSummary

/// Condensed view of the most recent WSJT-X `Status` broadcast.
public struct WsjtxStatusSummary: Sendable, Equatable {
    public let clientId: String
    public let dialFrequencyHz: UInt64
    public let mode: String
    public let dxCall: String
    public let deCall: String?
    public let transmitting: Bool
    public let receivedAt: Date

    /// e.g. "14.074 MHz FT8"
    public var frequencyAndMode: String {
        let mhz = Double(dialFrequencyHz) / 1_000_000
        return String(format: "%.3f MHz %@", mhz, mode)
    }
}

// MARK: - WsjtxDelegateBridge

/// Receives `WsjtxListenerDelegate` callbacks on the Rust runtime thread and
/// forwards them as a single `Sendable` event; the service hops to the main
/// actor. Same shape as CW Sweep's `PanadapterEventListener`.
final class WsjtxDelegateBridge: WsjtxListenerDelegate {
    // MARK: Lifecycle

    init(deliver: @escaping @Sendable (Event) -> Void) {
        self.deliver = deliver
    }

    // MARK: Internal

    enum Event: Sendable {
        case message(FfiWsjtxMessage, from: String)
        case error(String)
        case stopped
    }

    func onMessage(message: FfiWsjtxMessage, from: String) {
        deliver(.message(message, from: from))
    }

    func onError(message: String) {
        deliver(.error(message))
    }

    func onStopped() {
        deliver(.stopped)
    }

    // MARK: Private

    private let deliver: @Sendable (Event) -> Void
}
