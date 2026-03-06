import CarrierWaveCore
import CarrierWaveData
import Foundation

// MARK: - Smart Features

extension TuneInManager {
    // MARK: - QSY Detection

    func startQSYMonitor() {
        guard let spot else {
            return
        }
        stopQSYMonitor()

        qsyMonitorTask = Task { [weak self] in
            let rbn = RBNClient()
            let callsign = spot.callsign
            let currentFreq = spot.frequencyMHz

            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(45))
                guard !Task.isCancelled else {
                    break
                }

                do {
                    let spots = try await rbn.spots(
                        for: callsign, hours: 1, limit: 20
                    )
                    let recentCutoff = Date().addingTimeInterval(-300)
                    let qsySpot = spots
                        .filter { $0.timestamp > recentCutoff }
                        .sorted { $0.timestamp > $1.timestamp }
                        .first { abs($0.frequency - currentFreq * 1_000) > 1.0 }

                    if let qsy = qsySpot {
                        let newFreqMHz = qsy.frequency / 1_000.0
                        let newBand = BandUtilities.deriveBand(
                            from: qsy.frequency
                        ) ?? ""
                        await MainActor.run { [weak self] in
                            guard let self, isActive else {
                                return
                            }
                            qsyAlert = TuneInQSYAlert(
                                callsign: callsign,
                                newFrequencyMHz: newFreqMHz,
                                newMode: self.spot?.mode ?? "CW",
                                newBand: newBand,
                                currentFrequencyMHz: currentFreq,
                                currentBand: self.spot?.band ?? ""
                            )
                        }
                        break
                    }
                } catch {
                    // Network error — silently retry next cycle
                }
            }
        }
    }

    func stopQSYMonitor() {
        qsyMonitorTask?.cancel()
        qsyMonitorTask = nil
        qsyAlert = nil
    }

    func acceptQSYRetune() async {
        guard let alert = qsyAlert else {
            return
        }
        await session.retune(frequencyMHz: alert.newFrequencyMHz)

        if let currentSpot = spot {
            spot = TuneInSpot(
                callsign: currentSpot.callsign,
                frequencyMHz: alert.newFrequencyMHz,
                mode: alert.newMode,
                band: alert.newBand,
                parkRef: currentSpot.parkRef,
                parkName: currentSpot.parkName,
                summitCode: currentSpot.summitCode,
                summitName: currentSpot.summitName,
                latitude: currentSpot.latitude,
                longitude: currentSpot.longitude,
                grid: currentSpot.grid
            )
        }
        qsyAlert = nil
        startQSYMonitor()
    }

    func dismissQSYAlert() {
        qsyAlert = nil
    }

    // MARK: - Receiver Quality Monitoring

    func startReceiverMonitor() {
        stopReceiverMonitor()

        receiverMonitorTask = Task { [weak self] in
            let fetcher = KiwiSDRStatusFetcher()

            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(120))
                guard !Task.isCancelled else {
                    break
                }

                guard let self = await MainActor.run(body: { self }),
                      self.isActive,
                      let currentReceiver = self.session.receiver,
                      let spot = self.spot
                else {
                    continue
                }

                let currentStatus = await fetcher.fetchStatus(
                    host: currentReceiver.host,
                    port: currentReceiver.port
                )
                let currentSNR = currentStatus?.snrHF ?? currentStatus?.snrAll
                guard let snr = currentSNR, snr < 10 else {
                    continue
                }

                if let suggestion = await self.findBetterReceiver(
                    fetcher: fetcher, current: currentReceiver,
                    snr: snr, spot: spot
                ) {
                    await MainActor.run { [weak self] in
                        self?.receiverSuggestion = suggestion
                    }
                    return
                }
            }
        }
    }

    func findBetterReceiver(
        fetcher: KiwiSDRStatusFetcher,
        current: KiwiSDRReceiver,
        snr: Int,
        spot: TuneInSpot
    ) async -> ReceiverSuggestion? {
        let alternatives = await directory.findNearby(
            grid: spot.grid, latitude: spot.latitude,
            longitude: spot.longitude, limit: 5
        )
        for alt in alternatives where alt.id != current.id && alt.isAvailable {
            let altStatus = await fetcher.fetchStatus(
                host: alt.host, port: alt.port
            )
            let altSNR = altStatus?.snrHF ?? altStatus?.snrAll ?? 0
            if altSNR > snr + 5 {
                return ReceiverSuggestion(
                    currentName: current.name,
                    suggestedName: alt.name,
                    suggestedReceiver: alt,
                    reason: "\(alt.name) has better reception (SNR \(altSNR) dB vs \(snr) dB)"
                )
            }
        }
        return nil
    }

    func stopReceiverMonitor() {
        receiverMonitorTask?.cancel()
        receiverMonitorTask = nil
        receiverSuggestion = nil
    }

    func dismissReceiverSuggestion() {
        receiverSuggestion = nil
    }

    // MARK: - Follow Activator

    var followedActivators: [FollowedActivator] {
        get {
            guard let data = UserDefaults.standard.data(
                forKey: Self.followedActivatorsKey
            ) else {
                return []
            }
            return (try? JSONDecoder().decode(
                [FollowedActivator].self, from: data
            )) ?? []
        }
        set {
            let data = try? JSONEncoder().encode(newValue)
            UserDefaults.standard.set(data, forKey: Self.followedActivatorsKey)
        }
    }

    func isFollowing(_ callsign: String) -> Bool {
        followedActivators.contains {
            $0.callsign.uppercased() == callsign.uppercased()
        }
    }

    func followActivator(
        _ callsign: String,
        frequencyMHz: Double? = nil,
        mode: String? = nil
    ) {
        guard !isFollowing(callsign) else {
            return
        }
        var list = followedActivators
        list.append(FollowedActivator(
            callsign: callsign.uppercased(),
            followedAt: Date(),
            frequencyMHz: frequencyMHz,
            mode: mode
        ))
        followedActivators = list
    }

    func unfollowActivator(_ callsign: String) {
        var list = followedActivators
        list.removeAll {
            $0.callsign.uppercased() == callsign.uppercased()
        }
        followedActivators = list
    }

    func toggleFollow(_ callsign: String, frequencyMHz: Double?, mode: String?) {
        if isFollowing(callsign) {
            unfollowActivator(callsign)
        } else {
            followActivator(callsign, frequencyMHz: frequencyMHz, mode: mode)
        }
    }

    static let followedActivatorsKey = "tuneInFollowedActivators"
}
