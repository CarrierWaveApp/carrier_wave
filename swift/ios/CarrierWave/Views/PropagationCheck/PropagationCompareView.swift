import CarrierWaveCore
import CarrierWaveData
import CoreLocation
import MapKit
import SwiftUI

// MARK: - PropagationCompareView

/// Side-by-side and overlay comparison between two saved checks.
struct PropagationCompareView: View {
    // MARK: Internal

    let checks: [PropagationCheck]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Mode", selection: $mode) {
                    Text("Stats").tag(CompareMode.stats)
                    Text("Map").tag(CompareMode.map)
                }
                .pickerStyle(.segmented)
                .padding()

                switch mode {
                case .stats: statsLayer
                case .map: mapLayer
                }
            }
            .navigationTitle("Compare")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    // MARK: Private

    @Environment(\.dismiss) private var dismiss
    @State private var mode: CompareMode = .stats

    private var checkA: PropagationCheck? {
        checks.first
    }

    private var checkB: PropagationCheck? {
        checks.dropFirst().first
    }

    private var statsLayer: some View {
        ScrollView {
            VStack(spacing: 12) {
                if let lhs = checkA, let rhs = checkB {
                    nameRow(lhs: lhs, rhs: rhs)
                    deltaRow("Spots", lhs: lhs.totalSpots, rhs: rhs.totalSpots)
                    deltaRow("Skimmers", lhs: lhs.uniqueSkimmers, rhs: rhs.uniqueSkimmers)
                    deltaRow("Bands", lhs: lhs.bandsWithActivity.count, rhs: rhs.bandsWithActivity.count)
                    deltaRow("Max km", lhs: Int(lhs.maxDistanceKm), rhs: Int(rhs.maxDistanceKm))
                    deltaRow("Peak SNR", lhs: Int(lhs.peakSNRdB), rhs: Int(rhs.peakSNRdB))

                    if lhs.label.contains("·") || rhs.label.contains("·") {
                        Text("Tip: rename auto-named checks to make this comparison meaningful.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.top, 8)
                    }

                    Divider().padding(.vertical, 8)
                    Text("Per-band").font(.headline).frame(maxWidth: .infinity, alignment: .leading)
                    bandComparison(lhs: lhs, rhs: rhs)
                } else {
                    Text("Select exactly two checks to compare.")
                        .foregroundStyle(.secondary)
                        .padding()
                }
            }
            .padding(.horizontal)
        }
    }

    @ViewBuilder
    private var mapLayer: some View {
        let pinsA = (checkA?.decodedBlob?.spots ?? []).compactMap { ComparePin.from($0, color: .blue) }
        let pinsB = (checkB?.decodedBlob?.spots ?? []).compactMap { ComparePin.from($0, color: .orange) }
        Map(initialPosition: .region(
            MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 30, longitude: -40),
                span: MKCoordinateSpan(latitudeDelta: 160, longitudeDelta: 320)
            )
        )) {
            ForEach(pinsA) { pin in
                Annotation(pin.skimmerCall, coordinate: pin.coordinate, anchor: .center) {
                    Circle().fill(pin.color).frame(width: 8, height: 8)
                }
            }
            ForEach(pinsB) { pin in
                Annotation(pin.skimmerCall, coordinate: pin.coordinate, anchor: .center) {
                    Circle().fill(pin.color).frame(width: 8, height: 8)
                }
            }
        }
    }

    private func nameRow(lhs: PropagationCheck, rhs: PropagationCheck) -> some View {
        HStack {
            label(lhs, color: .blue)
            Spacer()
            label(rhs, color: .orange)
        }
    }

    private func label(_ check: PropagationCheck, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(check.label.isEmpty ? "Check" : check.label)
                .font(.subheadline.bold())
                .lineLimit(2)
            Text(check.startedAt, format: .dateTime.month().day().hour().minute())
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private func deltaRow(_ title: String, lhs: Int, rhs: Int) -> some View {
        let delta = rhs - lhs
        let symbol: String = delta > 0 ? "▲" : (delta < 0 ? "▼" : "•")
        let color: Color = delta > 0 ? .green : (delta < 0 ? .red : .secondary)
        HStack {
            Text(title)
                .frame(width: 90, alignment: .leading)
            Text("\(lhs)")
                .frame(maxWidth: .infinity, alignment: .leading)
                .monospacedDigit()
            Text("\(rhs)")
                .frame(maxWidth: .infinity, alignment: .leading)
                .monospacedDigit()
            HStack(spacing: 4) {
                Text(symbol)
                Text("\(abs(delta))")
                    .monospacedDigit()
            }
            .frame(width: 60, alignment: .trailing)
            .foregroundStyle(color)
            .font(.subheadline.bold())
        }
        .font(.subheadline)
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func bandComparison(lhs: PropagationCheck, rhs: PropagationCheck) -> some View {
        let bands = Array(Set(lhs.bandsWithActivity).union(rhs.bandsWithActivity)).sorted { lhs, rhs in
            let order = ["160m", "80m", "60m", "40m", "30m", "20m", "17m", "15m", "12m", "10m", "6m", "2m", "70cm"]
            return (order.firstIndex(of: lhs) ?? Int.max) < (order.firstIndex(of: rhs) ?? Int.max)
        }
        let blobLeft = lhs.decodedBlob ?? PropagationCheckBlob()
        let blobRight = rhs.decodedBlob ?? PropagationCheckBlob()
        let rowsLeft = PropagationCheckStatistics.bandBreakdown(spots: blobLeft.spots, userGrid: lhs.userGridUsed)
        let rowsRight = PropagationCheckStatistics.bandBreakdown(spots: blobRight.spots, userGrid: rhs.userGridUsed)
        let lookupLeft = Dictionary(uniqueKeysWithValues: rowsLeft.map { ($0.band, $0) })
        let lookupRight = Dictionary(uniqueKeysWithValues: rowsRight.map { ($0.band, $0) })

        VStack(spacing: 0) {
            ForEach(bands, id: \.self) { band in
                let leftSpots = lookupLeft[band]?.spotCount ?? 0
                let rightSpots = lookupRight[band]?.spotCount ?? 0
                deltaRow(band, lhs: leftSpots, rhs: rightSpots)
                Divider()
            }
        }
    }
}

// MARK: - CompareMode

private enum CompareMode: String, CaseIterable, Hashable {
    case stats
    case map
}

// MARK: - ComparePin

private struct ComparePin: Identifiable {
    let id: String
    let coordinate: CLLocationCoordinate2D
    let color: Color
    let skimmerCall: String

    static func from(_ entry: PropagationSpotEntry, color: Color) -> ComparePin? {
        guard let grid = entry.skimmerGrid,
              let coord = MaidenheadConverter.coordinate(from: grid)
        else {
            return nil
        }
        let label = color == .blue ? "A" : "B"
        return ComparePin(
            id: "\(label)-\(PropagationCheck.dedupKey(for: entry))",
            coordinate: coord,
            color: color,
            skimmerCall: entry.skimmerCall
        )
    }
}
