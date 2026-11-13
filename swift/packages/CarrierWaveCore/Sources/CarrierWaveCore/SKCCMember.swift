import CarrierWaveCwFfi
import Foundation

// MARK: - SKCCAward

/// Highest SKCC award level achieved by a member.
///
/// Award progression: plain member → Centurion (100 SKCC QSOs) →
/// Tribune (50 QSOs with C/T/S members) → Tribune ×N multiplier (Tx2..Tx10) →
/// Senator (Tx8 + worked all states / 200 unique SKCC). See
/// https://www.skccgroup.com/awards/ for the full rules.
public enum SKCCAward: String, Codable, Equatable, CaseIterable, Sendable {
    case member
    case centurion
    case tribune
    case senator

    // MARK: Public

    /// Single-character suffix appended to the member number (e.g. `12345T`).
    /// Plain members display no suffix.
    public var suffixCharacter: String {
        switch self {
        case .member: ""
        case .centurion: "C"
        case .tribune: "T"
        case .senator: "S"
        }
    }

    /// Full display name for inspectors and tooltips.
    public var displayName: String {
        switch self {
        case .member: "Member"
        case .centurion: "Centurion"
        case .tribune: "Tribune"
        case .senator: "Senator"
        }
    }
}

// MARK: - SKCCMember

/// A single SKCC roster entry with the highest award level the member has earned.
public struct SKCCMember: Codable, Equatable, Sendable {
    // MARK: Lifecycle

    public init(
        number: Int,
        callsign: String,
        name: String?,
        spc: String?,
        award: SKCCAward,
        tribuneMultiplier: Int?,
        otherCallsigns: [String]
    ) {
        self.number = number
        self.callsign = callsign
        self.name = name
        self.spc = spc
        self.award = award
        self.tribuneMultiplier = tribuneMultiplier
        self.otherCallsigns = otherCallsigns
    }

    // MARK: Public

    /// Plain SKCC member number (e.g. `12345`)
    public let number: Int

    /// Current callsign, normalized to uppercase
    public let callsign: String

    /// Operator's first name (when the roster supplies one)
    public let name: String?

    /// State / Province / Country abbreviation
    public let spc: String?

    /// Highest award level achieved (member, centurion, tribune, senator)
    public let award: SKCCAward

    /// Tribune multiplier (`nil` for plain Tribune, `2`...`10` for Tx2..Tx10)
    public let tribuneMultiplier: Int?

    /// Other callsigns the member has held, all uppercased
    public let otherCallsigns: [String]

    /// Pretty roster badge, e.g. `12345T`, `67890Tx5`, `23456C`, `99999S`
    public var badge: String {
        guard award == .tribune, let multiplier = tribuneMultiplier, multiplier > 1 else {
            return "\(number)\(award.suffixCharacter)"
        }
        return "\(number)Tx\(multiplier)"
    }

    /// Long-form description used in the spot inspector.
    public var summary: String {
        var parts: [String] = [badge]
        if let name, !name.isEmpty {
            parts.append(name)
        }
        if let spc, !spc.isEmpty {
            parts.append(spc)
        }
        return parts.joined(separator: " · ")
    }
}

// MARK: - FFI bridging

extension SKCCAward {
    /// Lift the Rust award enum into the Swift enum.
    init(ffi: FfiSkccAward) {
        switch ffi {
        case .member: self = .member
        case .centurion: self = .centurion
        case .tribune: self = .tribune
        case .senator: self = .senator
        }
    }
}

extension SKCCMember {
    /// Build a Swift member from the Rust-parsed FFI record.
    init(ffi: FfiSkccMember) {
        self.init(
            number: Int(ffi.number),
            callsign: ffi.callsign,
            name: ffi.name,
            spc: ffi.spc,
            award: SKCCAward(ffi: ffi.award),
            tribuneMultiplier: ffi.tribuneMultiplier.map(Int.init),
            otherCallsigns: ffi.otherCallsigns
        )
    }
}
