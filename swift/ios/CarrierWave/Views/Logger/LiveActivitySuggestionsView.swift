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
    var onFrequencyPicked: () -> Void = {}

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

    private var planner: FreeFrequencyPlanner {
        FreeFrequencyPlanner(mode: selectedMode, license: userLicenseClass)
    }

    // MARK: - Data

    private var filteredStations: [ActiveStation] {
        planner.relevantStations(allStations)
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
                onFrequencyPicked()
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
        let freePlanner = planner

        return Self.sortedBands.compactMap { band -> BandSuggestion? in
            guard let staticFreq = staticFreqs[band] else {
                return nil
            }
            let stations = (grouped[band] ?? [])
                .sorted { $0.frequencyMHz < $1.frequencyMHz }
            let (recFreq, reason) = freePlanner.recommend(band: band, stations: stations)
            return BandSuggestion(
                band: band,
                staticFreqMHz: staticFreq,
                stations: stations,
                recommendedFreqMHz: recFreq,
                reason: reason
            )
        }
    }

    // MARK: - Data Loading

    private func loadAllSpots() async {
        allStations = await ActiveSpotsLoader.load(mode: selectedMode)
        suggestions = buildSuggestions()
    }
}

// MARK: - BandActivitySheet

/// Detail sheet showing all active stations on a band with recommended frequency
struct BandActivitySheet: View, Identifiable {
    // MARK: Internal

    let suggestion: BandSuggestion
    var onFrequencyPicked: () -> Void = {}

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
                    onFrequencyPicked()
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
                    onFrequencyPicked()
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
