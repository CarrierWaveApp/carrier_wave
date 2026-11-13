import CarrierWaveCore
import CarrierWaveData
import Charts
import SwiftUI

// MARK: - OnAirSheet

/// Expanded sheet showing full conditions, DXpeditions, and contests
/// with navigation links to existing detail views.
struct OnAirSheet: View {
    // MARK: - Day Averaging

    static let dayFormatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        fmt.timeZone = TimeZone(identifier: "UTC")
        return fmt
    }()

    let tourState: TourState
    let snapshots: [EnvironmentalSnapshot]
    let solarData: HamQSLSolarData?
    let bandEstimates: [BandPropagation]
    let expeditions: [Ham365DXpedition]
    let onAirSpots: [String: [RBNSpot]]
    let contestService: ContestPollingService
    let friendSpots: [(callsign: String, spot: POTASpot)]
    let potaSpots: [POTASpot]
    let sotaSpots: [SOTASpot]
    let operatorNames: [String: String]
    let contactCounts: [String: Int]

    @Environment(\.dismiss) var dismiss

    @AppStorage("onAirShowConditions") var showConditions = true
    @AppStorage("onAirShowDXpeditions") var showDXpeditions = true
    @AppStorage("onAirShowContests") var showContests = true
    @AppStorage("onAirShowFriendSpots") var showFriendSpots = true
    @AppStorage("onAirShowPOTASpots") var showPOTASpots = true
    @AppStorage("onAirShowSOTASpots") var showSOTASpots = true
    @AppStorage("onAirBandFilter") var bandFilterRaw = ""
    @AppStorage("onAirModeFilter") var modeFilterRaw = ""
    @AppStorage("onAirSpotMaxAgeMinutes") var spotMaxAgeMinutes = 30

    var latestSolar: EnvironmentalSnapshot? {
        snapshots.last { $0.hasSolarData }
    }

    var latestWeather: EnvironmentalSnapshot? {
        snapshots.last { $0.hasWeatherData }
    }

    var onAirExpeditions: [Ham365DXpedition] {
        expeditions.filter(\.isOnAir)
    }

    var otherExpeditions: [Ham365DXpedition] {
        expeditions.filter { !$0.isOnAir && ($0.isActiveToday || !$0.activeDays.isEmpty) }
    }

    var currentDaysInMonth: Int {
        let calendar = Calendar.current
        guard let range = calendar.range(of: .day, in: .month, for: Date()) else {
            return 31
        }
        return range.count
    }

    var kIndexData: [(date: Date, value: Double)] {
        let raw = snapshots.compactMap { snap -> (key: String, val: Double)? in
            guard let kVal = snap.solarKIndex else {
                return nil
            }
            return (key: Self.dayKey(snap.timestamp), val: kVal)
        }

        var grouped: [String: [Double]] = [:]
        for point in raw {
            grouped[point.key, default: []].append(point.val)
        }

        return grouped.map { key, values in
            let avg = values.reduce(into: 0.0) { $0 += $1 } / Double(values.count)
            return (date: Self.dateFromDayKey(key), value: avg)
        }
        .sorted { $0.date < $1.date }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    OnAirActiveFiltersView(
                        bands: spotBands, modes: spotModes,
                        maxAgeMinutes: spotMaxAgeMinutes
                    )
                    if showConditions {
                        conditionsSection
                        spaceWeatherSection
                        bandConditionsSection
                    }
                    if showFriendSpots {
                        friendsOnAirSection
                    }
                    if showDXpeditions {
                        dxpeditionsSection
                    }
                    if showContests {
                        contestsSection
                    }
                    if showPOTASpots {
                        potaSpotsSection
                    }
                    if showSOTASpots {
                        sotaSpotsSection
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("On Air Now")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Conditions Section

    var conditionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Conditions", icon: "sun.max.fill", color: .orange)

            if let latest = latestSolar {
                conditionMetrics(latest)
            } else {
                noDataRow("No conditions data yet")
            }
        }
    }

    /// K-index sparkline averaged per calendar day.
    var sparklineChart: some View {
        Chart {
            ForEach(kIndexData, id: \.date) { point in
                LineMark(
                    x: .value("Date", point.date),
                    y: .value("K-Index", point.value)
                )
                .foregroundStyle(.orange.opacity(0.8))
                .interpolationMethod(.catmullRom)
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartYScale(
            domain: 0 ... max(kIndexData.map(\.value).max() ?? 5, 5)
        )
    }

    // MARK: - DXpeditions Section

    var dxpeditionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            let onAirCount = onAirExpeditions.count
            let subtitle = onAirCount > 0 ? "\(onAirCount) on air" : nil
            sectionHeader(
                "DXpeditions",
                icon: "globe.americas",
                color: .orange,
                badge: subtitle
            )

            if expeditions.isEmpty {
                noDataCard("No DXpeditions this month")
            } else {
                dxpeditionList
            }
        }
    }

    var dxpeditionList: some View {
        VStack(spacing: 0) {
            ForEach(Array(onAirExpeditions.prefix(5))) { dx in
                NavigationLink {
                    DXpeditionDetailView(
                        expedition: dx,
                        daysInMonth: currentDaysInMonth
                    )
                } label: {
                    dxRow(dx, isOnAir: true)
                }
                .buttonStyle(.plain)
            }

            ForEach(Array(otherExpeditions.prefix(5))) { dx in
                NavigationLink {
                    DXpeditionDetailView(
                        expedition: dx,
                        daysInMonth: currentDaysInMonth
                    )
                } label: {
                    dxRow(dx, isOnAir: false)
                }
                .buttonStyle(.plain)
            }

            seeAllLink("See All DXpeditions") {
                DXpeditionsView(isInNavigationContext: true)
            }
        }
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Contests Section

    // Contests, friends, band conditions, POTA/SOTA sections
    // are in OnAirSheet+Sections.swift
}
