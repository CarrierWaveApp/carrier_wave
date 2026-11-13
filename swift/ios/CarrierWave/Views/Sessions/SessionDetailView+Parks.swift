// Session Detail View - Park Cards
//
// Loads park boundaries and builds ParkCardItems for the
// Instagram album-style carousel in SessionDetailView.

import CarrierWaveCore
import CarrierWaveData
import SwiftUI

extension SessionDetailView {
    /// Collect park references from session (rove stops or single park),
    /// fetch their GIS boundaries, and build carousel cards.
    func loadParkCards() async {
        guard ExperimentalFeature.isEnabled(.parkGIS) else {
            return
        }

        let parkEntries = collectParkEntries()
        guard !parkEntries.isEmpty else {
            return
        }

        let allRefs = parkEntries.flatMap(\.refs)
        let boundaries = await fetchBoundaries(refs: allRefs)

        parkCards = parkEntries.map { entry in
            ParkCardItem(
                id: entry.refs.joined(separator: ","),
                reference: entry.displayRef,
                name: entry.name,
                myGrid: entry.myGrid,
                qsoCount: entry.qsoCount,
                boundary: boundaries[entry.refs.first ?? ""]
            )
        }
    }

    // MARK: - Private Helpers

    private func collectParkEntries() -> [ParkEntry] {
        if let session, session.isRove {
            return session.mergedRoveStops.map { stop in
                let refs = ParkReference.split(stop.parkReference)
                let primary = refs.first ?? stop.parkReference
                let name = POTAParksCache.shared.nameSync(for: primary)
                return ParkEntry(
                    refs: refs,
                    displayRef: stop.parkReference,
                    name: name,
                    myGrid: stop.myGrid ?? session.myGrid,
                    qsoCount: stop.qsoCount
                )
            }
        }

        // Single park from session or activation
        let parkRef = session?.parkReference ?? activation?.parkReference
        guard let parkRef else {
            return []
        }
        let refs = ParkReference.split(parkRef)
        let primary = refs.first ?? parkRef
        let name = parkName ?? POTAParksCache.shared.nameSync(for: primary)
        let qsoCount = activation?.qsoCount ?? qsos.count
        return [ParkEntry(
            refs: refs,
            displayRef: parkRef,
            name: name,
            myGrid: session?.myGrid ?? activation?.qsos.first?.myGrid,
            qsoCount: qsoCount
        )]
    }

    /// Resolve park boundaries for the carousel via `ParkMapApi.parkBoundaries`
    /// (cache-through the `"park"` GIS cache), decode into `ParkBoundary` off the
    /// main actor, keyed by reference.
    private func fetchBoundaries(
        refs: [String]
    ) async -> [String: ParkBoundary] {
        guard !refs.isEmpty else {
            return [:]
        }
        do {
            let api = try await ParkMapAccess.api()
            let fetched = try await Task.detached(priority: .userInitiated) {
                try await api.parkBoundaries(refs: refs, simplify: nil)
            }.value
            let boundaries = await Task.detached(priority: .userInitiated) {
                fetched.compactMap { ParkBoundary.from(ffi: $0) }
            }.value
            return Dictionary(
                boundaries.map { ($0.reference, $0) },
                uniquingKeysWith: { first, _ in first }
            )
        } catch {
            return [:]
        }
    }
}

// MARK: - ParkEntry

/// Intermediate type for collecting park info before boundary fetch.
private struct ParkEntry {
    let refs: [String]
    let displayRef: String
    let name: String?
    let myGrid: String?
    let qsoCount: Int
}
