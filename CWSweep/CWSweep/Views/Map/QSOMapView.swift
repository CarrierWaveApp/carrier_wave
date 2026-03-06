import CarrierWaveCore
import CarrierWaveData
import MapKit
import SwiftData
import SwiftUI

// MARK: - QSOMapView

/// Map view plotting QSO locations from Maidenhead grid squares
struct QSOMapView: View {
    // MARK: Internal

    var body: some View {
        ZStack(alignment: .topLeading) {
            mapContent

            // Top-left: header + date filter
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("QSO Map")
                        .font(.headline)
                    Text("\(plottableQSOs.count) plotted")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Picker("Period", selection: $dateFilter) {
                    ForEach(DateFilter.allCases) { filter in
                        Text(filter.label).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 280)
            }
            .padding(12)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
            .padding()

            // Bottom-right: band legend
            VStack(alignment: .leading, spacing: 4) {
                Text("Bands")
                    .font(.caption.bold())
                ForEach(legendBands, id: \.band) { item in
                    HStack(spacing: 6) {
                        Circle()
                            .fill(item.color)
                            .frame(width: 8, height: 8)
                        Text(item.band)
                            .font(.caption2)
                    }
                }
            }
            .padding(8)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            .padding()
        }
        .task { await loadQSOs() }
        .onChange(of: dateFilter) { _, _ in
            Task { await loadQSOs() }
        }
    }

    // MARK: Private

    // MARK: - Band Colors

    private static let bandColors: [String: Color] = [
        "160m": .purple,
        "80m": .indigo,
        "60m": Color(red: 0.3, green: 0.3, blue: 0.7),
        "40m": .blue,
        "30m": .teal,
        "20m": .green,
        "17m": .mint,
        "15m": .yellow,
        "12m": .orange,
        "10m": .red,
        "6m": .pink,
        "2m": Color(red: 0.8, green: 0.4, blue: 0.8),
    ]

    @Environment(\.modelContext) private var modelContext
    @AppStorage("myGrid") private var myGrid = ""
    @State private var qsos: [QSO] = []
    @State private var dateFilter: DateFilter = .all
    @State private var selectedQSO: QSO?

    // MARK: - Data

    private var plottableQSOs: [QSO] {
        qsos.filter { $0.theirGrid != nil && MaidenheadConverter.isValid($0.theirGrid!) }
    }

    private var userCoordinate: CLLocationCoordinate2D? {
        guard !myGrid.isEmpty,
              let coord = MaidenheadConverter.coordinate(from: myGrid)
        else {
            return nil
        }
        return CLLocationCoordinate2D(latitude: coord.latitude, longitude: coord.longitude)
    }

    private var legendBands: [(band: String, color: Color)] {
        let usedBands = Set(plottableQSOs.map(\.band))
        return BandUtilities.bandOrder
            .filter { usedBands.contains($0) }
            .compactMap { band in
                guard let color = Self.bandColors[band] else {
                    return nil
                }
                return (band: band, color: color)
            }
    }

    // MARK: - Map Content

    private var mapContent: some View {
        Map(selection: $selectedQSO) {
            // User QTH marker
            if let coord = userCoordinate {
                Annotation("My QTH", coordinate: coord) {
                    Image(systemName: "house.fill")
                        .font(.caption)
                        .foregroundStyle(.white)
                        .padding(4)
                        .background(.blue, in: Circle())
                }
                .annotationTitles(.hidden)
            }

            // QSO markers
            ForEach(plottableQSOs) { qso in
                if let coord = coordinate(for: qso) {
                    Annotation(qso.callsign, coordinate: coord) {
                        Circle()
                            .fill(bandColor(for: qso.band))
                            .frame(width: 10, height: 10)
                            .overlay(
                                Circle().stroke(.white, lineWidth: 1)
                            )
                    }
                    .annotationTitles(.hidden)
                    .tag(qso)
                }
            }
        }
        .mapStyle(.standard(elevation: .realistic))
        .popover(item: $selectedQSO) { qso in
            qsoPopover(qso)
        }
    }

    // MARK: - QSO Popover

    private func qsoPopover(_ qso: QSO) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(qso.callsign)
                .font(.headline)
            if let name = qso.name {
                Text(name)
                    .foregroundStyle(.secondary)
            }

            Divider()

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Band").font(.caption2).foregroundStyle(.secondary)
                    Text(qso.band).font(.caption)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Mode").font(.caption2).foregroundStyle(.secondary)
                    Text(qso.mode).font(.caption)
                }
                if let freq = qso.frequency {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Freq").font(.caption2).foregroundStyle(.secondary)
                        Text(String(format: "%.3f", freq)).font(.caption.monospacedDigit())
                    }
                }
            }

            if let grid = qso.theirGrid {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Grid").font(.caption2).foregroundStyle(.secondary)
                        Text(grid).font(.caption)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Time").font(.caption2).foregroundStyle(.secondary)
                        Text(qso.timestamp.formatted(.dateTime.month(.abbreviated).day().hour().minute()))
                            .font(.caption)
                    }
                }
            }
        }
        .padding()
        .frame(minWidth: 200)
    }

    private func coordinate(for qso: QSO) -> CLLocationCoordinate2D? {
        guard let grid = qso.theirGrid,
              let coord = MaidenheadConverter.coordinate(from: grid)
        else {
            return nil
        }
        return CLLocationCoordinate2D(latitude: coord.latitude, longitude: coord.longitude)
    }

    private func loadQSOs() async {
        let cutoff = dateFilter.cutoffDate
        var descriptor = if let cutoff {
            FetchDescriptor<QSO>(
                predicate: #Predicate<QSO> { qso in
                    !qso.isHidden && !qso.callsign.isEmpty && qso.timestamp >= cutoff
                },
                sortBy: [SortDescriptor(\QSO.timestamp, order: .reverse)]
            )
        } else {
            FetchDescriptor<QSO>(
                predicate: #Predicate<QSO> { qso in
                    !qso.isHidden && !qso.callsign.isEmpty
                },
                sortBy: [SortDescriptor(\QSO.timestamp, order: .reverse)]
            )
        }
        descriptor.fetchLimit = 2_000
        qsos = (try? modelContext.fetch(descriptor)) ?? []
    }

    private func bandColor(for band: String) -> Color {
        Self.bandColors[band] ?? .gray
    }
}

// MARK: - DateFilter

private enum DateFilter: String, CaseIterable, Identifiable {
    case today = "Today"
    case week = "7 Days"
    case month = "30 Days"
    case all = "All"

    // MARK: Internal

    var id: String {
        rawValue
    }

    var label: String {
        rawValue
    }

    var cutoffDate: Date? {
        let calendar = Calendar.current
        switch self {
        case .today: return calendar.startOfDay(for: Date())
        case .week: return calendar.date(byAdding: .day, value: -7, to: Date())
        case .month: return calendar.date(byAdding: .day, value: -30, to: Date())
        case .all: return nil
        }
    }
}
