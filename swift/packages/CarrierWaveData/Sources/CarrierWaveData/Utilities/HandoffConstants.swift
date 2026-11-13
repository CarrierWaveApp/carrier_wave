// Handoff Constants
//
// Shared constants for Apple Handoff between iOS and macOS apps.
// Both Carrier Wave (iOS) and CW Sweep (macOS) use these to
// advertise and consume NSUserActivity for session continuity.

import Foundation

// MARK: - HandoffConstants

/// Constants for Handoff between iOS and macOS.
public enum HandoffConstants {
    /// Activity type for an active logging session.
    public static let loggingSessionActivity =
        "com.jsvana.CarrierWave.loggingSession"

    /// Activity type for spot viewing.
    public static let spotViewingActivity =
        "com.jsvana.CarrierWave.spotViewing"

    /// Activity type for FT8 session.
    public static let ft8SessionActivity =
        "com.jsvana.CarrierWave.ft8Session"

    // MARK: - UserInfo Keys

    /// Session ID (UUID string).
    public static let sessionIDKey = "sessionID"
    /// Callsign being used.
    public static let myCallsignKey = "myCallsign"
    /// Grid square.
    public static let myGridKey = "myGrid"
    /// Current frequency in MHz.
    public static let frequencyKey = "frequency"
    /// Current mode (CW, SSB, FT8, etc.).
    public static let modeKey = "mode"
    /// Current band (20m, 40m, etc.).
    public static let bandKey = "band"
    /// Park reference (e.g., US-0001) if POTA activation.
    public static let parkReferenceKey = "parkReference"
    /// Number of QSOs logged in current session.
    public static let qsoCountKey = "qsoCount"
    /// Timestamp when session started.
    public static let sessionStartKey = "sessionStart"
    /// Spot callsign being viewed.
    public static let spotCallsignKey = "spotCallsign"
    /// Spot frequency in MHz.
    public static let spotFrequencyKey = "spotFrequency"
    /// Club/alternate station callsign (nil = operator is station).
    public static let stationCallsignKey = "stationCallsign"
}

// MARK: - HandoffSessionState

/// Serializable session state for Handoff transfer.
public struct HandoffSessionState: Codable, Sendable {
    // MARK: Lifecycle

    public init(
        sessionID: String,
        myCallsign: String,
        myGrid: String,
        frequency: Double? = nil,
        mode: String? = nil,
        band: String? = nil,
        parkReference: String? = nil,
        qsoCount: Int = 0,
        sessionStart: Date = Date(),
        stationCallsign: String? = nil
    ) {
        self.sessionID = sessionID
        self.myCallsign = myCallsign
        self.myGrid = myGrid
        self.frequency = frequency
        self.mode = mode
        self.band = band
        self.parkReference = parkReference
        self.qsoCount = qsoCount
        self.sessionStart = sessionStart
        self.stationCallsign = stationCallsign
    }

    /// Reconstruct from NSUserActivity userInfo.
    public init?(userInfo: [AnyHashable: Any]?) {
        guard let info = userInfo,
              let sid = info[HandoffConstants.sessionIDKey]
              as? String,
              let call = info[HandoffConstants.myCallsignKey]
              as? String,
              let grid = info[HandoffConstants.myGridKey]
              as? String
        else {
            return nil
        }

        sessionID = sid
        myCallsign = call
        myGrid = grid
        frequency = info[HandoffConstants.frequencyKey]
            as? Double
        mode = info[HandoffConstants.modeKey] as? String
        band = info[HandoffConstants.bandKey] as? String
        parkReference = info[
            HandoffConstants.parkReferenceKey
        ] as? String
        qsoCount = info[HandoffConstants.qsoCountKey]
            as? Int ?? 0

        stationCallsign = info[
            HandoffConstants.stationCallsignKey
        ] as? String

        if let ts = info[HandoffConstants.sessionStartKey]
            as? TimeInterval
        {
            sessionStart = Date(timeIntervalSince1970: ts)
        } else {
            sessionStart = Date()
        }
    }

    // MARK: Public

    public let sessionID: String
    public let myCallsign: String
    public let myGrid: String
    public let frequency: Double?
    public let mode: String?
    public let band: String?
    public let parkReference: String?
    public let qsoCount: Int
    public let sessionStart: Date
    public let stationCallsign: String?

    /// Convert to NSUserActivity userInfo dictionary.
    public var userInfo: [String: Any] {
        var info: [String: Any] = [
            HandoffConstants.sessionIDKey: sessionID,
            HandoffConstants.myCallsignKey: myCallsign,
            HandoffConstants.myGridKey: myGrid,
            HandoffConstants.qsoCountKey: qsoCount,
            HandoffConstants.sessionStartKey:
                sessionStart.timeIntervalSince1970,
        ]
        if let freq = frequency {
            info[HandoffConstants.frequencyKey] = freq
        }
        if let md = mode {
            info[HandoffConstants.modeKey] = md
        }
        if let bd = band {
            info[HandoffConstants.bandKey] = bd
        }
        if let park = parkReference {
            info[HandoffConstants.parkReferenceKey] = park
        }
        if let sc = stationCallsign {
            info[HandoffConstants.stationCallsignKey] = sc
        }
        return info
    }
}
