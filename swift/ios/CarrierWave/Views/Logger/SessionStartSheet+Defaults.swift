// `saveDefaults` and the equipment-binding switch hoisted out so the main
// `SessionStartSheet.swift` stays under SwiftLint's 500-line file cap.

import CarrierWaveData
import CoreLocation
import SwiftData
import SwiftUI

/// Search radius for the park prefill, matching the "Nearby" suggestions.
private let prefillMaxDistanceKm: Double = 16

/// How many recent sessions to scan for park-frequency ranking. Sessions are
/// lightweight and bounded (unlike QSOs), but cap the fetch anyway.
private let prefillHistoryLimit = 400

extension SessionStartSheet {
    /// Prepopulate the park field with the best nearby candidate: the park
    /// activated most often (from session history) among those within range,
    /// falling back to the closest. Never overwrites user input, a saved
    /// default park, or a map/template pre-fill — it only fills an empty
    /// field or replaces its own earlier suggestion (e.g. when the GPS fix
    /// lands after a prefill from the home-QTH default grid).
    func prefillParkIfNeeded() {
        guard operationType == .activation,
              selectedPrograms.contains("pota")
        else {
            return
        }
        let current = parkReference.trimmingCharacters(in: .whitespaces)
        guard current.isEmpty || current == autoFilledPark else {
            return
        }
        let grid = myGrid.isEmpty ? defaultGrid : myGrid
        guard let coord = MaidenheadConverter.coordinate(from: grid) else {
            return
        }
        let nearby = POTAParksCache.shared.nearbyParks(
            latitude: coord.latitude,
            longitude: coord.longitude,
            limit: 10,
            maxDistanceKm: prefillMaxDistanceKm
        )
        guard !nearby.isEmpty else {
            return
        }

        let counts = pastParkActivationCounts()
        let best = nearby.min { lhs, rhs in
            let lhsCount = counts[lhs.park.reference.uppercased()] ?? 0
            let rhsCount = counts[rhs.park.reference.uppercased()] ?? 0
            if lhsCount != rhsCount {
                return lhsCount > rhsCount
            }
            return lhs.distanceKm < rhs.distanceKm
        }
        guard let best, best.park.reference != current else {
            return
        }
        parkReference = best.park.reference
        autoFilledPark = best.park.reference
    }

    /// Times each park was activated, from recent session history. Handles
    /// comma-separated multi-park references ("US-1234,US-5678").
    private func pastParkActivationCounts() -> [String: Int] {
        var descriptor = FetchDescriptor<LoggingSession>(
            predicate: #Predicate { $0.parkReference != nil },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        descriptor.fetchLimit = prefillHistoryLimit
        guard let sessions = try? modelContext.fetch(descriptor) else {
            return [:]
        }
        return sessions.reduce(into: [String: Int]()) { counts, session in
            guard let refs = session.parkReference else {
                return
            }
            for ref in refs.split(separator: ",") {
                let key = ref.trimmingCharacters(in: .whitespaces).uppercased()
                guard !key.isEmpty else {
                    continue
                }
                counts[key, default: 0] += 1
            }
        }
    }
}

extension SessionStartSheet {
    func saveDefaults() {
        defaultMode = selectedMode
        defaultPower = powerText
        defaultRadio = selectedRadio ?? ""
        defaultAntenna = selectedAntenna ?? ""
        defaultKey = selectedKey ?? ""
        defaultMic = selectedMic ?? ""
        if !myGrid.isEmpty {
            defaultGrid = myGrid.uppercased()
        }
        // Save programs as JSON array
        let sorted = selectedPrograms.sorted()
        if let data = try? JSONEncoder().encode(sorted) {
            defaultPrograms = String(data: data, encoding: .utf8) ?? ""
        }
        if selectedPrograms.contains("pota") {
            defaultParkReference = parkReference.uppercased()
        } else {
            defaultParkReference = ""
        }

        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
            showSavedConfirmation = true
        }
    }
}
