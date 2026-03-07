import CarrierWaveData
import CoreLocation
import Foundation

// MARK: - Receiver Selection

extension TuneInManager {
    /// Ranked list of candidate receivers for the chosen strategy.
    /// Returns available receivers in priority order (best first),
    /// filtered to within `maxReceiverDistanceKm`.
    func selectCandidateReceivers(
        for spot: TuneInSpot,
        strategy: TuneInStrategy
    ) async -> [KiwiSDRReceiver] {
        switch strategy {
        case .nearStrongRBN:
            await candidatesNearRBN(for: spot)
        case .nearActivator:
            await candidatesNearActivator(for: spot)
        case .nearMyQTH:
            await candidatesNearMyQTH(for: spot)
        }
    }

    // MARK: - Near Strong RBN

    /// Candidate receivers near the strongest RBN spotters,
    /// with fallback candidates appended.
    private func candidatesNearRBN(
        for spot: TuneInSpot
    ) async -> [KiwiSDRReceiver] {
        var seen = Set<String>()
        var candidates: [KiwiSDRReceiver] = []

        if let spots = try? await RBNClient().spots(
            for: spot.callsign, hours: 1, limit: 20
        ) {
            let sorted = spots.sorted { $0.snr > $1.snr }
            for rbnSpot in sorted {
                guard let grid = rbnSpot.spotterGrid,
                      let coord = MaidenheadConverter.coordinate(from: grid)
                else {
                    continue
                }
                for rx in await findAllNearbyAvailable(
                    latitude: coord.latitude, longitude: coord.longitude
                ) where !seen.contains(rx.id) {
                    seen.insert(rx.id)
                    candidates.append(rx)
                }
            }
        }

        for rx in await fallbackCandidates(for: spot)
            where !seen.contains(rx.id)
        {
            seen.insert(rx.id)
            candidates.append(rx)
        }

        return candidates
    }

    // MARK: - Near Activator

    /// Candidate receivers near the activator's location.
    /// Tries: park → summit → HamDB grid → falls back to RBN candidates.
    private func candidatesNearActivator(
        for spot: TuneInSpot
    ) async -> [KiwiSDRReceiver] {
        var seen = Set<String>()
        var candidates: [KiwiSDRReceiver] = []

        if let parkRef = spot.parkRef,
           let park = POTAParksCache.shared.parkSync(for: parkRef),
           let lat = park.latitude, let lon = park.longitude
        {
            for rx in await findAllNearbyAvailable(latitude: lat, longitude: lon)
                where !seen.contains(rx.id)
            {
                seen.insert(rx.id)
                candidates.append(rx)
            }
        }

        if let summitCode = spot.summitCode,
           let summit = SOTASummitsCache.shared.lookupSummit(summitCode),
           let lat = summit.latitude, let lon = summit.longitude
        {
            for rx in await findAllNearbyAvailable(latitude: lat, longitude: lon)
                where !seen.contains(rx.id)
            {
                seen.insert(rx.id)
                candidates.append(rx)
            }
        }

        if let license = try? await HamDBClient().lookup(callsign: spot.callsign),
           let grid = license.grid,
           let coord = MaidenheadConverter.coordinate(from: grid)
        {
            for rx in await findAllNearbyAvailable(
                latitude: coord.latitude, longitude: coord.longitude
            ) where !seen.contains(rx.id) {
                seen.insert(rx.id)
                candidates.append(rx)
            }
        }

        let rbnCandidates = await candidatesNearRBN(for: spot)
        for rx in rbnCandidates where !seen.contains(rx.id) {
            seen.insert(rx.id)
            candidates.append(rx)
        }

        return candidates
    }

    // MARK: - Near My QTH

    /// Candidate receivers near the user's QTH, with RBN fallback.
    private func candidatesNearMyQTH(
        for spot: TuneInSpot
    ) async -> [KiwiSDRReceiver] {
        var seen = Set<String>()
        var candidates: [KiwiSDRReceiver] = []

        if let grid = UserDefaults.standard.string(
            forKey: "loggerDefaultGrid"
        ),
            let coord = MaidenheadConverter.coordinate(from: grid)
        {
            for rx in await findAllNearbyAvailable(
                latitude: coord.latitude, longitude: coord.longitude
            ) where !seen.contains(rx.id) {
                seen.insert(rx.id)
                candidates.append(rx)
            }
        }

        for rx in await candidatesNearRBN(for: spot)
            where !seen.contains(rx.id)
        {
            seen.insert(rx.id)
            candidates.append(rx)
        }

        return candidates
    }

    // MARK: - Receiver Failover

    /// Called when all reconnect attempts to the current receiver are
    /// exhausted. Finds an alternate available receiver and switches to it.
    func switchToAlternateReceiver() async {
        guard let spot, let failedReceiver = session.receiver else {
            return
        }

        let candidates = await WebSDRDirectory.shared.findNearby(
            grid: spot.grid,
            latitude: spot.latitude,
            longitude: spot.longitude,
            limit: 20
        )
        let alternate = candidates.first {
            $0.isAvailable && $0.id != failedReceiver.id
        }

        guard let alternate else {
            return
        }

        await session.resumeFromDormant(
            receiver: alternate,
            frequencyMHz: spot.frequencyMHz,
            mode: spot.mode
        )
    }

    // MARK: - Helpers

    /// All available receivers near a coordinate, sorted by distance.
    private func findAllNearbyAvailable(
        latitude: Double,
        longitude: Double
    ) async -> [KiwiSDRReceiver] {
        let receivers = await WebSDRDirectory.shared.findNearby(
            grid: nil,
            latitude: latitude,
            longitude: longitude,
            limit: 20
        )
        return receivers.filter(\.isAvailable)
    }

    /// Fallback candidates using the spot's own location data.
    private func fallbackCandidates(
        for spot: TuneInSpot
    ) async -> [KiwiSDRReceiver] {
        let receivers = await WebSDRDirectory.shared.findNearby(
            grid: spot.grid,
            latitude: spot.latitude,
            longitude: spot.longitude,
            limit: 20
        )
        return receivers.filter(\.isAvailable)
    }
}
