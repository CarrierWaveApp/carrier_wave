import CoreLocation
import MapKit
import SwiftUI

// MARK: - MutualProfilePlane

/// Cross-section plane through station A, station B, and the geocenter.
/// World positions project into polar coordinates in this plane: angle 0 at
/// station A, angle `gamma` at station B; the out-of-plane component is
/// dropped (a profile view, not a 3D render).
nonisolated struct MutualProfilePlane {
    // MARK: Lifecycle

    init(stationA: CLLocationCoordinate2D, stationB: CLLocationCoordinate2D) {
        let unitA = Self.unit(latitude: stationA.latitude, longitude: stationA.longitude)
        let unitB = Self.unit(latitude: stationB.latitude, longitude: stationB.longitude)
        axisA = unitA
        let dot = max(-1, min(1, unitA.x * unitB.x + unitA.y * unitB.y + unitA.z * unitB.z))
        gamma = acos(dot)
        let rejected = SIMD3(
            unitB.x - dot * unitA.x,
            unitB.y - dot * unitA.y,
            unitB.z - dot * unitA.z
        )
        let length = max(sqrt(rejected.x * rejected.x + rejected.y * rejected.y + rejected.z * rejected.z), 1e-9)
        axisB = SIMD3(rejected.x / length, rejected.y / length, rejected.z / length)
    }

    // MARK: Internal

    static let earthRadiusKm = 6_371.0

    /// Central angle between the stations (radians).
    let gamma: Double

    /// In-plane polar coordinates for a world position.
    func planePoint(latitude: Double, longitude: Double, altitudeKm: Double) -> (theta: Double, radiusKm: Double) {
        let dir = Self.unit(latitude: latitude, longitude: longitude)
        let xComp = dir.x * axisA.x + dir.y * axisA.y + dir.z * axisA.z
        let yComp = dir.x * axisB.x + dir.y * axisB.y + dir.z * axisB.z
        let inPlane = sqrt(xComp * xComp + yComp * yComp)
        let radius = (Self.earthRadiusKm + altitudeKm) * inPlane
        return (atan2(yComp, xComp), radius)
    }

    // MARK: Private

    private let axisA: SIMD3<Double>
    private let axisB: SIMD3<Double>

    private static func unit(latitude: Double, longitude: Double) -> SIMD3<Double> {
        let lat = latitude * .pi / 180
        let lon = longitude * .pi / 180
        return SIMD3(cos(lat) * cos(lon), cos(lat) * sin(lon), sin(lat))
    }
}

// MARK: - MutualPassProfileView

/// Profile view of one mutual pass: Earth in cross-section with both
/// stations on the surface, the satellite's path colored by who can see it
/// (green = both, orange = one, dim = neither), an animated satellite with
/// sight lines to each station, and its surface coverage arc.
struct MutualPassProfileView: View {
    // MARK: Internal

    let model: SatelliteTrackerModel
    let pass: MutualPass
    let stationAGrid: String
    let stationB: ResolvedStation

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                summaryCard
                profileCard
                MutualPassTimesTable(
                    pass: pass,
                    myLabel: myLabel,
                    theirLabel: stationB.label,
                    theirTimeZone: theirTimeZone
                )
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(pass.name)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            samples = await model.mutualProfileSamples(for: pass, other: stationB.coordinate)
            await resolveTheirTimeZone()
        }
    }

    // MARK: Private

    /// One animation loop across the whole pass.
    private static let loopSeconds = 12.0

    @State private var samples = [MutualPassSample]()
    @State private var theirTimeZone: TimeZone?

    /// The operator is identified by callsign, not grid.
    private var myLabel: String {
        CallsignAliasService.shared.getCurrentCallsign() ?? stationAGrid
    }

    private var maxAltitudeKm: Double {
        samples.map(\.altitudeKm).max() ?? 0
    }

    private var plane: MutualProfilePlane {
        MutualProfilePlane(
            stationA: model.observerCoordinate ?? stationB.coordinate,
            stationB: stationB.coordinate
        )
    }

    private var timeRange: String {
        let start = pass.start.formatted(.dateTime.weekday(.abbreviated).hour().minute())
        let end = pass.end.formatted(date: .omitted, time: .shortened)
        return "\(start) – \(end)"
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(timeRange)
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                Spacer()
                Text("\(max(Int((pass.duration / 60).rounded()), 1)) min together")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 10) {
                Text("\(myLabel) \(stationAGrid)")
                Text(String(format: "peak %.0f°", pass.peakElevationADeg))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(stationB.label) \(stationB.grid)")
                Text(String(format: "peak %.0f°", pass.peakElevationBDeg))
                    .foregroundStyle(.secondary)
            }
            .font(.caption.monospaced())
            Text(String(format: "Stations %.0f km apart", plane.gamma * MutualProfilePlane.earthRadiusKm))
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private var profileCard: some View {
        if samples.count > 1 {
            TimelineView(.animation(minimumInterval: 1.0 / 30)) { timeline in
                let index = currentIndex(at: timeline.date)
                VStack(spacing: 8) {
                    MutualPassProfileCanvas(
                        samples: samples,
                        plane: plane,
                        currentIndex: index,
                        labelA: myLabel,
                        labelB: stationB.label
                    )
                    .frame(height: 280)
                    readout(samples[index])
                    legend
                    if maxAltitudeKm > 3_000 {
                        Text("High orbit — altitude scale compressed")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(12)
                .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 12))
            }
        } else {
            ProgressView("Sampling pass…")
                .frame(maxWidth: .infinity, minHeight: 280)
                .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private var legend: some View {
        HStack(spacing: 14) {
            legendDot(.green, "both see it")
            legendDot(.orange, "one station")
            legendDot(.secondary, "neither")
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }

    private func readout(_ sample: MutualPassSample) -> some View {
        HStack(spacing: 12) {
            Text(sample.date, format: .dateTime.hour().minute().second())
                .monospacedDigit()
            Spacer()
            elevationLabel(myLabel, sample.elevationADeg)
            elevationLabel(stationB.label, sample.elevationBDeg)
        }
        .font(.caption.monospaced())
    }

    private func elevationLabel(_ station: String, _ elevation: Double) -> some View {
        Text(String(format: "%@ %+.0f°", station, elevation))
            .foregroundStyle(elevation > 0 ? Color.green : Color.secondary)
    }

    private func legendDot(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(text)
        }
    }

    /// Runs off the main actor: the geocoding request types aren't Sendable,
    /// so build and consume them in one nonisolated hop.
    @concurrent
    nonisolated private static func geocodedTimeZone(
        latitude: Double,
        longitude: Double
    ) async -> TimeZone? {
        let location = CLLocation(latitude: latitude, longitude: longitude)
        guard let request = MKReverseGeocodingRequest(location: location) else {
            return nil
        }
        let items = try? await request.mapItems
        return items?.first?.timeZone
    }

    /// The other station's time zone: reverse-geocoded from their grid,
    /// falling back to a longitude-based solar estimate offline.
    private func resolveTheirTimeZone() async {
        if let zone = await Self.geocodedTimeZone(
            latitude: stationB.latitude, longitude: stationB.longitude
        ) {
            theirTimeZone = zone
        } else {
            let offsetHours = Int((stationB.longitude / 15).rounded())
            theirTimeZone = TimeZone(secondsFromGMT: offsetHours * 3_600)
        }
    }

    private func currentIndex(at date: Date) -> Int {
        let progress = date.timeIntervalSinceReferenceDate
            .truncatingRemainder(dividingBy: Self.loopSeconds) / Self.loopSeconds
        return min(Int(progress * Double(samples.count)), samples.count - 1)
    }
}

// MARK: - MutualPassTimesTable

/// The mutual window's key instants — rise together, best, set together —
/// shown in Zulu and in EACH station's own local time (theirs is
/// reverse-geocoded from their grid).
struct MutualPassTimesTable: View {
    // MARK: Internal

    let pass: MutualPass
    let myLabel: String
    let theirLabel: String
    let theirTimeZone: TimeZone?

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 6) {
            GridRow {
                Text("")
                Text("Zulu")
                Text(zoneHeader(myLabel, zone: .current))
                Text(zoneHeader(theirLabel, zone: theirTimeZone))
            }
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            ForEach(events, id: \.label) { event in
                GridRow {
                    Text(event.label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(zulu(event.date))
                    Text(local(event.date, zone: .current))
                    Text(theirTimeZone.map { local(event.date, zone: $0) } ?? "—")
                }
                .font(.caption.monospaced())
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: Private

    private var events: [(label: String, date: Date)] {
        [("Both rise", pass.start), ("Best", pass.peakDate), ("Both set", pass.end)]
    }

    private func zoneHeader(_ label: String, zone: TimeZone?) -> String {
        guard let zone, let abbreviation = zone.abbreviation(for: pass.start) else {
            return label
        }
        return "\(label) \(abbreviation)"
    }

    private func zulu(_ date: Date) -> String {
        var style = Date.FormatStyle.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)
        style.timeZone = .gmt
        return date.formatted(style) + "z"
    }

    private func local(_ date: Date, zone: TimeZone) -> String {
        var style = Date.FormatStyle.dateTime.hour().minute()
        style.timeZone = zone
        return date.formatted(style)
    }
}
