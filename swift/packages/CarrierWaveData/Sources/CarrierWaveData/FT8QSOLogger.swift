//
//  FT8QSOLogger.swift
//  CarrierWaveData
//

import Foundation

// MARK: - FT8CompletedQSOData

/// Data for a completed FT8 QSO, passed to the logger.
public struct FT8CompletedQSOData {
    // MARK: Lifecycle

    public init(
        callsign: String,
        band: String,
        frequency: Double?,
        rstSent: String,
        rstReceived: String,
        theirGrid: String?
    ) {
        self.callsign = callsign
        self.band = band
        self.frequency = frequency
        self.rstSent = rstSent
        self.rstReceived = rstReceived
        self.theirGrid = theirGrid
    }

    // MARK: Public

    public let callsign: String
    public let band: String
    public let frequency: Double?
    public let rstSent: String
    public let rstReceived: String
    public let theirGrid: String?
}

// MARK: - FT8QSOLogger

/// Protocol for logging QSOs from FT8 sessions.
/// Conformers: LoggingSessionManager (activations) and ActivityLogManager (hunting).
@MainActor
public protocol FT8QSOLogger: AnyObject {
    @discardableResult
    func logFT8QSO(_ data: FT8CompletedQSOData) -> LoggedQSO?
}
