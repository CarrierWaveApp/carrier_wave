//
//  FT8EnrichedDecode.swift
//  CarrierWaveCore
//

import Foundation

// MARK: - FT8EnrichedDecode

/// An FT8 decode enriched with worked-before status, DXCC entity, distance, and other metadata.
///
/// Wraps `FT8DecodeResult` with lookup data that determines how the decode is displayed
/// in the FT8 interface: which section it appears in, its sort priority within that section,
/// and visual indicators like SNR tier and "new" badges.
public struct FT8EnrichedDecode: Identifiable, Sendable {
    // MARK: Lifecycle

    public init(
        decode: FT8DecodeResult,
        dxccEntity: String?,
        stateProvince: String?,
        distanceMiles: Int?,
        bearing: Int?,
        isNewDXCC: Bool,
        isNewState: Bool,
        isNewGrid: Bool,
        isNewBand: Bool,
        isDupe: Bool,
        isDirectedAtMe: Bool = false
    ) {
        self.decode = decode
        self.dxccEntity = dxccEntity
        self.stateProvince = stateProvince
        self.distanceMiles = distanceMiles
        self.bearing = bearing
        self.isNewDXCC = isNewDXCC
        self.isNewState = isNewState
        self.isNewGrid = isNewGrid
        self.isNewBand = isNewBand
        self.isDupe = isDupe
        self.isDirectedAtMe = isDirectedAtMe
    }

    // MARK: Public

    /// The underlying FT8 decode result
    public let decode: FT8DecodeResult

    /// DXCC entity name (e.g. "United States", "Japan")
    public let dxccEntity: String?

    /// State or province code (e.g. "CT", "ON")
    public let stateProvince: String?

    /// Distance from operator in miles
    public let distanceMiles: Int?

    /// Bearing from operator in degrees
    public let bearing: Int?

    /// Whether this callsign represents a new DXCC entity (never worked before)
    public let isNewDXCC: Bool

    /// Whether this callsign represents a new state/province
    public let isNewState: Bool

    /// Whether this grid square has never been worked
    public let isNewGrid: Bool

    /// Whether this callsign has never been worked on this band
    public let isNewBand: Bool

    /// Whether this callsign is a duplicate (already worked on this band and mode)
    public let isDupe: Bool

    /// Whether this message is directed at the operator's callsign
    public let isDirectedAtMe: Bool

    /// Identity delegates to the underlying decode result
    public var id: UUID {
        decode.id
    }
}

// MARK: - Section Classification

public extension FT8EnrichedDecode {
    /// Display section for grouping decodes in the FT8 list.
    ///
    /// Ordered by visual priority: messages directed at you appear first,
    /// then CQ calls you can respond to, then all other activity.
    enum Section: Int, Sendable, Comparable {
        /// Messages directed at the operator (responses to your CQ, reports, etc.)
        case directedAtYou = 0
        /// CQ calls from other stations that you can respond to
        case callingCQ = 1
        /// All other exchanges between other stations
        case allActivity = 2

        // MARK: Public

        public static func < (lhs: Section, rhs: Section) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    /// The section this decode belongs in, based on whether it's directed at the operator
    /// or is a CQ call.
    var section: Section {
        if isDirectedAtMe {
            return .directedAtYou
        }
        if decode.message.isCallable {
            return .callingCQ
        }
        return .allActivity
    }
}

// MARK: - Sort Priority

public extension FT8EnrichedDecode {
    /// Numeric sort priority within a section. Lower values sort first (more interesting).
    ///
    /// - 0: New DXCC entity (rarest, most valuable)
    /// - 1: New state/province or new grid square
    /// - 2: New band (worked before, but not on this band)
    /// - 3: Normal (not previously worked, no special status)
    /// - 4: Duplicate (already worked on this band/mode)
    var sortPriority: Int {
        if isNewDXCC {
            return 0
        }
        if isNewState || isNewGrid {
            return 1
        }
        if isNewBand {
            return 2
        }
        if isDupe {
            return 4
        }
        return 3
    }
}

// MARK: - SNR Tier

public extension FT8EnrichedDecode {
    /// Signal strength classification for visual display.
    enum SNRTier: Sendable {
        /// Strong signal (SNR > -5 dB)
        case strong
        /// Medium signal (-5 dB to -15 dB inclusive)
        case medium
        /// Weak signal (SNR < -15 dB)
        case weak
    }

    /// Classifies an SNR value into a display tier.
    ///
    /// - Parameter snr: Signal-to-noise ratio in dB
    /// - Returns: The SNR tier for visual display
    static func snrTier(forSNR snr: Int) -> SNRTier {
        if snr > -5 {
            return .strong
        }
        if snr >= -15 {
            return .medium
        }
        return .weak
    }
}
