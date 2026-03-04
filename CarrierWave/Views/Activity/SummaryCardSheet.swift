import CarrierWaveData
import CoreLocation
import SwiftData
import SwiftUI

// MARK: - SummaryCardSheet

/// Sheet for configuring and generating summary share cards
struct SummaryCardSheet: View {
    // MARK: Internal

    @Environment(\.dismiss) var dismiss
    @Environment(\.modelContext) var modelContext

    let callsign: String

    var body: some View {
        NavigationStack {
            Form {
                Section("Date Range") {
                    Picker("Period", selection: $selectedPeriod) {
                        ForEach(SummaryPeriod.allCases, id: \.self) { period in
                            Text(period.displayName).tag(period)
                        }
                    }
                    .pickerStyle(.segmented)

                    if selectedPeriod == .custom {
                        DatePicker("Start", selection: $customStartDate, displayedComponents: .date)
                        DatePicker("End", selection: $customEndDate, displayedComponents: .date)
                    }
                }

                Section("Preview") {
                    if let stats = computedStats {
                        ShareCardView(
                            content: .forSummary(summaryCardData(from: stats))
                        )
                        .scaleEffect(0.6)
                        .frame(height: 320)
                        .frame(maxWidth: .infinity)
                    } else {
                        ContentUnavailableView(
                            "No Data",
                            systemImage: "chart.bar.xaxis",
                            description: Text("No QSOs found in this period")
                        )
                        .frame(height: 200)
                    }
                }

                if computedStats != nil {
                    Section {
                        Button {
                            shareCard()
                        } label: {
                            HStack {
                                Spacer()
                                Label("Share", systemImage: "square.and.arrow.up")
                                    .fontWeight(.semibold)
                                Spacer()
                            }
                        }
                    }
                }
            }
            .navigationTitle("Share Summary")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .onChange(of: selectedPeriod) { _, _ in
                recomputeStats()
            }
            .onChange(of: customStartDate) { _, _ in
                if selectedPeriod == .custom {
                    recomputeStats()
                }
            }
            .onChange(of: customEndDate) { _, _ in
                if selectedPeriod == .custom {
                    recomputeStats()
                }
            }
            .onAppear {
                recomputeStats()
            }
            .sheet(isPresented: $showingShareSheet) {
                if let stats = computedStats {
                    SummaryShareSheetView(data: summaryCardData(from: stats))
                }
            }
        }
    }

    // MARK: Private

    @State private var selectedPeriod: SummaryPeriod = .week
    @State private var customStartDate = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
    @State private var customEndDate = Date()
    @State private var computedStats: SummaryStats?
    @State private var showingShareSheet = false

    private var dateRange: (start: Date, end: Date) {
        switch selectedPeriod {
        case .week:
            let end = Date()
            let start = Calendar.current.date(byAdding: .day, value: -7, to: end) ?? end
            return (start, end)
        case .month:
            let end = Date()
            let start = Calendar.current.date(byAdding: .month, value: -1, to: end) ?? end
            return (start, end)
        case .year:
            let end = Date()
            let start = Calendar.current.date(byAdding: .year, value: -1, to: end) ?? end
            return (start, end)
        case .custom:
            return (customStartDate, customEndDate)
        }
    }

    private var dateRangeString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        let range = dateRange
        return "\(formatter.string(from: range.start)) - \(formatter.string(from: range.end))"
    }

    private func recomputeStats() {
        let range = dateRange
        let startDate = range.start
        let endDate = range.end
        let descriptor = FetchDescriptor<QSO>(
            predicate: #Predicate { qso in
                qso.timestamp >= startDate && qso.timestamp <= endDate && !qso.isHidden
            }
        )

        do {
            let qsos = try modelContext.fetch(descriptor)

            guard !qsos.isEmpty else {
                computedStats = nil
                return
            }

            // Count unique DXCC entities
            let uniqueCountries = Set(qsos.compactMap(\.dxcc)).count

            // Find furthest distance (using grid squares)
            var maxDistance: Int?
            for qso in qsos {
                if let theirGrid = qso.theirGrid, !theirGrid.isEmpty,
                   let myGrid = qsos.first?.myGrid, !myGrid.isEmpty
                {
                    if let distance = calculateDistanceKm(from: myGrid, to: theirGrid) {
                        if maxDistance == nil || distance > maxDistance! {
                            maxDistance = distance
                        }
                    }
                }
            }

            // Calculate streak (simple daily count)
            let streakDays = calculateStreak(qsos: qsos, in: range)

            computedStats = SummaryStats(
                qsoCount: qsos.count,
                countriesWorked: uniqueCountries,
                furthestDistance: maxDistance,
                streakDays: streakDays > 1 ? streakDays : nil
            )
        } catch {
            computedStats = nil
        }
    }

    private func calculateDistanceKm(from grid1: String, to grid2: String) -> Int? {
        guard let coord1 = MaidenheadConverter.coordinate(from: grid1),
              let coord2 = MaidenheadConverter.coordinate(from: grid2)
        else {
            return nil
        }

        let location1 = CLLocation(latitude: coord1.latitude, longitude: coord1.longitude)
        let location2 = CLLocation(latitude: coord2.latitude, longitude: coord2.longitude)
        return Int(location1.distance(from: location2) / 1_000)
    }

    private func calculateStreak(qsos: [QSO], in range: (start: Date, end: Date)) -> Int {
        let calendar = Calendar.current
        var daysWithQSOs = Set<Date>()

        for qso in qsos {
            let day = calendar.startOfDay(for: qso.timestamp)
            daysWithQSOs.insert(day)
        }

        // Count consecutive days ending at range.end
        var streak = 0
        var currentDay = calendar.startOfDay(for: range.end)

        while daysWithQSOs.contains(currentDay), currentDay >= range.start {
            streak += 1
            guard let previousDay = calendar.date(byAdding: .day, value: -1, to: currentDay) else {
                break
            }
            currentDay = previousDay
        }

        return streak
    }

    private func summaryCardData(from stats: SummaryStats) -> SummaryCardData {
        SummaryCardData(
            callsign: callsign,
            title: selectedPeriod.title,
            dateRange: dateRangeString,
            qsoCount: stats.qsoCount,
            countriesWorked: stats.countriesWorked,
            furthestDistance: stats.furthestDistance,
            streakDays: stats.streakDays
        )
    }

    private func shareCard() {
        showingShareSheet = true
    }
}

// MARK: - SummaryPeriod

enum SummaryPeriod: CaseIterable {
    case week
    case month
    case year
    case custom

    // MARK: Internal

    var displayName: String {
        switch self {
        case .week: "Week"
        case .month: "Month"
        case .year: "Year"
        case .custom: "Custom"
        }
    }

    var title: String {
        switch self {
        case .week: "My Week in Radio"
        case .month: "My Month in Radio"
        case .year: "My Year in Radio"
        case .custom: "My Radio Activity"
        }
    }
}

// MARK: - SummaryStats

struct SummaryStats {
    var qsoCount: Int
    var countriesWorked: Int
    var furthestDistance: Int?
    var streakDays: Int?
}

// MARK: - SummaryShareSheetView

struct SummaryShareSheetView: UIViewControllerRepresentable {
    let data: SummaryCardData

    func makeUIViewController(context _: Context) -> UIActivityViewController {
        let image = ShareCardRenderer.renderSummary(data) ?? UIImage()

        return UIActivityViewController(
            activityItems: [image],
            applicationActivities: nil
        )
    }

    func updateUIViewController(_: UIActivityViewController, context _: Context) {}
}

// MARK: - Preview

#Preview {
    SummaryCardSheet(callsign: "W1ABC")
        .modelContainer(for: QSO.self, inMemory: true)
}
