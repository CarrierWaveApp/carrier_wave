// Video Export Actor — QSO Enrichment
//
// Enriches QSO snapshots with callsign notes, club memberships, and contact counts.

import CarrierWaveCore
import CarrierWaveData
import CoreLocation
import Foundation
import SwiftData

// MARK: - QSO Enrichment

extension VideoExportActor {
    struct ClubInfo {
        let name: String
        let emoji: String?
    }

    /// Creates enriched VideoQSOSnapshots using a SINGLE ModelContext.
    /// All SwiftData lookups share the same context to avoid cross-context faulting.
    func enrichQSOSnapshots(
        qsos: [QSO],
        context: ModelContext
    ) async -> [VideoQSOSnapshot] {
        // Load enrichment data using the SAME context (no new ModelContext creation)
        let contactCounts = loadContactCounts(context: context)
        let clubLookup = await loadClubMemberships(qsos: qsos)
        let notesCache = CallsignNotesCache.shared

        return qsos.map { qso in
            buildEnrichedSnapshot(
                qso: qso,
                contactCounts: contactCounts,
                clubLookup: clubLookup,
                notesCache: notesCache
            )
        }
    }

    private func buildEnrichedSnapshot(
        qso: QSO,
        contactCounts: [String: Int],
        clubLookup: [String: ClubInfo],
        notesCache: CallsignNotesCache
    ) -> VideoQSOSnapshot {
        let coord = qso.theirGrid.flatMap { grid in
            MaidenheadConverter.coordinate(from: grid).map {
                CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
            }
        }

        let info = notesCache.infoSync(for: qso.callsign)
        let club = clubLookup[qso.callsign.uppercased()]
        let priorCount = contactCounts[qso.callsign.uppercased()] ?? 0

        return VideoQSOSnapshot(
            id: qso.id,
            callsign: qso.callsign,
            timestamp: qso.timestamp,
            band: qso.band,
            mode: qso.mode,
            rstSent: qso.rstSent,
            rstReceived: qso.rstReceived,
            coordinate: coord,
            distanceKm: nil,
            name: info?.displayName,
            clubEmoji: club?.emoji ?? info?.combinedEmoji,
            clubName: club?.name,
            priorQSOCount: priorCount,
            theirParkRef: qso.theirParkReference,
            sotaRef: qso.sotaRef,
            wwffRef: qso.wwffRef,
            country: qso.country
        )
    }

    /// Count prior QSOs per callsign using the existing context.
    private func loadContactCounts(context: ModelContext) -> [String: Int] {
        let predicate = #Predicate<QSO> { qso in
            !qso.isHidden
                && qso.mode != "WEATHER"
                && qso.mode != "SOLAR"
                && qso.mode != "NOTE"
        }
        let descriptor = BoundedDescriptor<QSO>(
            predicate: predicate,
            limit: BoundedDescriptor<QSO>.maxLimit
        )
        guard let qsos = try? context.boundedFetch(descriptor) else {
            return [:]
        }
        var counts: [String: Int] = [:]
        counts.reserveCapacity(qsos.count / 2)
        for qso in qsos {
            counts[qso.callsign, default: 0] += 1
        }
        return counts
    }

    /// Load club memberships for QSO callsigns using the in-memory club cache.
    private func loadClubMemberships(qsos: [QSO]) async -> [String: ClubInfo] {
        var result: [String: ClubInfo] = [:]
        let upperCallsigns = Set(qsos.map { $0.callsign.uppercased() })
        for callsign in upperCallsigns {
            let clubNames = await ClubsSyncService.shared.clubs(for: callsign)
            if let firstName = clubNames.first {
                result[callsign] = ClubInfo(name: firstName, emoji: nil)
            }
        }
        return result
    }
}
