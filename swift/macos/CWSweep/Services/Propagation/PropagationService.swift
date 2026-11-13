import CarrierWaveCore
import SwiftUI

// MARK: - PropagationService

/// View-bound service wiring HamQSL solar data, DONKI space weather events,
/// and PropagationEstimator into a single observable propagation state.
@MainActor @Observable
final class PropagationService {
    // MARK: Internal

    // Published state
    var solarData: HamQSLSolarData?
    var donkiEvents: [DONKIEvent] = []
    var bandEstimates: [BandPropagation] = []
    var bestBand: BandPropagation?
    var mufEstimateMHz: Double?
    var isLoading = false
    var lastError: String?

    func refresh() async {
        isLoading = true
        defer { isLoading = false }
        lastError = nil

        // Fetch solar data and DONKI events in parallel
        // Note: both clients are actors — calls cross isolation boundaries
        async let solarResult = hamQSL.fetchSolarData()
        async let donkiResult = donki.fetchActiveEvents()

        do {
            solarData = try await solarResult
        } catch {
            lastError = "Solar data unavailable"
        }

        donkiEvents = await donkiResult

        // Compute propagation estimates from solar data
        if let solar = solarData {
            let hour = Calendar.current.component(.hour, from: Date())
            let sfi = solar.solarFlux ?? 100
            bandEstimates = PropagationEstimator.estimate(
                sfi: sfi, kIndex: solar.kIndex, utcHour: hour
            )
            bestBand = PropagationEstimator.bestBand(
                sfi: sfi, kIndex: solar.kIndex, utcHour: hour
            )
            mufEstimateMHz = bandEstimates.compactMap(\.mufEstimateMHz).max()
        }
    }

    // MARK: Private

    private let hamQSL = HamQSLClient()
    private let donki = DONKIClient()
}
