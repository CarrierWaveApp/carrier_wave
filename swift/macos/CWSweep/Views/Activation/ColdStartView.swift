import CarrierWaveCore
import CarrierWaveData
import SwiftData
import SwiftUI

// MARK: - ColdStartView

/// Top-level three-column cold-start layout for starting a new POTA activation.
/// Left: past activations, Center: propagation + session setup, Right: band map + suggestion.
struct ColdStartView: View {
    // MARK: Internal

    let radioManager: RadioManager
    var onSessionStarted: ((LoggingSession) -> Void)?

    @Environment(\.modelContext) var modelContext
    @Environment(SpotAggregator.self) var spotAggregator
    @State var propagationService = PropagationService()

    // Park state
    @State var parkReference = ""
    @State var parkName = ""
    @State var parkGrid: String?

    // Band/frequency selection
    @State var selectedBand: String?
    @State var selectedMode = "CW"

    // Callsign state
    @AppStorage("myCallsign") var myCallsign = ""
    @State var callsignPrefix = ""
    @State var selectedSuffix = "none"
    @State var customSuffix = ""
    @State var additionalOperators: [String] = []

    // Equipment state (auto-filled from @AppStorage)
    @AppStorage("lastActivationSuffix") var lastSuffix = "none"
    @AppStorage("lastActivationPower") var lastPower = ""
    @AppStorage("lastActivationGrid") var lastGrid = ""
    @AppStorage("lastActivationAntenna") var lastAntenna = ""
    @AppStorage("lastActivationKey") var lastKey = ""
    @AppStorage("lastActivationMic") var lastMic = ""

    @State var selectedAntenna: String?
    @State var selectedKey: String?
    @State var selectedMic: String?
    @State var powerText = ""
    @State var myGrid = ""
    @State var attendeesText = ""
    @State var sessionNotes = ""
    @State var isRove = false

    var currentSuggestion: FrequencySuggestion? {
        let band = selectedBand ?? propagationService.bestBand?.band ?? "20m"
        let recentFreqs = filteredSpotMarkers.map(\.frequencyMHz)
        return FrequencySuggestionEngine.suggest(
            band: band,
            mode: selectedMode,
            recentSpotFrequencies: recentFreqs
        )
    }

    var filteredSpotMarkers: [SpotMarker] {
        let targetBand = selectedBand ?? propagationService.bestBand?.band ?? "20m"
        let cutoff = Date().addingTimeInterval(-30 * 60)
        return spotAggregator.spots.compactMap { enriched in
            let spot = enriched.spot
            guard spot.timestamp > cutoff else {
                return nil
            }
            let freqMHz = spot.frequencyKHz / 1_000
            guard BandUtilities.deriveBand(from: spot.frequencyKHz) == targetBand else {
                return nil
            }
            let age = Int(-spot.timestamp.timeIntervalSinceNow / 60)
            return SpotMarker(
                frequencyMHz: freqMHz,
                callsign: spot.callsign,
                ageMinutes: min(age, 30)
            )
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            setupRow
                .zIndex(1)
            Divider()
            HSplitView {
                pastActivationsColumn
                centerColumn
                rightColumn
            }
        }
        .task {
            restoreDefaults()
            await propagationService.refresh()
        }
        .onAppear { vimEngine.isPaletteActive = true }
        .onDisappear { vimEngine.isPaletteActive = false }
    }

    // MARK: Private

    @Environment(VimEngine.self) private var vimEngine

    private var pastActivationsColumn: some View {
        PastActivationsListView(onParkSelected: { ref in
            parkReference = ref
        })
        .frame(minWidth: 240, idealWidth: 280, maxWidth: 320)
    }

    private var centerColumn: some View {
        ScrollView {
            VStack(spacing: 0) {
                PropagationPanelView(
                    propagationService: propagationService,
                    selectedBand: $selectedBand
                )
                Divider()
                sessionSetupSection
            }
        }
    }

    private var rightColumn: some View {
        VStack(spacing: 0) {
            FrequencySuggestionView(suggestion: currentSuggestion)
                .padding(8)
            VerticalBandMapView(
                band: selectedBand ?? propagationService.bestBand?.band ?? "20m",
                spots: filteredSpotMarkers,
                suggestion: currentSuggestion
            )
        }
        .frame(minWidth: 200, idealWidth: 220, maxWidth: 260)
    }

    private func restoreDefaults() {
        selectedSuffix = lastSuffix
        powerText = lastPower
        myGrid = lastGrid
        if !lastAntenna.isEmpty {
            selectedAntenna = lastAntenna
        }
        if !lastKey.isEmpty {
            selectedKey = lastKey
        }
        if !lastMic.isEmpty {
            selectedMic = lastMic
        }
    }
}
