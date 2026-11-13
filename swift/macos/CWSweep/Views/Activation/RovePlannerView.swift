import CarrierWaveCore
import MapKit
import SwiftUI

// MARK: - RoveStopEntry

/// A planned rove stop
struct RoveStopEntry: Identifiable, Equatable {
    let id = UUID()
    var reference: String
    var name: String
    var grid: String?
    var latitude: Double?
    var longitude: Double?
}

// MARK: - Stop Number Colors

private let stopColors: [Color] = [
    .green, .blue, Color(nsColor: .systemOrange), .purple,
    .red, .teal, Color(nsColor: .systemIndigo), .pink,
]

private func stopColor(for index: Int) -> Color {
    stopColors[index % stopColors.count]
}

// MARK: - RovePlannerView

/// Map-based rove stop planner with ordered stop list and route visualization.
struct RovePlannerView: View {
    // MARK: Internal

    @Binding var isRove: Bool
    @Binding var stops: [RoveStopEntry]

    var primaryParkReference: String
    var primaryParkName: String
    var primaryParkGrid: String?

    var body: some View {
        VStack(spacing: 0) {
            toggleRow
            Divider()
            ScrollView {
                VStack(spacing: 0) {
                    mapSection
                    if isRove {
                        Divider()
                        stopListSection
                    }
                }
            }
        }
    }

    // MARK: Private

    @State private var addStopReference = ""
    @State private var mapCameraPosition: MapCameraPosition = .automatic

    @MapContentBuilder
    private var singleParkMapContent: some MapContent {
        if let grid = primaryParkGrid,
           let coord = MaidenheadConverter.coordinate(from: grid)
        {
            Annotation(primaryParkReference, coordinate: CLLocationCoordinate2D(
                latitude: coord.latitude, longitude: coord.longitude
            )) {
                stopNumberCircle(number: 1, color: .green)
            }
        }
    }

    @MapContentBuilder
    private var roveMapContent: some MapContent {
        routePolyline
        stopAnnotations
    }

    @MapContentBuilder
    private var routePolyline: some MapContent {
        let coords = stops.compactMap { stop -> CLLocationCoordinate2D? in
            guard let lat = stop.latitude, let lon = stop.longitude else {
                if let grid = stop.grid,
                   let coord = MaidenheadConverter.coordinate(from: grid)
                {
                    return CLLocationCoordinate2D(latitude: coord.latitude, longitude: coord.longitude)
                }
                return nil
            }
            return CLLocationCoordinate2D(latitude: lat, longitude: lon)
        }
        if coords.count >= 2 {
            MapPolyline(coordinates: coords)
                .stroke(Color.accentColor.opacity(0.7), style: StrokeStyle(
                    lineWidth: 2,
                    dash: [6, 4]
                ))
        }
    }

    @MapContentBuilder
    private var stopAnnotations: some MapContent {
        ForEach(Array(stops.enumerated()), id: \.element.id) { index, stop in
            if let clCoord = stopCoordinate(stop) {
                Annotation(stop.reference, coordinate: clCoord) {
                    stopNumberCircle(number: index + 1, color: stopColor(for: index))
                }
            }
        }
    }

    // MARK: - Toggle Row

    private var toggleRow: some View {
        HStack {
            Toggle("This is a rove", isOn: $isRove)
                .toggleStyle(.switch)
                .onChange(of: isRove) { _, newValue in
                    handleRoveToggle(enabled: newValue)
                }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Map Section

    private var mapSection: some View {
        Map(position: $mapCameraPosition) {
            if isRove {
                roveMapContent
            } else {
                singleParkMapContent
            }
        }
        .frame(minHeight: 220)
        .onChange(of: stops) { _, _ in
            updateMapCamera()
        }
        .onChange(of: isRove) { _, _ in
            updateMapCamera()
        }
        .task {
            updateMapCamera()
        }
    }

    // MARK: - Stop Number Circle

    private func stopNumberCircle(number: Int, color: Color) -> some View {
        ZStack {
            Circle()
                .fill(color)
                .frame(width: 26, height: 26)
                .shadow(radius: 2)
            Text("\(number)")
                .font(.caption.bold())
                .foregroundStyle(.white)
        }
    }

    // MARK: - Map Helpers

    private func stopCoordinate(_ stop: RoveStopEntry) -> CLLocationCoordinate2D? {
        if let lat = stop.latitude, let lon = stop.longitude {
            return CLLocationCoordinate2D(latitude: lat, longitude: lon)
        }
        if let grid = stop.grid,
           let coord = MaidenheadConverter.coordinate(from: grid)
        {
            return CLLocationCoordinate2D(latitude: coord.latitude, longitude: coord.longitude)
        }
        return nil
    }

    private func updateMapCamera() {
        if isRove {
            let coords = stops.compactMap { stopCoordinate($0) }
            if coords.isEmpty {
                mapCameraPosition = .automatic
            } else {
                mapCameraPosition = .automatic
            }
        } else {
            if let grid = primaryParkGrid,
               let coord = MaidenheadConverter.coordinate(from: grid)
            {
                let center = CLLocationCoordinate2D(latitude: coord.latitude, longitude: coord.longitude)
                mapCameraPosition = .region(MKCoordinateRegion(
                    center: center,
                    span: MKCoordinateSpan(latitudeDelta: 0.5, longitudeDelta: 0.5)
                ))
            } else {
                mapCameraPosition = .automatic
            }
        }
    }

    // MARK: - Rove Toggle

    private func handleRoveToggle(enabled: Bool) {
        if enabled, stops.isEmpty {
            let primary = RoveStopEntry(
                reference: primaryParkReference,
                name: primaryParkName,
                grid: primaryParkGrid,
                latitude: nil,
                longitude: nil
            )
            stops = [primary]
        }
    }
}

// MARK: - RovePlannerView + StopList

extension RovePlannerView {
    // MARK: - Stop List Section

    var stopListSection: some View {
        VStack(spacing: 0) {
            stopListRows
            Divider()
            addStopRow
            Divider()
            summaryFooter
        }
    }

    private var stopListRows: some View {
        List {
            ForEach(Array(stops.enumerated()), id: \.element.id) { index, stop in
                stopRow(stop: stop, index: index)
                    .listRowInsets(EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8))
            }
            .onMove { indices, destination in
                stops.move(fromOffsets: indices, toOffset: destination)
            }
        }
        .listStyle(.plain)
        .frame(minHeight: 80, maxHeight: 200)
    }

    private func stopRow(stop: RoveStopEntry, index: Int) -> some View {
        HStack(spacing: 8) {
            stopNumberCircle(number: index + 1, color: stopColor(for: index))

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(stop.reference)
                        .font(.body.monospaced())
                        .foregroundStyle(.primary)
                    if let grid = stop.grid {
                        Text(grid)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                }
                Text(stop.name)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if let dist = distanceFromPrevious(at: index) {
                Text(UnitFormatter.distanceFromMeters(dist * 1_609.344))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            if index > 0 {
                Button {
                    removeStop(at: index)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .help("Remove stop")
            }
        }
    }

    // MARK: - Add Stop Row

    var addStopRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "plus.circle")
                .foregroundStyle(.secondary)
                .imageScale(.small)
                .frame(width: 26)

            ParkSearchField(
                selectedReference: $addStopReference,
                onParkSelected: { ref, name, grid in
                    appendStop(reference: ref, name: name, grid: grid)
                }
            )
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }

    // MARK: - Summary Footer

    var summaryFooter: some View {
        HStack {
            Text(summaryText)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text("Drag to reorder")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private var summaryText: String {
        let count = stops.count
        let total = totalDistanceMiles()
        let stopWord = count == 1 ? "stop" : "stops"
        if total > 0 {
            let dist = UnitFormatter.distanceFromMeters(total * 1_609.344)
            return "\(count) \(stopWord) · ~\(dist) total"
        }
        return "\(count) \(stopWord)"
    }

    // MARK: - Distance Helpers

    private func distanceFromPrevious(at index: Int) -> Double? {
        guard index > 0 else {
            return nil
        }
        let prev = stops[index - 1]
        let curr = stops[index]
        return gridDistance(from: prev, to: curr)
    }

    private func gridDistance(from prev: RoveStopEntry, to curr: RoveStopEntry) -> Double? {
        guard let fromGrid = prev.grid, let toGrid = curr.grid else {
            return nil
        }
        return MaidenheadConverter.distanceMiles(from: fromGrid, to: toGrid)
    }

    private func totalDistanceMiles() -> Double {
        guard stops.count >= 2 else {
            return 0
        }
        return stops.indices.dropFirst().reduce(into: 0.0) { total, idx in
            if let dist = gridDistance(from: stops[idx - 1], to: stops[idx]) {
                total += dist
            }
        }
    }

    // MARK: - Mutation Helpers

    private func appendStop(reference: String, name: String, grid: String?) {
        let entry = RoveStopEntry(
            reference: reference,
            name: name,
            grid: grid,
            latitude: nil,
            longitude: nil
        )
        stops.append(entry)
        addStopReference = ""
    }

    private func removeStop(at index: Int) {
        guard index < stops.count else {
            return
        }
        stops.remove(at: index)
    }
}
