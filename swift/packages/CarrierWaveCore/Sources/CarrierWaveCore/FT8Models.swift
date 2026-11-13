//
//  FT8Models.swift
//  CarrierWaveCore
//

import Foundation

// MARK: - FT8OperatingMode

/// Operating mode for FT8.
public enum FT8OperatingMode: Sendable {
    case listen
    case callCQ(modifier: String?)
    case searchAndPounce
}

// MARK: - FT8TXEvent

public struct FT8TXEvent: Identifiable, Sendable {
    // MARK: Lifecycle

    public init(message: String, timestamp: Date, audioFrequency: Double) {
        self.message = message
        self.timestamp = timestamp
        self.audioFrequency = audioFrequency
    }

    // MARK: Public

    public let id = UUID()
    public let message: String
    public let timestamp: Date
    public let audioFrequency: Double
}

// MARK: - FT8TXState

public enum FT8TXState: Sendable, Equatable {
    case idle
    case armed(callsign: String)
    case transmitting(message: String)
    case halted(callsign: String)
}

// MARK: - ChannelRecommendation

/// A recommended TX channel based on recent decode occupancy.
public struct ChannelRecommendation: Identifiable, Sendable {
    // MARK: Lifecycle

    public init(frequency: Double, activityCount: Int, occupancy: OccupancyLevel) {
        self.frequency = frequency
        self.activityCount = activityCount
        self.occupancy = occupancy
    }

    // MARK: Public

    public enum OccupancyLevel: String, Sendable {
        case clear = "CLEAR"
        case quiet = "QUIET"
        case fair = "FAIR"
        case busy = "BUSY"
    }

    public let id = UUID()
    public let frequency: Double
    public let activityCount: Int
    public let occupancy: OccupancyLevel
}
