// Components for the TOTA section in SessionDetailView:
//   - TOTAScoreLedger: four-tier breakdown with confidence labels
//   - TOTAPathMap: track polyline + start/end markers + GPX export button
//   - TOTAT3CandidatesList: callsign + tile + +N points entries

import CarrierWaveCore
import CarrierWaveData
import MapKit
import SwiftUI

// MARK: - TOTAScoreLedger

struct TOTAScoreLedger: View {
    // MARK: Internal

    let session: LoggingSession
    let qsos: [QSO]

    var body: some View {
        let inputs = TOTAEnrichmentService.makeScoringInputs(for: session, qsos: qsos)
        let result = TOTAScoringEngine.score(inputs)
        VStack(alignment: .leading, spacing: 8) {
            if session.totaCategory == .standard,
               (session.activationDistanceMiles ?? 0) <= 0,
               !qsos.isEmpty
            {
                zeroDistanceBanner
            }
            confirmedTier(result.confirmed)
            if result.estimatedT3Boost > 0 {
                tierLine(
                    label: "Estimated (spots)",
                    value: result.estimatedT3Boost,
                    color: .blue
                )
            }
            if result.assertedFirstEver > 0 {
                tierLine(
                    label: "Asserted: first activation of tile ever",
                    value: result.assertedFirstEver,
                    color: .orange
                )
            }
            if result.pendingMaxPoints > 0 {
                pendingTierLine(max: result.pendingMaxPoints, tileCount: max(inputs.tileCount, 1))
            }
            Divider()
            HStack {
                if session.totaOfficialPoints != nil {
                    Text("Official")
                } else {
                    Text("Estimated total")
                }
                Spacer()
                if let official = session.totaOfficialPoints {
                    Text(String(format: "%.1f pts", official))
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(.green)
                } else {
                    Text(String(format: "%.1f pts", result.total))
                        .font(.headline.monospacedDigit())
                }
            }
            if session.totaOfficialPoints != nil {
                Text("Server is authoritative; in-app inputs are locked.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                Text("Pre-upload estimate — server may add T3 + first-in-quarter bonuses.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }

    // MARK: Private

    private enum LedgerSign { case neutral, plus }

    /// Standard category requires non-zero distance to score. When the operator
    /// hasn't entered or recorded a distance, the entire base term is zero,
    /// percentage bonuses fall to 0, and the headline reads 0 pts. This banner
    /// surfaces the cause so the score isn't a silent mystery.
    private var zeroDistanceBanner: some View {
        Label(
            "Distance is 0 — TOTA Standard requires a non-zero distance. "
                + "Enter activation distance or record a track to score.",
            systemImage: "ruler"
        )
        .font(.caption)
        .foregroundStyle(.orange)
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func confirmedTier(_ tier: TOTAScoringResult.ConfirmedTier) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text("Confirmed")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(String(format: "%.1f", tier.subtotal))
                    .font(.subheadline.monospacedDigit().weight(.semibold))
            }
            if tier.base > 0 {
                ledgerLine(
                    label: "\(formatted(tier.effectiveQSOs)) QSOs × "
                        + "\(formatted(tier.distanceMiles)) mi",
                    value: tier.base
                )
            }
            if tier.qrpMultiplierApplied {
                ledgerLine(label: "QRP ×2", value: tier.qsoSubtotal - tier.base, sign: .plus)
            }
            if tier.winterBonus > 0 {
                ledgerLine(label: "Winter +20%", value: tier.winterBonus, sign: .plus)
            }
            if tier.ruckBonus > 0 {
                ledgerLine(label: "Ruck", value: tier.ruckBonus, sign: .plus)
            }
            if tier.elevationBonus > 0 {
                ledgerLine(label: "Elevation", value: tier.elevationBonus, sign: .plus)
            }
            if tier.petsBonus > 0 {
                ledgerLine(label: "Pets +15%", value: tier.petsBonus, sign: .plus)
            }
            if tier.kidsBonus > 0 {
                ledgerLine(label: "Kids +20%", value: tier.kidsBonus, sign: .plus)
            }
            if tier.winlinkFlat > 0 {
                ledgerLine(label: "Winlink +5", value: tier.winlinkFlat, sign: .plus)
            }
            if tier.aprsFlat > 0 {
                ledgerLine(label: "APRS +5", value: tier.aprsFlat, sign: .plus)
            }
            if tier.varacFlat > 0 {
                ledgerLine(label: "VarAC +5", value: tier.varacFlat, sign: .plus)
            }
        }
    }

    private func tierLine(label: String, value: Double, color: Color) -> some View {
        HStack {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(color)
            Spacer()
            Text(String(format: "+%.1f", value))
                .font(.subheadline.monospacedDigit().weight(.semibold))
                .foregroundStyle(color)
        }
    }

    private func pendingTierLine(max: Double, tileCount: Int) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Pending (server-confirmed)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.gray)
                Text("First-activation-of-grid-in-quarter, eligible × \(tileCount) tile(s).")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("up to +\(Int(max))")
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.gray)
        }
    }

    private func ledgerLine(label: String, value: Double, sign: LedgerSign = .neutral) -> some View {
        HStack {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Spacer()
            Text(formattedSigned(value, sign: sign))
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }

    private func formatted(_ value: Double) -> String {
        if value == value.rounded() {
            return String(format: "%.0f", value)
        }
        return String(format: "%.2f", value)
    }

    private func formattedSigned(_ value: Double, sign: LedgerSign) -> String {
        let prefix = (sign == .plus) ? "+" : ""
        return prefix + String(format: "%.2f", value)
    }
}

// MARK: - TOTAPathMap

struct TOTAPathMap: View {
    // MARK: Internal

    let session: LoggingSession

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            mapView
            HStack {
                Text(pathSummary)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                exportButton
            }
        }
        .sheet(isPresented: $showShareSheet) {
            if let gpxText {
                ShareSheet(activityItems: [gpxText])
            }
        }
    }

    // MARK: Private

    @State private var showShareSheet = false
    @State private var gpxText: String?

    private var trackCoords: [CLLocationCoordinate2D] {
        session.trackPoints.map {
            CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
        }
    }

    private var pathSummary: String {
        let count = session.trackPoints.count
        let miles = session.activationDistanceMiles ?? 0
        if count > 0 {
            return "\(count) GPS points · \(String(format: "%.2f", miles)) mi"
        }
        return "Manual entry: \(String(format: "%.2f", miles)) mi"
    }

    private var region: MKCoordinateRegion? {
        if !trackCoords.isEmpty {
            return Self.region(enclosing: trackCoords)
        }
        if let lat = session.activationLatitude, let lon = session.activationLongitude {
            return MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                latitudinalMeters: 4_000,
                longitudinalMeters: 4_000
            )
        }
        return nil
    }

    @ViewBuilder
    private var mapView: some View {
        if let region {
            Map(initialPosition: .region(region)) {
                ForEach(session.tilesActivated, id: \.self) { tile in
                    if let bounds = MaidenheadConverter.tileBounds(for: tile) {
                        MapPolygon(coordinates: tilePolygon(bounds: bounds))
                            .stroke(Color.purple, lineWidth: 1.5)
                            .foregroundStyle(Color.purple.opacity(0.10))
                    }
                }
                if !trackCoords.isEmpty {
                    MapPolyline(coordinates: trackCoords)
                        .stroke(Color.blue, lineWidth: 2.5)
                    if let first = trackCoords.first {
                        Marker("Start", systemImage: "play.fill", coordinate: first)
                            .tint(.green)
                    }
                    if let last = trackCoords.last, trackCoords.count > 1 {
                        Marker("End", systemImage: "stop.fill", coordinate: last)
                            .tint(.red)
                    }
                }
            }
            .allowsHitTesting(false)
            .frame(height: 180)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.tertiarySystemFill))
                Label("No track or activation coordinate", systemImage: "map")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(height: 100)
        }
    }

    private var exportButton: some View {
        Button {
            gpxText = GPXExporter.encode(
                points: session.trackPoints,
                trackName: session.tilesActivated.joined(separator: ", ")
            )
            if gpxText != nil {
                showShareSheet = true
            }
        } label: {
            Label("Share GPX", systemImage: "square.and.arrow.up")
                .font(.caption)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .disabled(session.trackPoints.isEmpty)
    }

    private static func region(
        enclosing coords: [CLLocationCoordinate2D]
    ) -> MKCoordinateRegion {
        guard !coords.isEmpty else {
            return MKCoordinateRegion()
        }
        let lats = coords.map(\.latitude)
        let lons = coords.map(\.longitude)
        guard let minLat = lats.min(), let maxLat = lats.max(),
              let minLon = lons.min(), let maxLon = lons.max()
        else {
            return MKCoordinateRegion()
        }
        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2
        )
        let span = MKCoordinateSpan(
            latitudeDelta: max((maxLat - minLat) * 1.4, 0.005),
            longitudeDelta: max((maxLon - minLon) * 1.4, 0.005)
        )
        return MKCoordinateRegion(center: center, span: span)
    }

    private func tilePolygon(
        bounds: (sw: CLLocationCoordinate2D, ne: CLLocationCoordinate2D)
    ) -> [CLLocationCoordinate2D] {
        [
            CLLocationCoordinate2D(latitude: bounds.sw.latitude, longitude: bounds.sw.longitude),
            CLLocationCoordinate2D(latitude: bounds.sw.latitude, longitude: bounds.ne.longitude),
            CLLocationCoordinate2D(latitude: bounds.ne.latitude, longitude: bounds.ne.longitude),
            CLLocationCoordinate2D(latitude: bounds.ne.latitude, longitude: bounds.sw.longitude),
        ]
    }
}

// MARK: - TOTAT3CandidatesList

struct TOTAT3CandidatesList: View {
    let candidates: [T3Candidate]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Tile-to-Tile candidates")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            ForEach(candidates) { candidate in
                HStack {
                    Text(candidate.callsign)
                        .font(.caption.monospaced())
                    Text(candidate.theirTile)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("+2")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.blue)
                }
            }
            Text("Server confirms T3 on upload by matching submissions.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}
