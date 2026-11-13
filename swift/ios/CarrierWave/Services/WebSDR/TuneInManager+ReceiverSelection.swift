import CarrierWaveCore
import CarrierWaveData
import Foundation

// MARK: - Receiver Selection

extension TuneInManager {
    /// Ranked list of candidate receivers for the chosen strategy.
    /// Returns available receivers in priority order (best first).
    ///
    /// The strategies (near strongest RBN spotter / near activator / near my
    /// QTH) run in the Rust core (`SdrApi.selectCandidateReceivers`), which
    /// does the RBN + HamDB lookups and the directory search. Park and
    /// summit coordinates are resolved here from the local caches and passed
    /// pre-resolved, preserving the previous lookup order.
    func selectCandidateReceivers(
        for spot: TuneInSpot,
        strategy: TuneInStrategy
    ) async -> [KiwiSDRReceiver] {
        guard let api = try? SdrApiProvider.shared() else {
            return []
        }

        let candidates = await api.selectCandidateReceivers(
            spot: spot.ffiSpot,
            strategy: strategy.ffiStrategy,
            myGrid: UserDefaults.standard.string(forKey: "loggerDefaultGrid")
        )
        return candidates.map(KiwiSDRReceiver.init(ffi:))
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
}

// MARK: - FFI Mapping

extension TuneInStrategy {
    var ffiStrategy: FfiTuneInStrategy {
        switch self {
        case .nearStrongRBN: .nearStrongRbn
        case .nearActivator: .nearActivator
        case .nearMyQTH: .nearMyQth
        }
    }
}

extension TuneInSpot {
    /// Snapshot for the Rust core, with park/summit coordinates resolved
    /// from the local caches (the host owns those datasets).
    var ffiSpot: FfiTuneInSpot {
        var parkLatitude: Double?
        var parkLongitude: Double?
        if let parkRef,
           let park = POTAParksCache.shared.parkSync(for: parkRef)
        {
            parkLatitude = park.latitude
            parkLongitude = park.longitude
        }

        var summitLatitude: Double?
        var summitLongitude: Double?
        if let summitCode,
           let summit = SOTASummitsCache.shared.lookupSummit(summitCode)
        {
            summitLatitude = summit.latitude
            summitLongitude = summit.longitude
        }

        return FfiTuneInSpot(
            callsign: callsign,
            frequencyMhz: frequencyMHz,
            mode: mode,
            band: band,
            parkRef: parkRef,
            summitCode: summitCode,
            latitude: latitude,
            longitude: longitude,
            grid: grid,
            parkLatitude: parkLatitude,
            parkLongitude: parkLongitude,
            summitLatitude: summitLatitude,
            summitLongitude: summitLongitude
        )
    }
}
