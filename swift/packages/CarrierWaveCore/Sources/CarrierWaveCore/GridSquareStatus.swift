//
//  GridSquareStatus.swift
//  CarrierWaveCore
//

import Foundation

// MARK: - GridSquareStatus

/// Status of a Maidenhead grid square relative to the operator's log.
public enum GridSquareStatus: Sendable, Equatable {
    /// Grid has not been worked
    case notWorked
    /// Grid was worked but not confirmed by any QSL service
    case worked(count: Int)
    /// Grid confirmed via LoTW or QRZ QSL
    case confirmed(count: Int)
}

// MARK: - GridSquareData

/// Aggregated data for a single 4-character Maidenhead grid square.
public struct GridSquareData: Sendable, Identifiable {
    // MARK: Lifecycle

    public init(
        grid: String,
        status: GridSquareStatus,
        qsoCount: Int,
        confirmedCount: Int,
        callsigns: [String],
        bands: Set<String>,
        modes: Set<String>,
        mostRecent: Date?
    ) {
        self.grid = grid
        self.status = status
        self.qsoCount = qsoCount
        self.confirmedCount = confirmedCount
        self.callsigns = callsigns
        self.bands = bands
        self.modes = modes
        self.mostRecent = mostRecent
    }

    // MARK: Public

    public let grid: String // 4-char grid (e.g. "FN42")
    public let status: GridSquareStatus
    public let qsoCount: Int
    public let confirmedCount: Int
    public let callsigns: [String]
    public let bands: Set<String>
    public let modes: Set<String>
    public let mostRecent: Date?

    public var id: String {
        grid
    }
}

// MARK: - GridTrackerSummary

/// Summary statistics for the grid tracker dashboard card.
public struct GridTrackerSummary: Sendable {
    // MARK: Lifecycle

    public init(
        totalGridsWorked: Int,
        totalGridsConfirmed: Int,
        totalFields: Int,
        gridData: [String: GridSquareData],
        fieldCounts: [String: Int]
    ) {
        self.totalGridsWorked = totalGridsWorked
        self.totalGridsConfirmed = totalGridsConfirmed
        self.totalFields = totalFields
        self.gridData = gridData
        self.fieldCounts = fieldCounts
    }

    // MARK: Public

    public static let empty = GridTrackerSummary(
        totalGridsWorked: 0,
        totalGridsConfirmed: 0,
        totalFields: 0,
        gridData: [:],
        fieldCounts: [:]
    )

    public let totalGridsWorked: Int
    public let totalGridsConfirmed: Int
    public let totalFields: Int
    public let gridData: [String: GridSquareData] // keyed by 4-char grid
    public let fieldCounts: [String: Int] // keyed by 2-char field (e.g. "FN")
}
