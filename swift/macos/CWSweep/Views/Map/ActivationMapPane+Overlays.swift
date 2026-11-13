import CarrierWaveCore
import MapKit
import SwiftUI

// MARK: - ActivationMapPane + Spot Overlays

extension ActivationMapPane {
    /// RBN spots where skimmers heard the user's callsign, with valid spotter grids.
    var rbnSkimmerSpots: [EnrichedSpot] {
        guard !myCallsign.isEmpty else {
            return []
        }
        return spotAggregator.spots.filter { enriched in
            enriched.spot.source == .rbn
                && enriched.spot.isSelfSpot(userCallsign: myCallsign)
                && enriched.spot.spotterGrid != nil
                && MaidenheadConverter.coordinate(from: enriched.spot.spotterGrid!) != nil
        }
    }

    /// All spots (non-self) that have a plottable DX grid.
    var plottableSpots: [EnrichedSpot] {
        spotAggregator.spots.filter { enriched in
            guard let grid = enriched.spot.dxGrid,
                  MaidenheadConverter.coordinate(from: grid) != nil
            else {
                return false
            }
            // Exclude self-spots (already shown as QSOs)
            if !myCallsign.isEmpty, enriched.spot.isSelfSpot(userCallsign: myCallsign) {
                return false
            }
            return true
        }
    }

    /// Map annotations for RBN skimmer locations.
    @MapContentBuilder
    var rbnAnnotations: some MapContent {
        ForEach(rbnSkimmerSpots) { enriched in
            if let grid = enriched.spot.spotterGrid,
               let coord = MaidenheadConverter.coordinate(from: grid)
            {
                let clCoord = CLLocationCoordinate2D(
                    latitude: coord.latitude, longitude: coord.longitude
                )
                let snr = enriched.spot.snr ?? 0
                let size = rbnMarkerSize(snr: snr)

                Annotation(
                    enriched.spot.spotter ?? "RBN",
                    coordinate: clCoord
                ) {
                    VStack(spacing: 1) {
                        Circle()
                            .fill(Color.cyan.opacity(0.7))
                            .frame(width: size, height: size)
                            .overlay(Circle().stroke(Color.cyan, lineWidth: 0.5))
                        Text("\(snr) dB")
                            .font(.system(size: 8).monospacedDigit())
                            .foregroundStyle(.cyan)
                    }
                }
                .annotationTitles(.hidden)
            }
        }
    }

    /// Map annotations for non-self spots with known DX grids.
    @MapContentBuilder
    var spotAnnotations: some MapContent {
        ForEach(plottableSpots) { enriched in
            if let grid = enriched.spot.dxGrid,
               let coord = MaidenheadConverter.coordinate(from: grid)
            {
                let clCoord = CLLocationCoordinate2D(
                    latitude: coord.latitude, longitude: coord.longitude
                )
                let color = Self.bandColors[enriched.spot.band] ?? .gray

                Annotation(enriched.spot.callsign, coordinate: clCoord) {
                    Circle()
                        .fill(color.opacity(0.5))
                        .frame(width: 8, height: 8)
                        .overlay(Circle().stroke(color, lineWidth: 1))
                }
                .annotationTitles(.hidden)
            }
        }
    }

    /// Marker size scaling with SNR: base 8pt, +1pt per 5dB above 5, capped at 16pt.
    func rbnMarkerSize(snr: Int) -> CGFloat {
        let base: CGFloat = 8
        let extra = CGFloat(max(0, snr - 5)) / 5.0
        return min(base + extra, 16)
    }

    /// Spots whose `spot_id` is in the saved query's allow-list. We
    /// render either the spotter's grid (for self-spots, since RBN is
    /// the obvious self-spot source) or the DX grid otherwise — the
    /// same routing the dedicated RBN/Spots modes use.
    var querySpots: [EnrichedSpot] {
        guard let allowed = queryRunner.allowedSpotIDs else {
            return []
        }
        return spotAggregator.spots.filter { enriched in
            allowed.contains(enriched.spot.id) && queryCoordinate(for: enriched) != nil
        }
    }

    /// Resolve which grid to plot a query-result spot at — spotter for
    /// RBN self-spots (so the "who heard me" use case still works
    /// inside a query) and dxGrid otherwise.
    func queryCoordinate(for enriched: EnrichedSpot) -> CLLocationCoordinate2D? {
        let spot = enriched.spot
        let isSelf = !myCallsign.isEmpty && spot.isSelfSpot(userCallsign: myCallsign)
        let grid: String? = if isSelf, spot.source == .rbn {
            spot.spotterGrid
        } else {
            spot.dxGrid ?? spot.spotterGrid
        }
        guard let grid, let coord = MaidenheadConverter.coordinate(from: grid) else {
            return nil
        }
        return CLLocationCoordinate2D(latitude: coord.latitude, longitude: coord.longitude)
    }

    /// Map annotations for spots in the SQL query allow-list. Markers
    /// blend the all-spots circle styling with an RBN-style SNR badge
    /// when the spot carries one — a query that joins skimmers stays
    /// readable.
    @MapContentBuilder
    var queryAnnotations: some MapContent {
        ForEach(querySpots) { enriched in
            if let coord = queryCoordinate(for: enriched) {
                let color = Self.bandColors[enriched.spot.band] ?? .gray
                Annotation(enriched.spot.callsign, coordinate: coord) {
                    VStack(spacing: 1) {
                        Circle()
                            .fill(color.opacity(0.7))
                            .frame(width: 9, height: 9)
                            .overlay(Circle().stroke(.white, lineWidth: 1))
                        if let snr = enriched.spot.snr {
                            Text("\(snr) dB")
                                .font(.system(size: 8).monospacedDigit())
                                .foregroundStyle(color)
                        }
                    }
                }
                .annotationTitles(.hidden)
            }
        }
    }
}

// MARK: - ActivationMapPane + Geodesic Arc

extension ActivationMapPane {
    /// Geodesic arc overlay between user QTH and the entry callsign's grid.
    @MapContentBuilder
    var arcOverlay: some MapContent {
        if case let .geodesicFocus(grid) = mapState,
           let userCoord = userCoordinate,
           let theirCoordRaw = MaidenheadConverter.coordinate(from: grid)
        {
            let segments = arcSegments(
                from: userCoord,
                to: CLLocationCoordinate2D(
                    latitude: theirCoordRaw.latitude,
                    longitude: theirCoordRaw.longitude
                )
            )
            ForEach(segments.indices, id: \.self) { idx in
                MapPolyline(coordinates: segments[idx])
                    .stroke(.orange, lineWidth: 2)
            }

            // Destination marker
            let destCoord = CLLocationCoordinate2D(
                latitude: theirCoordRaw.latitude,
                longitude: theirCoordRaw.longitude
            )
            Annotation("", coordinate: destCoord) {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.caption)
                    .foregroundStyle(.white)
                    .padding(4)
                    .background(.orange, in: Circle())
            }
            .annotationTitles(.hidden)
        }
    }

    /// Compute great circle arc, split at antimeridian if needed.
    func arcSegments(
        from start: CLLocationCoordinate2D,
        to end: CLLocationCoordinate2D
    ) -> [[CLLocationCoordinate2D]] {
        let path = AzimuthalProjection.greatCirclePath(
            fromLat: start.latitude, fromLon: start.longitude,
            toLat: end.latitude, toLon: end.longitude,
            segments: 50
        )

        let coords = path.map {
            CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon)
        }

        // Check for antimeridian crossing
        var segments: [[CLLocationCoordinate2D]] = []
        var current: [CLLocationCoordinate2D] = []

        for (idx, coord) in coords.enumerated() {
            current.append(coord)
            if idx > 0 {
                let lonDelta = abs(coord.longitude - coords[idx - 1].longitude)
                if lonDelta > 180 {
                    // Split here
                    segments.append(current)
                    current = [coord]
                }
            }
        }
        if !current.isEmpty {
            segments.append(current)
        }

        return segments
    }
}
