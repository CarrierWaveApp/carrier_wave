import CarrierWaveData
import SwiftData
import SwiftUI

// MARK: - Frequency Auto-Suggestion

/// How many recent sessions to scan when ranking bands by activation
/// frequency. Sessions are lightweight and bounded; cap the fetch anyway.
private let bandHistoryLimit = 400

/// Fallback band preference when the operator has no matching history,
/// ordered by general HF openness. Also breaks ties between bands with
/// equal activation counts.
private let fallbackBandOrder = [
    "20m", "40m", "30m", "17m", "15m", "10m", "80m", "12m", "6m", "160m",
]

// MARK: - FrequencyPickOutcome

/// How the frequency was chosen, for the explanatory note.
private enum FrequencyPickOutcome {
    /// A free frequency nestled among live spots; payload is the clearance
    /// reason (e.g. "3 kHz clear").
    case open(String)
    /// No live activity on the band — fell back to the calling frequency.
    case quiet
    /// Live spots present but no clear gap; payload is the station count.
    case congested(Int)
    /// Some spot sources hadn't answered by the wizard's deadline; picked
    /// from what had arrived. Payload is the clearance reason when a gap was
    /// found, `nil` when the calling frequency stands.
    case partial(String?)
}

extension SessionStartSheet {
    /// Auto-pick the operator's most-activated band — constrained to the
    /// bands the selected radio can actually work — then set the frequency
    /// to a *free* spot on that band, nestled among live POTA / SOTA / RBN
    /// activity with enough clearance to avoid interference. Falls back to
    /// the band's calling frequency when nothing is on-air. Records a short
    /// note explaining the choice.
    ///
    /// The calling frequency goes in *immediately* so the field is usable the
    /// moment the sheet opens; the live spot fetch then has a few seconds
    /// (`ActiveSpotsLoader.wizardDeadlineSec`) to upgrade it before the
    /// wizard settles for whatever sources have answered.
    ///
    /// Never clobbers a frequency the operator typed, a band pill they
    /// tapped, or a template pre-fill: it only fills an empty field or
    /// replaces its own earlier suggestion. Re-checks that guard after the
    /// async spot fetch in case the operator typed while it was in flight.
    func refreshSuggestedFrequency() async {
        guard canPlaceSuggestion() else {
            return
        }
        let capable = radioCapableBands()
        let counts = bandActivationCounts(within: capable)
        guard let band = chooseBand(counts: counts, capable: capable) else {
            frequencySuggestionNote = nil
            return
        }
        let fromHistory = (counts[band] ?? 0) > 0
        let requestMode = selectedMode
        let staticFreq = LoggingSession.suggestedFrequencies(for: requestMode)[band]

        // Fill the field *now* with the mode's calling frequency so the
        // operator has something usable (and editable) the instant the sheet
        // opens. The live pick below upgrades it if the band is busy.
        if let staticFreq {
            place(staticFreq)
            frequencySuggestionNote = suggestionNote(band: band, fromHistory: fromHistory, outcome: .quiet)
        }

        // Look for a free frequency among live spots on the chosen band, but
        // wait only briefly: the sources' own timeouts run 15–30 s and a
        // slow RBN proxy must never hold up "start activation".
        frequencySuggestionLoading = true
        defer { frequencySuggestionLoading = false }

        let planner = FreeFrequencyPlanner(mode: requestMode, license: userLicenseClass)
        let loaded = await ActiveSpotsLoader.load(
            mode: requestMode,
            within: ActiveSpotsLoader.wizardDeadlineSec
        )
        let onBand = loaded.stations.filter { $0.band == band }

        // The await above yielded — bail if the mode changed under us (a newer
        // refresh owns the result) or the operator claimed the field.
        guard selectedMode == requestMode, canPlaceSuggestion() else {
            return
        }
        // The scope shows the whole on-air picture for the band (every source
        // and mode); the planner still nestles only among mode-relevant,
        // in-plan stations.
        scopeSpots = onBand.map(ScopeSpot.init(station:))
        let stations = planner.relevantStations(onBand)
        let (liveFreq, liveReason) = planner.recommend(band: band, stations: stations)
        guard let freq = liveFreq ?? staticFreq else {
            frequencySuggestionNote = nil
            return
        }
        let outcome: FrequencyPickOutcome = if !loaded.complete {
            .partial(liveFreq == nil ? nil : liveReason)
        } else if liveFreq != nil {
            .open(liveReason)
        } else if stations.isEmpty {
            .quiet
        } else {
            .congested(stations.count)
        }
        place(freq)
        frequencySuggestionNote = suggestionNote(band: band, fromHistory: fromHistory, outcome: outcome)
    }

    /// Write `freq` into the field as *our* suggestion, so the
    /// `onChange(of: frequency)` guard doesn't read it as an operator edit.
    private func place(_ freq: Double) {
        let formatted = FrequencyFormatter.format(freq)
        autoFilledFrequency = formatted
        frequency = formatted
    }

    /// True while the wizard still owns the frequency field — it's empty or
    /// holds our own earlier suggestion, and the operator hasn't overridden.
    private func canPlaceSuggestion() -> Bool {
        !frequencyOverridden && (frequency.isEmpty || frequency == autoFilledFrequency)
    }

    /// Operator's license class, read straight from defaults (no `@AppStorage`
    /// property needed on the wizard). Gates which segments count as clear.
    var userLicenseClass: LicenseClass {
        let raw = UserDefaults.standard.string(forKey: "userLicenseClass")
            ?? LicenseClass.extra.rawValue
        return LicenseClass(rawValue: raw) ?? .extra
    }

    /// "Change" action: drop the suggestion, clear the field for manual
    /// entry, and open the band suggestions list.
    func clearSuggestedFrequency() {
        frequencyOverridden = true
        frequencySuggestionNote = nil
        frequency = ""
        autoFilledFrequency = nil
        showBandSuggestions = true
    }

    // MARK: - Band selection

    /// Bands the selected radio can transmit on, or `nil` when no radio is
    /// chosen or its capability list is empty (treat as "any band").
    func radioCapableBands() -> Set<String>? {
        guard let item = resolveSelectedRadioItem() else {
            return nil
        }
        let bands = item.bands
        return bands.isEmpty ? nil : Set(bands)
    }

    private func resolveSelectedRadioItem() -> EquipmentItem? {
        if let id = selectedRadioItemID {
            var descriptor = FetchDescriptor<EquipmentItem>(
                predicate: #Predicate { $0.id == id }
            )
            descriptor.fetchLimit = 1
            if let match = try? modelContext.fetch(descriptor).first {
                return match
            }
        }
        guard let name = selectedRadio, !name.isEmpty else {
            return nil
        }
        let radioRaw = EquipmentCategory.radio.rawValue
        var descriptor = FetchDescriptor<EquipmentItem>(
            predicate: #Predicate { $0.categoryRawValue == radioRaw && !$0.isRetired }
        )
        descriptor.fetchLimit = 200
        let items = (try? modelContext.fetch(descriptor)) ?? []
        return items.first { $0.displayName == name }
    }

    /// Times each band was activated, from recent session history, dropping
    /// bands the selected radio can't work.
    private func bandActivationCounts(within capable: Set<String>?) -> [String: Int] {
        var descriptor = FetchDescriptor<LoggingSession>(
            predicate: #Predicate { $0.frequency != nil },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        descriptor.fetchLimit = bandHistoryLimit
        guard let sessions = try? modelContext.fetch(descriptor) else {
            return [:]
        }
        return sessions.reduce(into: [String: Int]()) { counts, session in
            guard let freq = session.frequency else {
                return
            }
            let band = LoggingSession.bandForFrequency(freq)
            guard band != "Unknown" else {
                return
            }
            if let capable, !capable.contains(band) {
                return
            }
            counts[band, default: 0] += 1
        }
    }

    /// Most-activated band, tie-broken by `fallbackBandOrder`. With no
    /// history, returns the first capable fallback band (or the plain
    /// fallback when the radio works any band).
    private func chooseBand(counts: [String: Int], capable: Set<String>?) -> String? {
        // Highest activation count wins; ties break toward the more open band.
        let best = counts.max { lhs, rhs in
            lhs.value == rhs.value
                ? fallbackIndex(lhs.key) > fallbackIndex(rhs.key)
                : lhs.value < rhs.value
        }
        if let best {
            return best.key
        }
        if let capable {
            return fallbackBandOrder.first(where: capable.contains) ?? capable.min()
        }
        return fallbackBandOrder.first
    }

    private func fallbackIndex(_ band: String) -> Int {
        fallbackBandOrder.firstIndex(of: band) ?? fallbackBandOrder.count
    }

    // MARK: - Note

    private func suggestionNote(band: String, fromHistory: Bool, outcome: FrequencyPickOutcome) -> String {
        let radioName = selectedRadio?.trimmingCharacters(in: .whitespaces) ?? ""
        let bandClause: String = if fromHistory {
            radioName.isEmpty
                ? "\(band) is your most-activated band"
                : "\(band) is your most-activated band on \(radioName)"
        } else {
            radioName.isEmpty
                ? "Starting on \(band)"
                : "Starting on \(band), a good default for \(radioName)"
        }
        let freqClause = switch outcome {
        case let .open(reason):
            "found an open frequency (\(reason))"
        case .quiet:
            "no live activity yet — set to the \(frequencyModeLabel)"
        case let .congested(count):
            "\(count) station\(count == 1 ? "" : "s") active, no clear gap — set to the \(frequencyModeLabel)"
        case let .partial(reason?):
            "found an open frequency (\(reason)); some spot sources were slow to answer"
        case .partial(nil):
            "spot sources were slow to answer — set to the \(frequencyModeLabel)"
        }
        return "\(bandClause) — \(freqClause)."
    }

    private var frequencyModeLabel: String {
        switch selectedMode.uppercased() {
        case "CW": "CW calling frequency"
        case "SSB",
             "USB",
             "LSB": "SSB calling frequency"
        case "FT8": "FT8 frequency"
        case "FT4": "FT4 frequency"
        case "RTTY": "RTTY frequency"
        default: "calling frequency"
        }
    }

    // MARK: - Callout view

    /// While the spot fetch runs: a spinner describing what it's doing.
    /// Afterwards: a one-line explanation of the auto-picked frequency plus a
    /// "Change" button. Shown beneath the frequency field.
    @ViewBuilder
    var frequencySuggestionCallout: some View {
        if frequencySuggestionLoading, !frequencyOverridden {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("Checking live POTA, SOTA & RBN spots for an open frequency…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(.vertical, 2)
        } else if let note = frequencySuggestionNote, !frequencyOverridden {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "wand.and.stars")
                    .font(.caption)
                    .foregroundStyle(.purple)
                    .accessibilityHidden(true)
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Button("Change") {
                    clearSuggestedFrequency()
                }
                .font(.caption.weight(.semibold))
                .buttonStyle(.plain)
                .foregroundStyle(.tint)
            }
            .padding(.vertical, 2)
        }
    }
}
