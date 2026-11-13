import CarrierWaveCore
import CarrierWaveData
import CoreLocation
import MapKit
import SwiftUI

// MARK: - Data Loading & Boundary Management

extension ParkSearchMapView {
    /// Debounced viewport pin fetch — mirrors the 500ms settle debounce
    /// used for boundaries/trails so a fast pan doesn't spam `pinsInBox`.
    func fetchPinsForRegion(_ region: MKCoordinateRegion) {
        pinFetchTask?.cancel()
        pinFetchTask = Task {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else {
                return
            }
            await loadPinsInBox(region)
        }
    }

    /// Load park/summit pins for the current viewport via `ParkMapApi.pinsInBox`,
    /// materializing each `FfiParkPin` reference back into the full
    /// `POTAPark`/`SOTASummit` record from the existing reference caches
    /// (already hydrated app-wide at launch) so `ParkSearchMapKit` /
    /// `ClusterMap` / callouts keep consuming the same full-detail types.
    /// Fetches both kinds regardless of the show/hide toggles — visibility
    /// gating happens downstream in `ParkSearchMapKit`/`ClusterMap`, same as
    /// the previous full-dataset load.
    ///
    /// Fetches at ALL zoom levels, including continental/world zoom — there is
    /// intentionally no span guard here (unlike `fetchBoundariesForRegion`/
    /// `fetchTrailsForRegion`, which skip fetching past a ~5° span). A guard
    /// would blank the map at zoomed-out levels; the old full-dataset code
    /// always had every park/summit in memory and rendered clusters at every
    /// zoom, so an empty map at zoom-out would be a regression, not a parity
    /// improvement. Each kind is capped at 500 rows per `pinsInBox`; the store
    /// returns rows ordered highest-priority-first (POTA: reference; SOTA:
    /// points DESC; per the `fetch_*_in_box` store queries), so a capped
    /// viewport is a deterministic, principled subset rather than an arbitrary
    /// slice — `ClusterMap` then clusters whatever the store returns.
    func loadPinsInBox(_ region: MKCoordinateRegion) async {
        let bbox = FfiBoundingBox(mapRegion: region)
        do {
            let api = try await ParkMapAccess.api()
            let pins = try await Task.detached(priority: .userInitiated) {
                try api.pinsInBox(bbox: bbox, kinds: ["park", "summit"], limit: 500)
            }.value
            guard !Task.isCancelled else {
                return
            }
            visibleParks = pins
                .filter { $0.kind == "park" }
                .compactMap { POTAParksCache.shared.parkSync(for: $0.reference) }
            visibleSummits = pins
                .filter { $0.kind == "summit" }
                .compactMap { SOTASummitsCache.shared.summitSync(for: $0.reference) }
        } catch {
            RadioService.shared.addLog(.error, "Park map pin load failed: \(error)")
        }
    }

    /// Fetch park boundaries for the viewport via `ParkMapApi.parkBoundariesInBox`
    /// (cache-through the `"park"` GIS cache), decode into `ParkBoundary` render
    /// models off-main, and merge in the ones we don't already hold. The span
    /// guard and 500ms debounce predate this phase and stay.
    func fetchBoundariesForRegion(_ region: MKCoordinateRegion) async {
        guard showBoundaries else {
            return
        }

        // Cancel any pending fetch
        boundaryFetchTask?.cancel()

        // Don't fetch if zoomed out too far (span > ~5 degrees)
        guard region.span.latitudeDelta < 5, region.span.longitudeDelta < 5 else {
            return
        }

        // Simplify polygons based on zoom level — more simplified when zoomed out
        let simplifyTolerance = simplifyTolerance(for: region)
        let bbox = FfiBoundingBox(mapRegion: region)

        boundaryFetchTask = Task {
            // Debounce: wait 500ms after map stops moving
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else {
                return
            }

            // Snapshot known refs so we can skip reprocessing them.
            let knownRefs = Set(boundariesByRef.keys)
            await loadBoundaries(
                bbox: bbox, simplifyTolerance: simplifyTolerance, knownRefs: knownRefs
            )
        }
    }

    /// Fetch + decode + merge park boundaries for the viewport.
    private func loadBoundaries(
        bbox: FfiBoundingBox, simplifyTolerance: Double, knownRefs: Set<String>
    ) async {
        isLoadingBoundaries = true
        defer { isLoadingBoundaries = false }
        do {
            let api = try await ParkMapAccess.api()
            let fetched = try await Task.detached(priority: .userInitiated) {
                try await api.parkBoundariesInBox(
                    bbox: bbox, limit: 50, simplify: simplifyTolerance
                )
            }.value
            guard !Task.isCancelled else {
                return
            }
            let newBoundaries = await Task.detached(priority: .userInitiated) {
                fetched.compactMap { boundary -> ParkBoundary? in
                    guard !knownRefs.contains(boundary.reference) else {
                        return nil
                    }
                    return ParkBoundary.from(ffi: boundary)
                }
            }.value
            if !newBoundaries.isEmpty {
                mergeBoundaries(newBoundaries)
            }
        } catch {
            RadioService.shared.addLog(.error, "Boundary fetch failed: \(error)")
        }
    }

    /// Choose polygon simplification tolerance based on zoom level.
    /// Wider spans = more aggressive simplification (fewer polygon points).
    func simplifyTolerance(for region: MKCoordinateRegion) -> Double {
        let span = max(region.span.latitudeDelta, region.span.longitudeDelta)
        if span > 3 {
            return 0.005 // Very zoomed out — aggressive simplification
        } else if span > 1 {
            return 0.002
        } else if span > 0.3 {
            return 0.001
        } else {
            return 0.0005 // Close zoom — high detail
        }
    }

    /// Merge new boundaries into existing set, replacing duplicates.
    /// Evicts the farthest boundaries when over the limit.
    func mergeBoundaries(_ newBoundaries: [ParkBoundary]) {
        var byRef = boundariesByRef
        for boundary in newBoundaries {
            byRef[boundary.reference] = boundary
        }
        // Keep bounded to avoid unbounded memory growth and render overhead
        let maxCached = 150
        if byRef.count > maxCached, let region = lastVisibleRegion {
            let centerLat = region.center.latitude
            let centerLon = region.center.longitude
            let newRefs = Set(newBoundaries.map(\.reference))
            // Sort non-new boundaries by distance from viewport center, keep closest
            let others = byRef.filter { !newRefs.contains($0.key) }
            let sorted = others.sorted { lhs, rhs in
                let distA = abs(lhs.value.bbox.centerLat - centerLat)
                    + abs(lhs.value.bbox.centerLon - centerLon)
                let distB = abs(rhs.value.bbox.centerLat - centerLat)
                    + abs(rhs.value.bbox.centerLon - centerLon)
                return distA < distB
            }
            let keepCount = maxCached - newBoundaries.count
            var kept = Dictionary(
                sorted.prefix(max(0, keepCount)).map { ($0.key, $0.value) },
                uniquingKeysWith: { first, _ in first }
            )
            for boundary in newBoundaries {
                kept[boundary.reference] = boundary
            }
            byRef = kept
        }
        boundariesByRef = byRef
    }

    // MARK: - Trail Loading

    func fetchTrailsForRegion(_ region: MKCoordinateRegion) {
        trailFetchTask?.cancel()

        // Don't fetch if zoomed out too far
        guard region.span.latitudeDelta < 5,
              region.span.longitudeDelta < 5
        else {
            return
        }

        let simplifyTolerance = simplifyTolerance(for: region)
        let bbox = FfiBoundingBox(mapRegion: region)

        trailFetchTask = Task {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else {
                return
            }
            await loadTrails(bbox: bbox, simplifyTolerance: simplifyTolerance)
        }
    }

    /// Fetch trails via `ParkMapApi.trailsInBox` (cache-through the `"trail"` GIS
    /// cache), decode into `TrailBoundary` render models off-main, and merge.
    private func loadTrails(bbox: FfiBoundingBox, simplifyTolerance: Double) async {
        do {
            let api = try await ParkMapAccess.api()
            let fetched = try await Task.detached(priority: .userInitiated) {
                try await api.trailsInBox(bbox: bbox, limit: 50, simplify: simplifyTolerance)
            }.value
            guard !Task.isCancelled else {
                return
            }
            let newTrails = await Task.detached(priority: .userInitiated) {
                fetched.compactMap { TrailBoundary.from(ffi: $0) }
            }.value
            if !newTrails.isEmpty {
                mergeTrails(newTrails)
            }
        } catch {
            // Silently ignore trail fetch errors (parity with prior behavior).
        }
    }

    /// Merge new trails into existing set, replacing duplicates
    func mergeTrails(_ newTrails: [TrailBoundary]) {
        var byRef = trailsByRef
        for trail in newTrails {
            byRef[trail.reference] = trail
        }
        // Keep bounded to avoid unbounded memory growth
        let maxCached = 100
        if byRef.count > maxCached {
            let newRefs = Set(newTrails.map(\.reference))
            let others = byRef.filter { !newRefs.contains($0.key) }
            let keepCount = maxCached - newTrails.count
            var kept = Dictionary(
                others.prefix(max(0, keepCount)).map { ($0.key, $0.value) },
                uniquingKeysWith: { first, _ in first }
            )
            for trail in newTrails {
                kept[trail.reference] = trail
            }
            byRef = kept
        }
        trailsByRef = byRef
    }

    func recenterOnMyLocation() {
        // Bump the token so the UIViewRepresentable triggers
        // `setUserTrackingMode(.follow)`, which pins the camera to the live GPS
        // fix. Crucially we do NOT also set `mapRegion` here: setting the region
        // to the coarse home grid in the same `updateUIView` pass cancels the
        // user-tracking animation and strands the map on the grid-square center
        // instead of the user's real location. The map's coordinator handles
        // the no-permission fallback to `homeFallback` on its own.
        recenterToken &+= 1
    }

    // MARK: - Park Lookup

    /// Find a POTAPark matching a boundary reference.
    /// Checks visible parks first, then falls back to the full parks cache.
    func findPark(for reference: String) -> POTAPark? {
        if let park = visibleParks.first(where: { $0.reference == reference }) {
            return park
        }
        return POTAParksCache.shared.parkSync(for: reference)
    }

    /// Find the first boundary whose polygon (including skirt buffer) contains the
    /// given coordinate. Point-in-ring uses the shared `pointInRing` FFI. Checks
    /// exact boundaries first, then the precomputed skirt for near-edge taps.
    func boundaryContaining(_ point: CLLocationCoordinate2D) -> String? {
        let ffiPoint = FfiCoordinate(latitude: point.latitude, longitude: point.longitude)
        // Only check boundaries near the tap point (bbox filter)
        let candidates = boundariesByRef.values.filter { boundary in
            boundary.bbox.minLat <= point.latitude
                && boundary.bbox.maxLat >= point.latitude
                && boundary.bbox.minLon <= point.longitude
                && boundary.bbox.maxLon >= point.longitude
        }

        // Check actual boundaries first (exact match)
        for boundary in candidates {
            for polygon in boundary.mergedPolygons {
                let inExterior = pointInFfiRing(ffiPoint, ring: polygon.exterior)
                let inHole = polygon.holes.contains { hole in
                    pointInFfiRing(ffiPoint, ring: hole)
                }
                if inExterior, !inHole {
                    return boundary.reference
                }
            }
        }
        // Fall back to precomputed skirt for near-edge taps
        for boundary in candidates {
            for polygon in boundary.mergedPolygons {
                let inHole = polygon.holes.contains { hole in
                    pointInFfiRing(ffiPoint, ring: hole)
                }
                if pointInFfiRing(ffiPoint, ring: polygon.skirt), !inHole {
                    return boundary.reference
                }
            }
        }
        return nil
    }

    /// Find the first trail whose skirt polygon contains the given coordinate.
    func trailContaining(_ point: CLLocationCoordinate2D) -> TrailBoundary? {
        let ffiPoint = FfiCoordinate(latitude: point.latitude, longitude: point.longitude)
        for trail in trailsByRef.values {
            for polygon in trail.skirtPolygons
                where pointInFfiRing(ffiPoint, ring: polygon)
            {
                return trail
            }
        }
        return nil
    }

    // MARK: - Search

    func updateSearchResults(query: String) async {
        do {
            let api = try await ParkMapAccess.api()
            // Two separate calls, one per kind, each with its own `limit: 10`
            // (restoring the old per-kind result floor) — `ParkMapApi.search`'s
            // `limit` is a single combined cap across all requested kinds, so a
            // single `kinds: ["park", "summit"], limit: 20` call could let one
            // kind's matches starve the other (e.g. 20 park hits crowding out
            // every summit hit) instead of guaranteeing up to 10 of each.
            async let parkHits = Task.detached(priority: .userInitiated) {
                try api.search(query: query, kinds: ["park"], limit: 10)
            }.value
            async let summitHits = Task.detached(priority: .userInitiated) {
                try api.search(query: query, kinds: ["summit"], limit: 10)
            }.value
            let hits = try await parkHits + summitHits
            guard !Task.isCancelled else {
                return
            }
            let parks = hits
                .filter { $0.kind == "park" }
                .compactMap { POTAParksCache.shared.parkSync(for: $0.reference) }
            let summits = hits
                .filter { $0.kind == "summit" }
                .compactMap { SOTASummitsCache.shared.summitSync(for: $0.reference) }
            searchResults = parks
            summitSearchResults = summits

            // Auto-zoom to best match
            if let first = parks.first {
                zoomToPark(first)
            } else if let first = summits.first {
                zoomToSummit(first)
            }
        } catch {
            RadioService.shared.addLog(.error, "Park/summit search failed: \(error)")
        }
    }

    func searchForParkOrSummit() {
        if let first = searchResults.first {
            selectAndZoom(to: first)
        } else if let first = summitSearchResults.first {
            selectAndZoomToSummit(first)
        }
    }

    func selectAndZoom(to park: POTAPark) {
        selection = .park(park)
        searchText = ""
        searchResults = []
        summitSearchResults = []

        guard let lat = park.latitude, let lon = park.longitude else {
            return
        }

        withAnimation {
            mapRegion = MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
            )
        }
    }

    func selectAndZoomToSummit(_ summit: SOTASummit) {
        selection = .summit(summit)
        searchText = ""
        searchResults = []
        summitSearchResults = []

        guard let lat = summit.latitude, let lon = summit.longitude else {
            return
        }

        withAnimation {
            mapRegion = MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
            )
        }
    }

    /// Zoom to a park and select it, keeping search results visible.
    func zoomToPark(_ park: POTAPark) {
        selection = .park(park)
        guard let lat = park.latitude, let lon = park.longitude else {
            return
        }
        withAnimation {
            mapRegion = MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
            )
        }
    }

    /// Zoom to a summit and select it, keeping search results visible.
    func zoomToSummit(_ summit: SOTASummit) {
        selection = .summit(summit)
        guard let lat = summit.latitude, let lon = summit.longitude else {
            return
        }
        withAnimation {
            mapRegion = MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
            )
        }
    }

    // MARK: - Geometry

    /// Ray-cast point-in-ring test via the shared `pointInRing` FFI (the same
    /// helper the Rust rosette scan uses), bridging the coordinate ring.
    private func pointInFfiRing(
        _ point: FfiCoordinate,
        ring: [CLLocationCoordinate2D]
    ) -> Bool {
        pointInRing(
            point: point,
            ring: ring.map { FfiCoordinate(latitude: $0.latitude, longitude: $0.longitude) }
        )
    }
}
