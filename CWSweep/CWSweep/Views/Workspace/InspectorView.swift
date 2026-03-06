import CarrierWaveCore
import CarrierWaveData
import MapKit
import SwiftData
import SwiftUI

// MARK: - InspectorView

/// Inspector panel showing contextual details (callsign info, QSO edit, spot detail)
struct InspectorView: View {
    // MARK: Internal

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Inspector")
                .font(.headline)
                .padding(.horizontal)
                .padding(.vertical, 8)

            Divider()

            if let qso = selectedQSO {
                QSODetailInspector(qso: qso)
            } else if let spot = selectionState.selectedSpot {
                SpotDetailInspector(spot: spot)
            } else {
                emptyState
            }
        }
        .task(id: selectionState.selectedQSOId) {
            guard let id = selectionState.selectedQSOId else {
                selectedQSO = nil
                return
            }
            let descriptor = FetchDescriptor<QSO>(
                predicate: #Predicate<QSO> { qso in qso.id == id }
            )
            selectedQSO = try? modelContext.fetch(descriptor).first
        }
    }

    // MARK: Private

    @Environment(SelectionState.self) private var selectionState
    @Environment(\.modelContext) private var modelContext
    @State private var selectedQSO: QSO?

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "info.circle")
                .font(.system(size: 32))
                .foregroundStyle(.quaternary)
                .accessibilityHidden(true)
            Text("Select a QSO or spot to see details")
                .foregroundStyle(.secondary)
                .font(.callout)
            Text("Cmd+Opt+I to toggle")
                .foregroundStyle(.tertiary)
                .font(.caption)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - QSODetailInspector

struct QSODetailInspector: View {
    let qso: QSO

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Callsign header
                VStack(alignment: .leading, spacing: 4) {
                    Text(qso.callsign)
                        .font(.title2.bold())
                    if let name = qso.name {
                        Text(name)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal)

                QSOContactMapView(qso: qso)

                Divider()

                // QSO fields
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                ], alignment: .leading, spacing: 8) {
                    InspectorField(label: "Date", value: qso.timestamp.formatted(
                        .dateTime.month(.abbreviated).day().year()
                    ))
                    InspectorField(label: "Time", value: qso.timestamp.formatted(
                        .dateTime.hour().minute().second()
                    ))
                    InspectorField(label: "Band", value: qso.band)
                    InspectorField(label: "Mode", value: qso.mode)

                    if let freq = qso.frequency {
                        InspectorField(label: "Freq", value: String(format: "%.3f MHz", freq))
                    }

                    if let rst = qso.rstSent {
                        InspectorField(label: "RST Sent", value: rst)
                    }
                    if let rst = qso.rstReceived {
                        InspectorField(label: "RST Rcvd", value: rst)
                    }

                    if let grid = qso.theirGrid {
                        InspectorField(label: "Grid", value: grid)
                    }

                    if let park = qso.theirParkReference {
                        InspectorField(label: "Their Park", value: park)
                    }
                    if let park = qso.parkReference {
                        InspectorField(label: "My Park", value: park)
                    }

                    if let state = qso.state {
                        InspectorField(label: "State", value: state)
                    }
                }
                .padding(.horizontal)

                if let notes = qso.notes, !notes.isEmpty {
                    Divider()
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Notes")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(notes)
                            .font(.callout)
                    }
                    .padding(.horizontal)
                }
            }
            .padding(.vertical)
        }
    }
}

// MARK: - QSOContactMapView

struct QSOContactMapView: View {
    // MARK: Internal

    let qso: QSO

    var body: some View {
        if theirCoord != nil {
            VStack(spacing: 4) {
                Map(position: $mapPosition, interactionModes: [.pan, .zoom]) {
                    if let my = myCoord {
                        Annotation("My QTH", coordinate: my) {
                            Image(systemName: "house.fill")
                                .font(.caption2)
                                .foregroundStyle(.white)
                                .padding(3)
                                .background(.blue, in: Circle())
                        }
                        .annotationTitles(.hidden)
                    }

                    if let their = theirCoord {
                        Annotation(qso.callsign, coordinate: their, anchor: .bottom) {
                            MapPinMarkerView(color: rstColor)
                        }
                        .annotationTitles(.hidden)

                        if showGeodesic, let path = geodesicPath {
                            MapPolyline(coordinates: path)
                                .stroke(.white.opacity(0.5), lineWidth: 2.5)
                        }
                    }
                }
                .mapStyle(isWideSpan
                    ? .imagery(elevation: .realistic)
                    : .standard(elevation: .realistic))
                .frame(height: 150)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .padding(.horizontal)
                .onAppear {
                    mapPosition = computedCameraPosition
                    showGeodesic = true
                }
                .onChange(of: qso.id) {
                    showGeodesic = false
                    mapPosition = computedCameraPosition
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        showGeodesic = true
                    }
                }

                if let info = distanceAndBearing {
                    Text("\(Int(info.miles).formatted()) mi \u{00B7} \(Int(info.degrees))\u{00B0}")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal)
                }
            }
        }
    }

    // MARK: Private

    @AppStorage("myGrid") private var myGrid = ""
    @State private var mapPosition: MapCameraPosition = .automatic
    @State private var showGeodesic = false

    private var theirCoord: CLLocationCoordinate2D? {
        guard let grid = qso.theirGrid,
              MaidenheadConverter.isValid(grid),
              let coord = MaidenheadConverter.coordinate(from: grid)
        else {
            return nil
        }
        return CLLocationCoordinate2D(latitude: coord.latitude, longitude: coord.longitude)
    }

    private var myCoord: CLLocationCoordinate2D? {
        let grid = qso.myGrid ?? (myGrid.isEmpty ? nil : myGrid)
        guard let grid,
              MaidenheadConverter.isValid(grid),
              let coord = MaidenheadConverter.coordinate(from: grid)
        else {
            return nil
        }
        return CLLocationCoordinate2D(latitude: coord.latitude, longitude: coord.longitude)
    }

    private var isWideSpan: Bool {
        guard let their = theirCoord else {
            return false
        }
        let coords = myCoord.map { [$0, their] } ?? [their]
        let lons = coords.map(\.longitude)
        guard let minLon = lons.min(), let maxLon = lons.max() else {
            return false
        }
        let direct = maxLon - minLon
        return min(direct, 360 - direct) > 90
    }

    private var geodesicPath: [CLLocationCoordinate2D]? {
        guard let my = myCoord, let their = theirCoord else {
            return nil
        }
        return Self.computeGeodesicPath(from: my, to: their, segments: 30)
    }

    /// Fit the camera to all geodesic path points (not just endpoints) so the
    /// curved great-circle line is never clipped. Uses a globe camera for
    /// extreme distances (>90° span).
    private var computedCameraPosition: MapCameraPosition {
        guard let their = theirCoord else {
            return .automatic
        }

        // Use all geodesic points if available so the arc's curvature is included
        let allCoords: [CLLocationCoordinate2D] = if let path = geodesicPath {
            path
        } else {
            myCoord.map { [$0, their] } ?? [their]
        }

        let lats = allCoords.map(\.latitude)
        let lons = allCoords.map(\.longitude)
        guard let minLat = lats.min(), let maxLat = lats.max(),
              let minLon = lons.min(), let maxLon = lons.max()
        else {
            return .automatic
        }

        let latSpan = maxLat - minLat
        let centerLat = (minLat + maxLat) / 2

        // Dateline-aware longitude span
        let directLonSpan = maxLon - minLon
        let datelineLonSpan = 360 - directLonSpan
        let crossesDateline = datelineLonSpan < directLonSpan
        let lonSpan = crossesDateline ? datelineLonSpan : directLonSpan
        let centerLon: Double
        if crossesDateline {
            let raw = maxLon + datelineLonSpan / 2
            centerLon = raw > 180 ? raw - 360 : raw
        } else {
            centerLon = (minLon + maxLon) / 2
        }

        let maxSpan = max(latSpan, lonSpan)
        let center = CLLocationCoordinate2D(
            latitude: centerLat,
            longitude: centerLon
        )

        let padding: Double = maxSpan > 90 ? 1.5 : 1.3
        let paddedLatSpan = min(max(latSpan, 5) * padding, 180)
        let paddedLonSpan = min(max(lonSpan, 5) * padding, 360)
        return .region(MKCoordinateRegion(
            center: center,
            span: MKCoordinateSpan(
                latitudeDelta: paddedLatSpan,
                longitudeDelta: paddedLonSpan
            )
        ))
    }

    private var distanceAndBearing: (miles: Double, degrees: Double)? {
        let myGridStr = qso.myGrid ?? (myGrid.isEmpty ? nil : myGrid)
        guard let myGridStr, let theirGrid = qso.theirGrid,
              let miles = MaidenheadConverter.distanceMiles(from: myGridStr, to: theirGrid),
              let bearing = MaidenheadConverter.bearing(from: myGridStr, to: theirGrid)
        else {
            return nil
        }
        return (miles, bearing)
    }

    /// RST-based pin color matching Carrier Wave's RSTColorHelper:
    /// green (avg >= 55), yellow (avg >= 45), red (< 45)
    private var rstColor: Color {
        let avg = Self.averageRST(qso.rstSent, qso.rstReceived)
        if avg >= 55 {
            return .green
        }
        if avg >= 45 {
            return .yellow
        }
        return .red
    }

    private static func parseRST(_ rst: String?) -> Int? {
        guard let rst, !rst.isEmpty else {
            return nil
        }
        let digits = rst.filter(\.isNumber)
        guard !digits.isEmpty else {
            return nil
        }
        if digits.count >= 2 {
            return Int(String(digits.prefix(2)))
        }
        return Int(digits)! * 10
    }

    private static func averageRST(_ sent: String?, _ received: String?) -> Int {
        switch (parseRST(sent), parseRST(received)) {
        case let (sentVal?, recvVal?): (sentVal + recvVal) / 2
        case let (sentVal?, nil): sentVal
        case let (nil, recvVal?): recvVal
        case (nil, nil): 55
        }
    }

    /// Calculate intermediate points along the great circle path (matches Carrier Wave)
    private static func computeGeodesicPath(
        from: CLLocationCoordinate2D,
        to: CLLocationCoordinate2D,
        segments: Int
    ) -> [CLLocationCoordinate2D] {
        let lat1 = from.latitude * .pi / 180
        let lon1 = from.longitude * .pi / 180
        let lat2 = to.latitude * .pi / 180
        let lon2 = to.longitude * .pi / 180

        let angularDist =
            2
                * asin(
                    sqrt(
                        pow(sin((lat1 - lat2) / 2), 2) + cos(lat1) * cos(lat2)
                            * pow(sin((lon1 - lon2) / 2), 2)
                    )
                )

        guard angularDist > 0.001 else {
            return [from, to]
        }

        var points: [CLLocationCoordinate2D] = []
        points.reserveCapacity(segments + 1)

        for i in 0 ... segments {
            let fraction = Double(i) / Double(segments)

            let coeffA = sin((1 - fraction) * angularDist) / sin(angularDist)
            let coeffB = sin(fraction * angularDist) / sin(angularDist)

            let x = coeffA * cos(lat1) * cos(lon1) + coeffB * cos(lat2) * cos(lon2)
            let y = coeffA * cos(lat1) * sin(lon1) + coeffB * cos(lat2) * sin(lon2)
            let z = coeffA * sin(lat1) + coeffB * sin(lat2)

            let lat = atan2(z, sqrt(x * x + y * y)) * 180 / .pi
            let lon = atan2(y, x) * 180 / .pi

            points.append(CLLocationCoordinate2D(latitude: lat, longitude: lon))
        }

        return points
    }
}

// MARK: - MapPinMarkerView

/// Pin marker matching Carrier Wave's MapPinMarker style — colored circle with a stem
private struct MapPinMarkerView: View {
    let color: Color
    var size: CGFloat = 9

    var body: some View {
        VStack(spacing: 0) {
            Circle()
                .fill(color.opacity(0.8))
                .frame(width: size, height: size)
            Rectangle()
                .fill(color.opacity(0.7))
                .frame(width: max(1.5, size * 0.17), height: max(6, size * 0.67))
        }
    }
}

// MARK: - InspectorField

struct InspectorField: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.callout)
        }
    }
}
