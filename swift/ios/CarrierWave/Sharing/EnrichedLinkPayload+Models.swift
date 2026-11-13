//
//  EnrichedLinkPayload+Models.swift
//  CarrierWave
//
//  SwiftData-model → enriched-link-payload converters. These live in the
//  iOS app target (not CarrierWaveCore) because they import CarrierWaveData.
//

import CarrierWaveCore
import CarrierWaveData
import Foundation

// MARK: - QSO

@MainActor
extension EnrichedLinkPayload {
    /// Build a QSO payload from a SwiftData QSO model. Truncates long
    /// notes to fit within the activation note budget (also reasonable
    /// for QSO notes).
    static func from(qso: QSO, myCall: String) -> EnrichedLinkPayload {
        let truncatedNotes = qso.notes.flatMap { notes -> String? in
            guard !notes.isEmpty else {
                return nil
            }
            let limit = ActivationPayload.maxNoteLength
            return notes.count > limit
                ? String(notes.prefix(limit)) + "…"
                : notes
        }
        return .qso(QSOPayload(
            theirCall: qso.callsign,
            myCall: myCall,
            band: qso.band,
            mode: qso.mode,
            timestamp: qso.timestamp,
            frequency: qso.frequency,
            rstSent: qso.rstSent,
            rstReceived: qso.rstReceived,
            myGrid: qso.myGrid,
            theirGrid: qso.theirGrid,
            parkReference: qso.parkReference,
            notes: truncatedNotes
        ))
    }

    /// Build a callsign payload from any local context the caller has —
    /// optionally including a previously-fetched QRZ blob and "worked
    /// before" stats. The server adds DXCC/flag from cty.dat, so callers
    /// don't need to supply DXCC info here.
    static func callsign(
        _ call: String,
        name: String? = nil,
        grid: String? = nil,
        qth: String? = nil,
        country: String? = nil,
        workedCount: Int? = nil,
        lastWorked: Date? = nil,
        lastBand: String? = nil,
        lastMode: String? = nil,
        propagationHint: String? = nil
    ) -> EnrichedLinkPayload {
        .callsign(CallsignPayload(
            callsign: call,
            name: name,
            grid: grid,
            qth: qth,
            country: country,
            workedCount: workedCount,
            lastWorked: lastWorked,
            lastBand: lastBand,
            lastMode: lastMode,
            propagationHint: propagationHint
        ))
    }

    /// Build a park payload from a POTA reference. Caller may pass
    /// activation/hunt counts pulled from local stats.
    static func park(
        reference: String,
        name: String? = nil,
        state: String? = nil,
        country: String? = nil,
        latitude: Double? = nil,
        longitude: Double? = nil,
        userActivations: Int? = nil,
        userHunts: Int? = nil,
        isActiveNow: Bool? = nil
    ) -> EnrichedLinkPayload {
        .park(ParkPayload(
            reference: reference,
            name: name,
            state: state,
            country: country,
            latitude: latitude,
            longitude: longitude,
            userActivations: userActivations,
            userHunts: userHunts,
            isActiveNow: isActiveNow
        ))
    }

    /// Build a SOTA summit payload. Caller may pass local activation/chase
    /// counts pulled from local stats; otherwise omit them.
    static func summit(
        reference: String,
        name: String? = nil,
        associationName: String? = nil,
        regionName: String? = nil,
        altitudeMeters: Int? = nil,
        points: Int? = nil,
        latitude: Double? = nil,
        longitude: Double? = nil,
        activationCount: Int? = nil,
        userActivations: Int? = nil,
        userChases: Int? = nil
    ) -> EnrichedLinkPayload {
        .summit(SummitPayload(
            reference: reference,
            name: name,
            associationName: associationName,
            regionName: regionName,
            altitudeMeters: altitudeMeters,
            points: points,
            latitude: latitude,
            longitude: longitude,
            activationCount: activationCount,
            userActivations: userActivations,
            userChases: userChases
        ))
    }
}
