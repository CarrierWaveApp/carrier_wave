import Foundation

// MARK: - QSOMapView Data Helpers

extension QSOMapView {
    /// Filter snapshots based on current filter state
    static func filterSnapshots(
        _ snapshots: [MapQSOSnapshot],
        with filterState: MapFilterState
    ) -> [MapQSOSnapshot] {
        snapshots.filter { snapshot in
            // Must have their grid
            guard let theirGrid = snapshot.theirGrid, !theirGrid.isEmpty else {
                return false
            }

            // Date range filter
            if let start = filterState.startDate, snapshot.timestamp < start {
                return false
            }
            if let end = filterState.endDate, snapshot.timestamp > end {
                return false
            }

            // Band filter (case-insensitive)
            if let band = filterState.selectedBand,
               snapshot.band.uppercased() != band.uppercased()
            {
                return false
            }

            // Mode filter (case-insensitive)
            if let mode = filterState.selectedMode,
               snapshot.mode.uppercased() != mode.uppercased()
            {
                return false
            }

            // Park filter
            if let park = filterState.selectedPark, snapshot.parkReference != park {
                return false
            }

            // Confirmed filter (include if confirmed by either QRZ or LoTW)
            if filterState.confirmedOnly, !snapshot.lotwConfirmed, !snapshot.qrzConfirmed {
                return false
            }

            return true
        }
    }

    /// Compute annotations from snapshots
    static func computeAnnotations(
        from snapshots: [MapQSOSnapshot],
        showIndividual: Bool
    ) -> [QSOAnnotation] {
        if showIndividual {
            computeIndividualAnnotations(from: snapshots)
        } else {
            computeClusteredAnnotations(from: snapshots)
        }
    }

    /// Create individual annotations for each QSO
    private static func computeIndividualAnnotations(
        from snapshots: [MapQSOSnapshot]
    ) -> [QSOAnnotation] {
        snapshots.compactMap { snapshot -> QSOAnnotation? in
            guard let grid = snapshot.theirGrid, grid.count >= 4,
                  let coordinate = MaidenheadConverter.coordinate(from: grid)
            else {
                return nil
            }

            return QSOAnnotation(
                id: snapshot.id.uuidString,
                coordinate: coordinate,
                gridSquare: String(grid.prefix(4)).uppercased(),
                qsoCount: 1,
                callsigns: [snapshot.callsign],
                mostRecentDate: snapshot.timestamp
            )
        }
    }

    /// Create clustered annotations grouped by 4-char grid
    private static func computeClusteredAnnotations(
        from snapshots: [MapQSOSnapshot]
    ) -> [QSOAnnotation] {
        var gridGroups: [String: [MapQSOSnapshot]] = [:]

        for snapshot in snapshots {
            guard let grid = snapshot.theirGrid, grid.count >= 4 else {
                continue
            }
            let gridKey = String(grid.prefix(4)).uppercased()
            gridGroups[gridKey, default: []].append(snapshot)
        }

        return gridGroups.compactMap { gridKey, snapshots -> QSOAnnotation? in
            guard let coordinate = MaidenheadConverter.coordinate(from: gridKey) else {
                return nil
            }

            let callsigns = snapshots.map(\.callsign).sorted()
            let mostRecent = snapshots.map(\.timestamp).max() ?? Date()

            return QSOAnnotation(
                id: gridKey,
                coordinate: coordinate,
                gridSquare: gridKey,
                qsoCount: snapshots.count,
                callsigns: callsigns,
                mostRecentDate: mostRecent
            )
        }
    }

    /// Compute arcs from snapshots
    static func computeArcs(from snapshots: [MapQSOSnapshot]) -> [QSOArc] {
        var result: [QSOArc] = []

        for snapshot in snapshots {
            guard let myGrid = snapshot.myGrid,
                  let theirGrid = snapshot.theirGrid,
                  let from = MaidenheadConverter.coordinate(from: myGrid),
                  let to = MaidenheadConverter.coordinate(from: theirGrid)
            else {
                continue
            }

            result.append(
                QSOArc(
                    id: snapshot.id.uuidString,
                    from: from,
                    to: to,
                    callsign: snapshot.callsign
                )
            )
        }

        return result
    }
}
