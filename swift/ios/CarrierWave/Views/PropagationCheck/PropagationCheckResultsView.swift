import CarrierWaveCore
import CarrierWaveData
import CoreLocation
import SwiftUI

// MARK: - PropagationCheckResultsView

/// Results screen for a saved propagation check. Everything renders inline:
/// headline counters, home → skimmer map with geodesic arcs, per-band table,
/// geographic breakdown, timeline chart, distance histogram, and meta.
struct PropagationCheckResultsView: View {
    // MARK: Internal

    let check: PropagationCheck

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                headlineCard
                mapModePicker
                mapSection
                sparseHelpCard
                if check.hasSolarData {
                    PropagationCheckSolarCard(check: check)
                }
                detailsSection
            }
            .padding()
        }
        .navigationTitle(check.label.isEmpty ? "Propagation Check" : check.label)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    presentEditSheet = true
                } label: {
                    Label("Edit", systemImage: "pencil")
                }
            }
        }
        .sheet(isPresented: $presentEditSheet) {
            PropagationCheckMetadataEditSheet(check: check)
        }
        .task(id: check.id) {
            guard blob.spots.contains(where: { $0.skimmerGrid == nil }) else {
                // New artifacts persist enriched grids on every spot — nothing to backfill.
                return
            }
            enrichedGrids = await PropagationCheckLegacyEnrichment.resolveMissingGrids(for: blob.spots)
        }
    }

    // MARK: Private

    @State private var geoMode: GeoMode = .continent
    @State private var mapMode: MapMode = .standard
    @State private var presentEditSheet = false
    /// Base callsign → grid, resolved via a view-time callbook `locate` pass for
    /// legacy artifacts saved before commit e1ce3a3b (which deleted the view-time
    /// HamDB re-enrichment path). New artifacts are enriched at persist time by the
    /// Rust engine and never populate this.
    @State private var enrichedGrids: [String: String] = [:]

    private var blob: PropagationCheckBlob {
        check.decodedBlob ?? PropagationCheckBlob()
    }

    /// Project the persisted spots to coordinate/distance/bearing off their
    /// reported grids, falling back to `enrichedGrids` (view-time callbook
    /// locate) for legacy artifacts whose spots were saved without a grid.
    private var enrichedSpots: [PropagationEnrichedSpot] {
        let userGrid = check.userGridUsed
        let userCoord = MaidenheadConverter.coordinate(from: userGrid)
        return blob.spots.map { entry in
            let effectiveGrid = entry.skimmerGrid
                ?? enrichedGrids[PropagationCheckLegacyEnrichment.baseSkimmerCallsign(entry.skimmerCall)]
            let coord = effectiveGrid.flatMap(MaidenheadConverter.coordinate(from:))
            var distanceKm: Double?
            var bearing: Double?
            if let effectiveGrid, userCoord != nil {
                distanceKm = MaidenheadConverter.distanceKm(from: userGrid, to: effectiveGrid)
                bearing = MaidenheadConverter.bearing(from: userGrid, to: effectiveGrid)
            }
            return PropagationEnrichedSpot(
                id: PropagationCheck.dedupKey(for: entry),
                entry: entry,
                effectiveGrid: effectiveGrid,
                coordinate: coord,
                distanceKm: distanceKm,
                bearing: bearing
            )
        }
    }

    /// `blob.spots` with `skimmerGrid` patched from `enrichedGrids` when missing,
    /// so `PropagationCheckStatistics` sees every resolvable spot for band /
    /// geography / distance breakdowns — not just the ones saved with a grid.
    private var effectiveEntries: [PropagationSpotEntry] {
        guard !enrichedGrids.isEmpty else {
            return blob.spots
        }
        return blob.spots.map { entry in
            var patched = entry
            if patched.skimmerGrid == nil {
                patched
                    .skimmerGrid =
                    enrichedGrids[PropagationCheckLegacyEnrichment.baseSkimmerCallsign(entry.skimmerCall)]
            }
            return patched
        }
    }

    /// Recomputed headline that picks up grids resolved after the session
    /// ended — either baked in at persist time by the Rust engine (new
    /// artifacts) or backfilled at view time via callbook locate (legacy
    /// artifacts, see `enrichedGrids`).
    private var liveHeadline: PropagationCheckStatistics.Headline {
        PropagationCheckStatistics.compute(
            spots: effectiveEntries,
            userGrid: check.userGridUsed
        )
    }

    private var headlineCard: some View {
        let headline = liveHeadline
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                statTile(title: "Spots", value: "\(headline.totalSpots)")
                statTile(title: "Skimmers", value: "\(headline.uniqueSkimmers)")
                statTile(title: "Bands", value: "\(headline.bandsWithActivity.count)")
            }
            HStack {
                statTile(title: "Max distance", value: distanceLabel(headline.maxDistanceKm))
                statTile(title: "Peak SNR", value: "\(Int(headline.peakSNRdB)) dB")
                statTile(title: "Duration", value: durationLabel(check.duration))
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
    }

    private var mapModePicker: some View {
        Picker("Map", selection: $mapMode) {
            ForEach(MapMode.allCases) { mode in
                Text(mode.label).tag(mode)
            }
        }
        .pickerStyle(.segmented)
    }

    @ViewBuilder
    private var mapSection: some View {
        switch mapMode {
        case .standard:
            PropagationCheckMapCard(check: check, enrichedSpots: enrichedSpots)
        case .azimuthal:
            PropagationCheckAzimuthalCard(
                userGrid: check.userGridUsed,
                enrichedSpots: enrichedSpots
            )
        }
    }

    @ViewBuilder
    private var sparseHelpCard: some View {
        if check.totalSpots <= 2 {
            VStack(alignment: .leading, spacing: 8) {
                Label("Nobody (or almost nobody) heard you", systemImage: "ear.trianglebadge.exclamationmark")
                    .font(.headline)
                Text("RBN and PSK Reporter were both reachable. Common causes:")
                    .font(.subheadline)
                Group {
                    bullet("The band was dead — check propagation forecasts.")
                    bullet("Antenna or feedline issue (check SWR).")
                    bullet("Wrong band CQ'd vs. what you watched.")
                    bullet("Callsign typo (yours: \(check.callsignUsed)).")
                    bullet("FT8 sessions under 15 min are sparse — PSK Reporter window granularity.")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding()
            .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private var detailsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            PropagationCheckMetadataCard(check: check)
            bandBreakdownSection
            geoBreakdownSection
            PropagationCheckTimelineChart(
                spots: blob.spots,
                startedAt: check.startedAt,
                endedAt: check.endedAt
            )
            PropagationCheckDistanceHistogram(
                spots: effectiveEntries,
                userGrid: check.userGridUsed
            )
            PropagationCheckSpotsList(enrichedSpots: enrichedSpots)
            metaSection
        }
    }

    @ViewBuilder
    private var bandBreakdownSection: some View {
        let rows = PropagationCheckStatistics.bandBreakdown(spots: effectiveEntries, userGrid: check.userGridUsed)
        VStack(alignment: .leading, spacing: 8) {
            Text("Per Band")
                .font(.headline)
            if rows.isEmpty {
                Text("No band activity captured.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(rows) { row in
                        bandRow(row)
                        Divider()
                    }
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private var geoBreakdownSection: some View {
        let buckets: [PropagationCheckStatistics.GeographicBucket] = switch geoMode {
        case .continent: PropagationCheckStatistics.continentBreakdown(spots: effectiveEntries)
        case .cqZone: PropagationCheckStatistics.cqZoneBreakdown(spots: effectiveEntries)
        }
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Geography")
                    .font(.headline)
                Spacer()
                Picker("", selection: $geoMode) {
                    Text("Continent").tag(GeoMode.continent)
                    Text("CQ Zone").tag(GeoMode.cqZone)
                }
                .pickerStyle(.segmented)
                .fixedSize()
            }
            if buckets.isEmpty {
                Text("No skimmer locations decoded.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(buckets) { bucket in
                    HStack {
                        Text(bucket.name)
                        Spacer()
                        Text("\(bucket.spotCount)")
                            .monospacedDigit()
                    }
                    .font(.subheadline)
                    .padding(.vertical, 2)
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
    }

    private var metaSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            metaRow("Callsign", check.callsignUsed)
            metaRow("Grid", check.userGridUsed)
            metaRow("Mode", check.transmitModeKind.displayName)
            metaRow("Stop reason", check.stopReasonKind.rawValue)
            if !blob.connectivityGaps.isEmpty {
                Divider()
                Text("Connectivity gaps")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                ForEach(blob.connectivityGaps.indices, id: \.self) { idx in
                    let gap = blob.connectivityGaps[idx]
                    HStack {
                        Text(gap.source.displayName)
                        Spacer()
                        Text("\(Int(gap.endedAt.timeIntervalSince(gap.startedAt))) s")
                            .monospacedDigit()
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
    }

    private func statTile(title: String, value: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title2.bold().monospacedDigit())
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func bandRow(_ row: PropagationCheckStatistics.BandBreakdownRow) -> some View {
        HStack {
            Circle()
                .fill(BandColors.color(for: row.band))
                .frame(width: 12, height: 12)
            Text(row.band)
                .font(.body.monospaced())
                .frame(width: 50, alignment: .leading)
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(row.spotCount) spots · \(row.uniqueSkimmers) RX")
                    .font(.subheadline.monospacedDigit())
                Text(
                    "\(distanceLabel(row.maxDistanceKm)) max · "
                        + "\(Int(row.medianSNRdB)) dB med · \(Int(row.peakSNRdB)) dB peak"
                )
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
    }

    private func metaRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.body.monospaced())
        }
        .font(.subheadline)
    }
}

// MARK: - Bullet helper

private func bullet(_ text: String) -> some View {
    HStack(alignment: .top, spacing: 6) {
        Text("•")
        Text(text)
    }
}

// MARK: - Formatting helpers

private func distanceLabel(_ kilometers: Double) -> String {
    if kilometers <= 0 {
        return "—"
    }
    let miles = kilometers * 0.621371
    return "\(Int(miles)) mi"
}

private func durationLabel(_ seconds: TimeInterval) -> String {
    let mins = Int(seconds) / 60
    if mins == 0 {
        return "\(Int(seconds))s"
    }
    return "\(mins) min"
}

// MARK: - PropagationCheckLegacyEnrichment

/// View-time enrichment fallback for legacy propagation artifacts saved
/// before commit e1ce3a3b, whose spots may lack a `skimmerGrid` because the
/// pre-swap re-enrichment path that used to backfill them at view time was
/// deleted. New artifacts persist enriched grids on every spot at save time
/// (via the Rust `PropagationApi`) and never need this.
private enum PropagationCheckLegacyEnrichment {
    /// Resolves the suffix-stripped base callsigns of grid-less spots via the
    /// shared Rust callbook (`QrzApi.locate`) and returns a
    /// `base callsign → grid` map. Best-effort: any failure degrades to an
    /// empty map so the view renders whatever was already resolvable.
    static func resolveMissingGrids(for spots: [PropagationSpotEntry]) async -> [String: String] {
        var seen: Set<String> = []
        var bases: [String] = []
        for spot in spots where spot.skimmerGrid == nil {
            let base = baseSkimmerCallsign(spot.skimmerCall)
            guard !base.isEmpty, !seen.contains(base) else {
                continue
            }
            seen.insert(base)
            bases.append(base)
        }
        guard !bases.isEmpty else {
            return [:]
        }

        do {
            let store = try await CwStoreProvider.shared.store()
            let qrzApi = try QrzApi.withStore(secure: KeychainSecureStore(), store: store)
            let locations = try await qrzApi.locate(callsigns: bases)
            var resolved: [String: String] = [:]
            for location in locations {
                if let grid = location.grid {
                    resolved[location.callsign.uppercased()] = grid
                }
            }
            return resolved
        } catch {
            RadioService.shared.addLog(.error, "Propagation check legacy grid enrichment failed: \(error)")
            return [:]
        }
    }

    /// Strip RBN skimmer hyphen-suffix tags so the result is the actual
    /// licensee callsign (e.g. "AK6RI-1-#" → "AK6RI").
    static func baseSkimmerCallsign(_ spotter: String) -> String {
        let upper = spotter.uppercased()
        if let hyphenIndex = upper.firstIndex(of: "-") {
            return String(upper[..<hyphenIndex])
        }
        return upper
    }
}

// MARK: - GeoMode

private enum GeoMode: String, CaseIterable, Hashable {
    case continent
    case cqZone
}

// MARK: - MapMode

private enum MapMode: String, CaseIterable, Identifiable, Hashable {
    case standard
    case azimuthal

    // MARK: Internal

    var id: String {
        rawValue
    }

    var label: String {
        switch self {
        case .standard: "Map"
        case .azimuthal: "Azimuthal"
        }
    }
}
