//
//  ActivationTruncation.swift
//  CarrierWaveCore
//
//  Progressive truncation for activation payloads. The fragment budget
//  is 1.5 KB total URL — most activations fit at level 0, but multi-band
//  multi-mode rove activations may need truncation.
//

import Foundation

enum ActivationTruncation {
    // MARK: Internal

    enum Level: Int, CaseIterable {
        case full = 0
        case dropNotes
        case truncateBandModes
        case dropDxcc
        case dropParkToPark
        case dropEndTime
        case dropBandsModes
    }

    static let allLevels: [Level] = Level.allCases

    static func apply(
        _ level: Level,
        to original: ActivationPayload
    ) -> ActivationPayload {
        switch level {
        case .full:
            original
        case .dropNotes:
            rebuild(original, notes: nil)
        case .truncateBandModes:
            rebuild(
                original,
                bands: trimmedArray(original.bands),
                modes: trimmedArray(original.modes),
                notes: nil
            )
        case .dropDxcc:
            rebuild(
                original,
                bands: trimmedArray(original.bands),
                modes: trimmedArray(original.modes),
                dxccCount: nil,
                notes: nil
            )
        case .dropParkToPark:
            rebuild(
                original,
                bands: trimmedArray(original.bands),
                modes: trimmedArray(original.modes),
                parkToParkCount: nil,
                dxccCount: nil,
                notes: nil
            )
        case .dropEndTime:
            rebuild(
                original,
                endTime: nil,
                bands: trimmedArray(original.bands),
                modes: trimmedArray(original.modes),
                parkToParkCount: nil,
                dxccCount: nil,
                notes: nil
            )
        case .dropBandsModes:
            rebuild(
                original,
                endTime: nil,
                bands: [],
                modes: [],
                parkToParkCount: nil,
                dxccCount: nil,
                notes: nil
            )
        }
    }

    // MARK: Private

    private static func trimmedArray(_ array: [String]) -> [String] {
        Array(array.prefix(ActivationPayload.maxBandModeArrayLength))
    }

    /// Rebuild an activation payload, defaulting any unspecified field to
    /// the original's value. Each truncation level overrides only the
    /// fields it drops.
    private static func rebuild(
        _ original: ActivationPayload,
        endTime: Date?? = .none,
        bands: [String]? = nil,
        modes: [String]? = nil,
        parkToParkCount: Int?? = .none,
        dxccCount: Int?? = .none,
        notes: String?? = .none
    ) -> ActivationPayload {
        ActivationPayload(
            myCall: original.myCall,
            parkReference: original.parkReference,
            parkName: original.parkName,
            startTime: original.startTime,
            endTime: endTime ?? original.endTime,
            qsoCount: original.qsoCount,
            bands: bands ?? original.bands,
            modes: modes ?? original.modes,
            parkToParkCount: parkToParkCount ?? original.parkToParkCount,
            dxccCount: dxccCount ?? original.dxccCount,
            notes: notes ?? original.notes
        )
    }
}
