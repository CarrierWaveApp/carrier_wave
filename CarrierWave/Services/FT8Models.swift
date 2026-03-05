//
//  FT8Models.swift
//  CarrierWave
//

import Foundation

// MARK: - FT8OperatingMode

/// Operating mode for FT8.
enum FT8OperatingMode: Sendable {
    case listen
    case callCQ(modifier: String?)
    case searchAndPounce
}

// MARK: - FT8TXEvent

struct FT8TXEvent: Identifiable, Sendable {
    let id = UUID()
    let message: String
    let timestamp: Date
    let audioFrequency: Double
}

// MARK: - FT8TXState

enum FT8TXState: Sendable, Equatable {
    case idle
    case armed(callsign: String)
    case transmitting(message: String)
    case halted(callsign: String)
}

// MARK: - ChannelRecommendation

/// A recommended TX channel based on recent decode occupancy.
struct ChannelRecommendation: Identifiable, Sendable {
    enum OccupancyLevel: String, Sendable {
        case clear = "CLEAR"
        case quiet = "QUIET"
        case fair = "FAIR"
        case busy = "BUSY"
    }

    let id = UUID()
    let frequency: Double
    let activityCount: Int
    let occupancy: OccupancyLevel
}
