import CarrierWaveCore
import CarrierWaveCwFfi
import CarrierWaveData
import SwiftData
import SwiftUI

// MARK: - Data Loading

extension OnAirCard {
    func loadAllData() async {
        // Short-circuit redundant reloads. SwiftUI re-fires this view's
        // `.task` whenever the dashboard reappears (tab switch back), and
        // the previous behavior was to kick off 5 parallel network +
        // SwiftData fetches plus ~11 staged `@Observable` writes every
        // time — which cascaded into body invalidations and visible scroll
        // chop on every dashboard focus. Solar / DX / spot data refreshes
        // on minute timescales so a freshness window is fine.
        if Date().timeIntervalSince(lastLoadedAt) < OnAirCard.loadFreshnessWindow {
            isLoading = false
            return
        }
        // One engine poll feeds POTA + SOTA + friend spots; the loads below
        // read its snapshot (a second concurrent refresh would double-poll).
        await refreshSpotEngine()
        async let conditionsTask: Void = loadConditions()
        async let dxTask: Void = loadDXpeditions()
        async let friendsTask: Void = loadFriends()
        async let activityTask: Void = loadActivitySpots()
        // Contests load via ContestPollingService singleton
        _ = await (conditionsTask, dxTask, friendsTask, activityTask)
        isLoading = false
        lastLoadedAt = Date()
        // Fire-and-forget: resolve operator names and contact counts
        await lookupOperatorNames()
        await loadContactCounts()
    }

    func loadConditions() async {
        let container = modelContext.container
        let start = Calendar.current.date(
            byAdding: .day, value: -30, to: Date()
        ) ?? Date()

        snapshots = await (try? dataActor.fetchSnapshots(
            from: start, to: Date(), container: container
        )) ?? []

        await refreshLatestSolar()

        let hamqsl = HamQSLClient()
        solarData = try? await hamqsl.fetchSolarData()

        if let data = solarData {
            let utcHour = Calendar(identifier: .gregorian)
                .component(.hour, from: Date())
            bandEstimates = data.bandPropagation(utcHour: utcHour)
        }
    }

    /// One-shot fetch of the most recent `SolarSnapshot`. Called on view
    /// appearance and whenever `.didStoreSolarSnapshot` fires (≤ once per
    /// 30 minutes). Replaces the prior `@Query` that re-evaluated on every
    /// container save and triggered scroll hitches in the dashboard.
    func refreshLatestSolar() async {
        var descriptor = FetchDescriptor<SolarSnapshot>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        latestSolar = (try? modelContext.fetch(descriptor))?.first
    }

    func loadDXpeditions() async {
        let calendar = Calendar.current
        let now = Date()
        let month = calendar.component(.month, from: now)
        let year = calendar.component(.year, from: now)

        do {
            expeditions = try await ham365Client.fetchDXpeditions(
                month: month, year: year
            )
            await fetchOnAirSpots()
        } catch {
            dxError = error.localizedDescription
        }
    }

    func fetchOnAirSpots() async {
        let onAir = expeditions.filter(\.isOnAir)
        guard !onAir.isEmpty else {
            return
        }

        var spotsByCall: [String: [RBNSpot]] = [:]
        await withTaskGroup(of: (String, [RBNSpot]).self) { group in
            for expedition in onAir {
                group.addTask { [rbnClient] in
                    let spots = await (try? rbnClient.spots(
                        forVariants: expedition.searchCallsigns,
                        hours: 1, limit: 20
                    )) ?? []
                    return (expedition.callsign, spots)
                }
            }
            for await (callsign, spots) in group {
                spotsByCall[callsign] = spots
            }
        }
        onAirSpots = spotsByCall
    }

    func loadFriends() async {
        loadAcceptedFriends()
        let callsigns = Set(acceptedFriends.map { $0.friendCallsign.uppercased() })
        friendSpots = loadFriendSpots(friendCallsigns: callsigns)
    }

    /// One-shot fetch of accepted Friendships from SwiftData. Replaces the
    /// previous SwiftData `@Query` observer that fired on every container
    /// save (CloudKit syncs, log inserts, ActivityItem writes) and cascaded
    /// into dashboard scroll jank. Friendships change rarely; this re-runs
    /// on view re-appear via `.task`.
    func loadAcceptedFriends() {
        acceptedFriends = FriendsSyncService.shared.acceptedFriends
    }

    /// One manual spot-engine poll ahead of the snapshot-based loads.
    func refreshSpotEngine() async {
        guard showPOTASpots || showSOTASpots || !FriendsSyncService.shared.acceptedFriends.isEmpty,
              let engine = SpotEngineProvider.shared.engine()
        else {
            return
        }
        await engine.refresh()
    }

    /// POTA + SOTA activity from the engine's snapshot (single conversion
    /// pass; the legacy view models keep the card's rows unchanged).
    func loadActivitySpots() async {
        guard showPOTASpots || showSOTASpots,
              let engine = SpotEngineProvider.shared.engine()
        else {
            return
        }
        let spots = engine.snapshot(filter: nil, worked: nil).spots
        if showPOTASpots {
            potaSpots = spots.compactMap(\.appPotaSpot)
        }
        if showSOTASpots {
            sotaSpots = Array(
                spots.compactMap(\.appSotaSpot).prefix(SpotFetchLimits.onAirSOTA)
            )
        }
    }

    /// Batch-lookup operator names for visible POTA/SOTA/friend spots.
    /// Runs lookups concurrently and updates names as they resolve.
    func lookupOperatorNames() async {
        var callsigns = Set<String>()
        let bands = OnAirSpotFilter.decodeSet(from: bandFilterRaw)
        let modes = OnAirSpotFilter.decodeSet(from: modeFilterRaw)
        let maxAge = spotMaxAgeMinutes
        for spot in OnAirSpotFilter.filterPOTA(
            potaSpots, bands: bands, modes: modes, maxAgeMinutes: maxAge
        ) {
            callsigns.insert(spot.activator.uppercased())
        }
        for spot in OnAirSpotFilter.filterSOTA(
            sotaSpots, bands: bands, modes: modes, maxAgeMinutes: maxAge
        ) {
            callsigns.insert(spot.activatorCallsign.uppercased())
        }
        for item in OnAirSpotFilter.filterFriends(
            friendSpots, bands: bands, modes: modes, maxAgeMinutes: maxAge
        ) {
            callsigns.insert(item.callsign.uppercased())
        }
        guard !callsigns.isEmpty else {
            return
        }

        let lookupService = CallsignLookupService(modelContext: nil)
        await withTaskGroup(of: (String, String?).self) { group in
            for call in callsigns {
                group.addTask {
                    guard let info = await lookupService.lookup(call) else {
                        return (call, nil)
                    }
                    let displayName = info.firstName ?? info.name
                    return (call, displayName)
                }
            }
            for await (call, displayName) in group {
                if let displayName, !displayName.isEmpty {
                    operatorNames[call] = displayName.titleCased()
                }
            }
        }
    }

    /// Batch-lookup total QSO counts for visible spot callsigns.
    func loadContactCounts() async {
        var callsigns = Set<String>()
        let bands = OnAirSpotFilter.decodeSet(from: bandFilterRaw)
        let modes = OnAirSpotFilter.decodeSet(from: modeFilterRaw)
        let maxAge = spotMaxAgeMinutes
        for spot in OnAirSpotFilter.filterPOTA(
            potaSpots, bands: bands, modes: modes, maxAgeMinutes: maxAge
        ) {
            callsigns.insert(spot.activator.uppercased())
        }
        for spot in OnAirSpotFilter.filterSOTA(
            sotaSpots, bands: bands, modes: modes, maxAgeMinutes: maxAge
        ) {
            callsigns.insert(spot.activatorCallsign.uppercased())
        }
        for item in OnAirSpotFilter.filterFriends(
            friendSpots, bands: bands, modes: modes, maxAgeMinutes: maxAge
        ) {
            callsigns.insert(item.callsign.uppercased())
        }
        guard !callsigns.isEmpty else {
            return
        }

        let container = modelContext.container
        let counts = await Task.detached {
            let ctx = ModelContext(container)
            ctx.autosaveEnabled = false
            var result: [String: Int] = [:]
            for call in callsigns {
                let upper = call
                let count = (try? ctx.boundedCount(
                    QSO.self,
                    predicate: #Predicate<QSO> { qso in
                        qso.callsign == upper
                            && !qso.isHidden
                            && qso.mode != "WEATHER"
                            && qso.mode != "SOLAR"
                            && qso.mode != "NOTE"
                    }
                )) ?? 0
                if count > 0 {
                    result[call] = count
                }
            }
            return result
        }.value
        contactCounts = counts
    }
}

// MARK: - String + Title Case

private extension String {
    /// "KEVIN RITCHEY" → "Kevin Ritchey"
    func titleCased() -> String {
        lowercased().split(separator: " ").map { word in
            word.prefix(1).uppercased() + word.dropFirst()
        }.joined(separator: " ")
    }
}

// MARK: - OnAirItem

/// A merged item for the compact card, either a DXpedition or a contest.
enum OnAirItem {
    case dxpedition(Ham365DXpedition, isLive: Bool)
    case contest(Contest, isLive: Bool)
}
