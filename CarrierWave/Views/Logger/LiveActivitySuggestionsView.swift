import CarrierWaveData
import SwiftUI

// MARK: - BandSuggestion

struct BandSuggestion: Identifiable {
    let band: String
    let staticFreqMHz: Double
    let stations: [ActiveStation]
    let recommendedFreqMHz: Double?
    let reason: String

    var id: String {
        band
    }

    var hasLiveData: Bool {
        !stations.isEmpty
    }

    var primaryFreqMHz: Double {
        recommendedFreqMHz ?? staticFreqMHz
    }
}

// MARK: - FrequencyBandView

/// Unified frequency suggestions: static band frequencies enriched with live spot data.
struct FrequencyBandView: View {
    // MARK: Internal

    let selectedMode: String

    @Binding var frequency: String
    @Binding var detailBand: BandSuggestion?

    var body: some View {
        ForEach(suggestions) { suggestion in
            bandRow(suggestion)
        }
        // Hidden anchor ensures .task fires even when suggestions is empty
        Color.clear.frame(height: 0)
            .task {
                suggestions = buildSuggestions()
                await loadAllSpots()
            }
            .onChange(of: selectedMode) {
                suggestions = buildSuggestions()
                Task { await loadAllSpots() }
            }
    }

    // MARK: Private

    private static let minClearanceMHz = 0.002 // 2 kHz
    private static let maxSpotAgeSec: TimeInterval = 12 * 60

    private static let sortedBands = [
        "160m", "80m", "40m", "30m", "20m", "17m", "15m", "12m", "10m",
        "6m", "2m", "70cm",
    ]

    @AppStorage("userLicenseClass") private var licenseClassRaw: String = LicenseClass.extra
        .rawValue

    @State private var allStations: [ActiveStation] = []
    @State private var suggestions: [BandSuggestion] = []

    private var userLicenseClass: LicenseClass {
        LicenseClass(rawValue: licenseClassRaw) ?? .extra
    }

    private var modeFilter: ModeFilter {
        ModeFilter.from(modeName: selectedMode)
    }

    // MARK: - Data

    private var filteredStations: [ActiveStation] {
        allStations.filter { station in
            guard modeFilter.matches(station.mode) else {
                return false
            }
            let violation = BandPlanService.validate(
                frequencyMHz: station.frequencyMHz,
                mode: station.mode,
                license: userLicenseClass
            )
            if let violation {
                switch violation.type {
                case .outOfBand,
                     .noPrivileges,
                     .wrongMode:
                    return false
                case .unusualFrequency:
                    return true
                }
            }
            return true
        }
    }

    // MARK: - Views

    private func bandRow(_ suggestion: BandSuggestion) -> some View {
        let freqStr = FrequencyFormatter.format(suggestion.primaryFreqMHz)
        let isSelected = frequency == freqStr

        return Button {
            if suggestion.hasLiveData {
                detailBand = suggestion
            } else {
                frequency = freqStr
            }
        } label: {
            HStack(spacing: 10) {
                // Band badge
                Text(suggestion.band)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.blue.opacity(0.2))
                    .clipShape(Capsule())

                // Frequency and detail
                VStack(alignment: .leading, spacing: 2) {
                    Text(FrequencyFormatter.formatWithUnit(suggestion.primaryFreqMHz))
                        .font(.subheadline.monospaced().weight(.medium))

                    if suggestion.hasLiveData {
                        HStack(spacing: 4) {
                            if suggestion.recommendedFreqMHz != nil {
                                Image(systemName: "star.fill")
                                    .font(.caption2)
                                    .foregroundStyle(.orange)
                                Text(suggestion.reason)
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                                Text("·")
                                    .foregroundStyle(.tertiary)
                            }
                            Text("\(suggestion.stations.count) active")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Spacer()

                if suggestion.hasLiveData {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(isSelected ? Color.accentColor.opacity(0.1) : nil)
    }

    private func buildSuggestions() -> [BandSuggestion] {
        let staticFreqs = LoggingSession.suggestedFrequencies(for: selectedMode)
        let grouped = Dictionary(grouping: filteredStations, by: \.band)

        return Self.sortedBands.compactMap { band -> BandSuggestion? in
            guard let staticFreq = staticFreqs[band] else {
                return nil
            }
            let stations = (grouped[band] ?? [])
                .sorted { $0.frequencyMHz < $1.frequencyMHz }
            let (recFreq, reason) = recommendedFrequency(
                in: band, avoiding: stations
            )
            return BandSuggestion(
                band: band,
                staticFreqMHz: staticFreq,
                stations: stations,
                recommendedFreqMHz: recFreq,
                reason: reason
            )
        }
    }

    // MARK: - Recommendation

    private func recommendedFrequency(
        in band: String,
        avoiding stations: [ActiveStation]
    ) -> (Double?, String) {
        let recent = stations.filter {
            Date().timeIntervalSince($0.timestamp) <= Self.maxSpotAgeSec
        }
        let occupied = recent.map(\.frequencyMHz).sorted()
        guard !occupied.isEmpty else {
            return (nil, "")
        }

        let privileged = BandPlanService.privilegedSegments(for: userLicenseClass)
            .filter { $0.band == band }
        let widePrivileged = privileged.filter { $0.minimumLicense != .extra }
        let preferWide = !widePrivileged.isEmpty

        let allZones = BandPlan.usageZones(forBand: band, mode: selectedMode)
        let primary = allZones.filter { $0.isPrimaryZone(for: selectedMode) }
        let secondary = allZones.filter { !$0.isPrimaryZone(for: selectedMode) }

        let attempts: [([UsageZone], [BandSegment])] = [
            (primary, preferWide ? widePrivileged : privileged),
            (primary, privileged),
            (secondary, preferWide ? widePrivileged : privileged),
            (secondary, privileged),
        ]

        for (zones, segs) in attempts where !zones.isEmpty && !segs.isEmpty {
            let result = nestledFrequency(
                zones: zones, privileged: segs, occupied: occupied
            )
            if result.0 != nil {
                return result
            }
        }
        return (nil, "")
    }

    private func nestledFrequency(
        zones: [UsageZone],
        privileged: [BandSegment],
        occupied: [Double]
    ) -> (Double?, String) {
        var candidates: [(freq: Double, clearance: Double)] = []

        for zone in zones {
            let startKHz = Int(zone.startMHz * 1_000)
            let endKHz = Int(zone.endMHz * 1_000)
            var kHz = startKHz
            while kHz < endKHz {
                let mhz = Double(kHz) / 1_000.0
                let licensed = privileged.contains { $0.contains(frequencyMHz: mhz) }
                if licensed {
                    let clearance = occupied.map { abs(mhz - $0) }.min() ?? .infinity
                    if clearance >= Self.minClearanceMHz {
                        candidates.append((mhz, clearance))
                    }
                }
                kHz += 1
            }
        }

        guard !candidates.isEmpty else {
            return (nil, "No clear frequency found")
        }

        let center = occupied.reduce(0.0, +) / Double(occupied.count)
        let best = candidates.min { abs($0.freq - center) < abs($1.freq - center) }!
        return (best.freq, "\(Int(best.clearance * 1_000)) kHz clear")
    }

    // MARK: - Data Loading

    private func loadAllSpots() async {
        async let potaTask = fetchPOTAStations()
        async let rbnTask = fetchRBNStations()
        let (pota, rbn) = await (potaTask, rbnTask)

        var seen: Set<String> = []
        var merged: [ActiveStation] = []
        for station in pota {
            let key = "\(station.callsign)-\(station.band)"
            if seen.insert(key).inserted {
                merged.append(station)
            }
        }
        for station in rbn {
            let key = "\(station.callsign)-\(station.band)"
            if seen.insert(key).inserted {
                merged.append(station)
            }
        }
        allStations = merged
        suggestions = buildSuggestions()
    }

    private func fetchPOTAStations() async -> [ActiveStation] {
        do {
            let client = POTAClient(authService: POTAAuthService())
            return try await client.fetchActiveSpots()
                .compactMap { ActiveStation.fromPOTA($0) }
        } catch { return [] }
    }

    private func fetchRBNStations() async -> [ActiveStation] {
        do {
            let client = RBNClient()
            return try await client.spots(
                mode: selectedMode,
                since: Date().addingTimeInterval(-Self.maxSpotAgeSec),
                limit: 200
            ).map { ActiveStation.fromRBN($0) }
        } catch { return [] }
    }
}

// MARK: - BandActivitySheet

/// Detail sheet showing all active stations on a band with recommended frequency
struct BandActivitySheet: View, Identifiable {
    // MARK: Internal

    let suggestion: BandSuggestion

    @Binding var frequency: String

    var id: String {
        suggestion.id
    }

    var body: some View {
        NavigationStack {
            List {
                recommendedSection
                stationsSection
            }
            .navigationTitle("\(suggestion.band) — \(suggestion.stations.count) Active")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .landscapeAdaptiveDetents(portrait: [.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: Private

    @Environment(\.dismiss) private var dismiss

    @ViewBuilder
    private var recommendedSection: some View {
        if let recFreq = suggestion.recommendedFreqMHz {
            Section {
                Button {
                    frequency = FrequencyFormatter.format(recFreq)
                    dismiss()
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "star.fill")
                            .font(.title3)
                            .foregroundStyle(.orange)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Suggested Frequency")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Text(FrequencyFormatter.formatWithUnit(recFreq))
                                .font(.title3.monospaced().weight(.semibold))
                            Text(suggestion.reason)
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }

                        Spacer()

                        Text("Use")
                            .font(.subheadline.weight(.medium))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(Color.accentColor)
                            .foregroundStyle(.white)
                            .clipShape(Capsule())
                    }
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
            } header: {
                Text("Recommended")
            } footer: {
                Text(
                    "Frequency nestled among active stations with enough clearance to avoid interference"
                )
            }
        }
    }

    private var stationsSection: some View {
        Section("Active Stations") {
            ForEach(suggestion.stations) { station in
                Button {
                    frequency = FrequencyFormatter.format(station.frequencyMHz)
                    dismiss()
                } label: {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(station.ageColor)
                            .frame(width: 8, height: 8)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(station.callsign)
                                .font(.subheadline.monospaced().weight(.medium))
                            Text(station.sourceLabel)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        VStack(alignment: .trailing, spacing: 2) {
                            Text(FrequencyFormatter.formatWithUnit(station.frequencyMHz))
                                .font(.subheadline.monospaced())
                            Text(station.timeAgo)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 2)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}
