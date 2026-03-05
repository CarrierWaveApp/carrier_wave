//
//  FT8QSOStateMachine.swift
//  CarrierWaveCore
//

import Foundation

// MARK: - FT8QSOStateMachine

/// Pure-logic state machine for FT8 QSO exchanges.
/// Drives the auto-sequencer: given the current state and incoming messages,
/// determines the next TX message and when a QSO is complete.
public struct FT8QSOStateMachine: Sendable {
    // MARK: Lifecycle

    // MARK: - Init

    public init(myCallsign: String, myGrid: String) {
        self.myCallsign = myCallsign
        self.myGrid = myGrid
    }

    // MARK: Public

    // MARK: - Types

    public enum QSORole: Sendable, Equatable {
        /// We called CQ, they responded.
        case cqOriginator
        /// They called CQ, we responded.
        case searchAndPounce
    }

    public enum State: Sendable, Equatable {
        /// Not in a QSO; listening or calling CQ.
        case idle
        /// Sent our grid/call, waiting for signal report.
        case calling
        /// Sent signal report, waiting for R+report or RR73.
        case reportSent
        /// Received R+report, sending RR73.
        case reportReceived
        /// QSO logged; sending final 73/RR73 grace message. Resets after one cycle.
        case completing
        /// QSO done — ready to log.
        case complete
    }

    public struct CompletedQSO: Sendable {
        public let theirCallsign: String
        public let theirGrid: String?
        public let theirReport: Int?
        public let myReport: Int?
        public let startTime: Date
    }

    public private(set) var state: State = .idle
    public private(set) var role: QSORole?
    public let myCallsign: String
    public let myGrid: String

    public private(set) var theirCallsign: String?
    public private(set) var theirGrid: String?
    public private(set) var theirReport: Int?
    public var myReport: Int?

    // MARK: - TX Message Generation

    public var nextTXMessage: String? {
        switch state {
        case .idle:
            return cqMessage

        case .calling:
            guard let their = theirCallsign else {
                return nil
            }
            return "\(their) \(myCallsign) \(myGrid)"

        case .reportSent:
            guard let their = theirCallsign, let report = myReport else {
                return nil
            }
            let sign = report >= 0 ? "+" : "-"
            let formatted = "\(sign)\(String(format: "%02d", abs(report)))"
            if role == .searchAndPounce {
                return "\(their) \(myCallsign) R\(formatted)"
            }
            return "\(their) \(myCallsign) \(formatted)"

        case .reportReceived:
            guard let their = theirCallsign else {
                return nil
            }
            return "\(their) \(myCallsign) RR73"

        case .completing:
            guard let their = theirCallsign else {
                return nil
            }
            if role == .cqOriginator {
                return "\(their) \(myCallsign) RR73"
            }
            return "\(their) \(myCallsign) 73"

        case .complete:
            return nil
        }
    }

    // MARK: - Completed QSO

    public var completedQSO: CompletedQSO? {
        guard state == .complete || state == .completing, let call = theirCallsign else {
            return nil
        }
        return CompletedQSO(
            theirCallsign: call,
            theirGrid: theirGrid,
            theirReport: theirReport,
            myReport: myReport,
            startTime: qsoStartTime ?? Date()
        )
    }

    // MARK: - CQ Mode

    public mutating func setCQMode(modifier: String?) {
        isCQMode = true
        cqModifier = modifier
        state = .idle
    }

    public mutating func setListenMode() {
        isCQMode = false
        state = .idle
        resetQSO()
    }

    // MARK: - Initiate Call (S&P)

    public mutating func initiateCall(to callsign: String, theirGrid: String?) {
        guard !workedCallsigns.contains(callsign.uppercased()) else {
            return
        }

        theirCallsign = callsign
        self.theirGrid = theirGrid
        state = .calling
        role = .searchAndPounce
        maxCyclesBeforeTimeout = 4
        cyclesSinceLastResponse = 0
        qsoStartTime = Date()
    }

    // MARK: - Process Incoming Message

    public mutating func processMessage(_ message: FT8Message) {
        if handleCQResponse(message) {
            return
        }

        guard message.isDirectedTo(myCallsign),
              let sender = message.callerCallsign,
              sender.uppercased() == theirCallsign?.uppercased()
        else {
            return
        }
        cyclesSinceLastResponse = 0

        switch (state, message) {
        case let (.calling, .signalReport(_, _, dB)):
            theirReport = dB
            state = .reportSent

        case let (.reportSent, .rogerReport(_, _, dB)):
            theirReport = dB
            // CQ originator: received R+report → completing (log QSO, send RR73)
            if role == .cqOriginator {
                markComplete(entering: .completing)
            } else {
                state = .reportReceived
            }

        case (.reportReceived, .rogerEnd),
             (.reportReceived, .end):
            markComplete(entering: .completing)

        case (.reportSent, .rogerEnd):
            // S&P receiving RR73 from reportSent → completing
            markComplete(entering: .completing)

        default:
            break
        }
    }

    // MARK: - Cycle Management

    public mutating func advanceCycle() {
        if state == .completing {
            state = .idle
            resetQSO()
            return
        }
        guard state != .idle, state != .complete else {
            return
        }
        cyclesSinceLastResponse += 1
        if cyclesSinceLastResponse >= maxCyclesBeforeTimeout {
            state = .idle
            resetQSO()
        }
    }

    // MARK: - Worked Stations

    public mutating func markWorked(_ callsign: String) {
        workedCallsigns.insert(callsign.uppercased())
    }

    public func hasWorked(_ callsign: String) -> Bool {
        workedCallsigns.contains(callsign.uppercased())
    }

    // MARK: - Reset

    public mutating func resetForNextQSO() {
        state = .idle
        resetQSO()
    }

    // MARK: Private

    private var cqModifier: String?
    private var isCQMode = false
    private var cyclesSinceLastResponse = 0
    private var maxCyclesBeforeTimeout = 8
    private var workedCallsigns = Set<String>()
    private var qsoStartTime: Date?

    private var cqMessage: String? {
        guard isCQMode else {
            return nil
        }
        if let mod = cqModifier {
            return "CQ \(mod) \(myCallsign) \(myGrid)"
        }
        return "CQ \(myCallsign) \(myGrid)"
    }

    /// Handle a CQ response in CQ mode. Returns true if handled.
    private mutating func handleCQResponse(_ message: FT8Message) -> Bool {
        guard isCQMode, state == .idle else {
            return false
        }
        guard case let .directed(from, to, grid) = message,
              to.uppercased() == myCallsign.uppercased(),
              !workedCallsigns.contains(from.uppercased())
        else {
            return false
        }
        theirCallsign = from
        theirGrid = grid
        state = .reportSent
        role = .cqOriginator
        maxCyclesBeforeTimeout = 8
        cyclesSinceLastResponse = 0
        qsoStartTime = Date()
        return true
    }

    private mutating func markComplete(entering targetState: State = .complete) {
        state = targetState
        if let call = theirCallsign {
            workedCallsigns.insert(call.uppercased())
        }
    }

    private mutating func resetQSO() {
        theirCallsign = nil
        theirGrid = nil
        theirReport = nil
        myReport = nil
        role = nil
        cyclesSinceLastResponse = 0
        qsoStartTime = nil
    }
}
