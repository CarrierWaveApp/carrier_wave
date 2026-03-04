import CarrierWaveData
import Foundation

// MARK: - TuneInQSYAlert

/// Alert data when the tuned activator is re-spotted on a different frequency.
struct TuneInQSYAlert: Equatable {
    let callsign: String
    let newFrequencyMHz: Double
    let newMode: String
    let newBand: String
    let currentFrequencyMHz: Double
    let currentBand: String
}

// MARK: - ReceiverSuggestion

/// Suggestion to switch to a better receiver.
struct ReceiverSuggestion: Equatable {
    let currentName: String
    let suggestedName: String
    let suggestedReceiver: KiwiSDRReceiver
    let reason: String

    static func == (lhs: ReceiverSuggestion, rhs: ReceiverSuggestion) -> Bool {
        lhs.currentName == rhs.currentName && lhs.suggestedName == rhs.suggestedName
    }
}

// MARK: - FollowedActivator

/// An activator callsign the user is following.
struct FollowedActivator: Codable, Identifiable, Equatable {
    let callsign: String
    let followedAt: Date
    /// Last known frequency when followed
    let frequencyMHz: Double?
    let mode: String?

    var id: String {
        callsign
    }
}

// MARK: - Smart Features

extension TuneInManager {
    // MARK: - QSY Detection

    /// Start monitoring for QSY (frequency change) of the tuned activator
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
                // Check every 45 seconds
                try? await Task.sleep(for: .seconds(45))
                guard !Task.isCancelled else {
                    break
                }

                do {
                    let spots = try await rbn.spots(
                        for: callsign, hours: 1, limit: 20
                    )
                    // Find the most recent spot with a different frequency
                    let recentCutoff = Date().addingTimeInterval(-300) // 5 min
                    let qsySpot = spots
                        .filter { $0.timestamp > recentCutoff }
                        .sorted { $0.timestamp > $1.timestamp }
                        .first { abs($0.frequency - currentFreq * 1_000) > 1.0 }

                    if let qsy = qsySpot {
                        let newFreqMHz = qsy.frequency / 1_000.0
                        let newBand = LoggingSession.bandForFrequency(newFreqMHz)
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
                        break // One alert per session, don't spam
                    }
                } catch {
                    // Network error — silently retry next cycle
                }
            }
        }
    }

    /// Stop QSY monitoring
    func stopQSYMonitor() {
        qsyMonitorTask?.cancel()
        qsyMonitorTask = nil
        qsyAlert = nil
    }

    /// Accept a QSY retune — switch to the new frequency
    func acceptQSYRetune() async {
        guard let alert = qsyAlert else {
            return
        }
        await session.retune(frequencyMHz: alert.newFrequencyMHz)
        // Update the spot metadata
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
        // Restart QSY monitor for the new frequency
        startQSYMonitor()
    }

    /// Dismiss a QSY alert without retuning
    func dismissQSYAlert() {
        qsyAlert = nil
    }

    // MARK: - Receiver Quality Monitoring

    /// Start monitoring receiver quality and suggest alternatives
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
                      await self.isActive,
                      let currentReceiver = await self.session.receiver,
                      let spot = await self.spot
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

    /// Check nearby receivers for better SNR than current
    private func findBetterReceiver(
        fetcher: KiwiSDRStatusFetcher,
        current: KiwiSDRReceiver,
        snr: Int,
        spot: TuneInSpot
    ) async -> ReceiverSuggestion? {
        let alternatives = await WebSDRDirectory.shared.findNearby(
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

    /// Stop receiver quality monitoring
    func stopReceiverMonitor() {
        receiverMonitorTask?.cancel()
        receiverMonitorTask = nil
        receiverSuggestion = nil
    }

    /// Dismiss a receiver suggestion
    func dismissReceiverSuggestion() {
        receiverSuggestion = nil
    }

    // MARK: - Follow Activator

    /// Currently followed activators
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

    /// Whether a callsign is currently followed
    func isFollowing(_ callsign: String) -> Bool {
        followedActivators.contains {
            $0.callsign.uppercased() == callsign.uppercased()
        }
    }

    /// Follow an activator callsign
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

    /// Unfollow an activator callsign
    func unfollowActivator(_ callsign: String) {
        var list = followedActivators
        list.removeAll {
            $0.callsign.uppercased() == callsign.uppercased()
        }
        followedActivators = list
    }

    /// Toggle follow state for an activator
    func toggleFollow(_ callsign: String, frequencyMHz: Double?, mode: String?) {
        if isFollowing(callsign) {
            unfollowActivator(callsign)
        } else {
            followActivator(callsign, frequencyMHz: frequencyMHz, mode: mode)
        }
    }

    // MARK: - Private Storage

    private static let followedActivatorsKey = "tuneInFollowedActivators"
}
