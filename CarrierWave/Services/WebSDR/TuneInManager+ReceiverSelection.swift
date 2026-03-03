import CarrierWaveCore
import CoreLocation
import Foundation

// MARK: - Receiver Selection

extension TuneInManager {
    /// Select a receiver using the chosen listening strategy.
    func selectReceiver(
        for spot: TuneInSpot,
        strategy: TuneInStrategy
    ) async -> KiwiSDRReceiver? {
        switch strategy {
        case .nearStrongRBN:
            await selectReceiverNearRBN(for: spot)
        case .nearActivator:
            await selectReceiverNearActivator(for: spot)
        case .nearMyQTH:
            await selectReceiverNearMyQTH(for: spot)
        }
    }

    // MARK: - Near Strong RBN

    /// Find a receiver near the strongest RBN spotter for this activator.
    /// Falls back to the closest-available receiver if RBN lookup fails.
    private func selectReceiverNearRBN(
        for spot: TuneInSpot
    ) async -> KiwiSDRReceiver? {
        let rbn = RBNClient()
        do {
            let spots = try await rbn.spots(
                for: spot.callsign, hours: 1, limit: 20
            )
            // Sort by SNR descending — strongest signal first
            let sorted = spots.sorted { $0.snr > $1.snr }

            for rbnSpot in sorted {
                guard let grid = rbnSpot.spotterGrid,
                      let coord = MaidenheadConverter.coordinate(from: grid)
                else {
                    continue
                }
                if let receiver = await findNearbyAvailable(
                    latitude: coord.latitude,
                    longitude: coord.longitude
                ) {
                    return receiver
                }
            }
        } catch {
            // RBN lookup failed — fall through to fallback
        }

        return await selectReceiverFallback(for: spot)
    }

    // MARK: - Near Activator

    /// Find a receiver near the activator's location.
    /// Tries: park coords → summit coords → HamDB grid → fallback to nearRBN.
    private func selectReceiverNearActivator(
        for spot: TuneInSpot
    ) async -> KiwiSDRReceiver? {
        // Try park coordinates
        if let parkRef = spot.parkRef,
           let park = POTAParksCache.shared.parkSync(for: parkRef),
           let lat = park.latitude, let lon = park.longitude
        {
            if let receiver = await findNearbyAvailable(
                latitude: lat, longitude: lon
            ) {
                return receiver
            }
        }

        // Try summit coordinates
        if let summitCode = spot.summitCode,
           let summit = SOTASummitsCache.shared.lookupSummit(summitCode),
           let lat = summit.latitude, let lon = summit.longitude
        {
            if let receiver = await findNearbyAvailable(
                latitude: lat, longitude: lon
            ) {
                return receiver
            }
        }

        // Try HamDB callsign lookup for grid
        let hamDB = HamDBClient()
        do {
            if let license = try await hamDB.lookup(callsign: spot.callsign),
               let grid = license.grid,
               let coord = MaidenheadConverter.coordinate(from: grid)
            {
                if let receiver = await findNearbyAvailable(
                    latitude: coord.latitude,
                    longitude: coord.longitude
                ) {
                    return receiver
                }
            }
        } catch {
            // HamDB lookup failed — fall through
        }

        // Fall back to nearRBN strategy
        return await selectReceiverNearRBN(for: spot)
    }

    // MARK: - Near My QTH

    /// Find a receiver near the user's configured grid square.
    /// Falls back to nearRBN if no grid is configured or no receivers found.
    private func selectReceiverNearMyQTH(
        for spot: TuneInSpot
    ) async -> KiwiSDRReceiver? {
        if let grid = UserDefaults.standard.string(
            forKey: "loggerDefaultGrid"
        ),
            let coord = MaidenheadConverter.coordinate(from: grid)
        {
            if let receiver = await findNearbyAvailable(
                latitude: coord.latitude,
                longitude: coord.longitude
            ) {
                return receiver
            }
        }

        // Fall back to nearRBN strategy
        return await selectReceiverNearRBN(for: spot)
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

        // Resume the existing recording on the new receiver
        await session.resumeFromDormant(
            receiver: alternate,
            frequencyMHz: spot.frequencyMHz,
            mode: spot.mode
        )
    }

    // MARK: - Helpers

    /// Find the first available receiver near a coordinate.
    private func findNearbyAvailable(
        latitude: Double,
        longitude: Double
    ) async -> KiwiSDRReceiver? {
        let receivers = await WebSDRDirectory.shared.findNearby(
            grid: nil,
            latitude: latitude,
            longitude: longitude,
            limit: 20
        )
        return receivers.first(where: \.isAvailable)
    }

    /// Closest-available receiver using the spot's own location data.
    /// This is the original pre-strategy behavior.
    func selectReceiverFallback(
        for spot: TuneInSpot
    ) async -> KiwiSDRReceiver? {
        let receivers = await WebSDRDirectory.shared.findNearby(
            grid: spot.grid,
            latitude: spot.latitude,
            longitude: spot.longitude,
            limit: 20
        )
        return receivers.first(where: \.isAvailable)
    }
}
