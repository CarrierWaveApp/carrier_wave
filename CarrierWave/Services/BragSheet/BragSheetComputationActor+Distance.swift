import CarrierWaveCore
import Foundation

// MARK: - Distance Stats

extension BragSheetComputationActor {
    func computeFurthestContact(
        _ snapshots: [BragSheetQSOSnapshot]
    ) -> BragSheetStatValue {
        guard let best = snapshots.compactMap({ qso -> (BragSheetQSOSnapshot, Double)? in
            guard let km = qso.distanceKm else {
                return nil
            }
            return (qso, km)
        }).max(by: { $0.1 < $1.1 }) else {
            return .noData
        }
        return .contact(
            callsign: best.0.callsign,
            distanceKm: best.1,
            band: best.0.band
        )
    }

    func computeFurthestPerBand(
        _ snapshots: [BragSheetQSOSnapshot]
    ) -> BragSheetStatValue {
        let withDistance = snapshots.compactMap { qso -> (BragSheetQSOSnapshot, Double)? in
            guard let km = qso.distanceKm else {
                return nil
            }
            return (qso, km)
        }
        guard !withDistance.isEmpty else {
            return .noData
        }

        let byBand = Dictionary(grouping: withDistance) { $0.0.band.lowercased() }
        var entries: [BandTableEntry] = []
        for (band, qsos) in byBand {
            guard let best = qsos.max(by: { $0.1 < $1.1 }) else {
                continue
            }
            entries.append(BandTableEntry(
                band: band,
                callsign: best.0.callsign,
                distanceKm: best.1
            ))
        }
        entries.sort { $0.distanceKm > $1.distanceKm }
        return .bandTable(entries)
    }

    func computeFurthestQRP(
        _ snapshots: [BragSheetQSOSnapshot]
    ) -> BragSheetStatValue {
        let qrpWithDistance = snapshots.filter(\.isQRP).compactMap { qso
            -> (BragSheetQSOSnapshot, Double)? in
            guard let km = qso.distanceKm else {
                return nil
            }
            return (qso, km)
        }
        guard let best = qrpWithDistance.max(by: { $0.1 < $1.1 }) else {
            return .noData
        }
        return .contact(
            callsign: best.0.callsign,
            distanceKm: best.1,
            band: best.0.band
        )
    }

    func computeAverageDistance(
        _ snapshots: [BragSheetQSOSnapshot]
    ) -> BragSheetStatValue {
        let distances = snapshots.compactMap(\.distanceKm)
        guard !distances.isEmpty else {
            return .noData
        }
        let avg = distances.reduce(0, +) / Double(distances.count)
        return .distance(km: avg)
    }
}

// MARK: - Power & Efficiency Stats

extension BragSheetComputationActor {
    func computeLowestPower(
        _ snapshots: [BragSheetQSOSnapshot]
    ) -> BragSheetStatValue {
        let withPower = snapshots.filter { $0.power != nil && $0.power! > 0 }
        guard let lowest = withPower.min(by: { $0.power! < $1.power! }) else {
            return .noData
        }
        return .power(
            watts: lowest.power!,
            callsign: lowest.callsign,
            distanceKm: lowest.distanceKm,
            band: lowest.band
        )
    }

    func computeBestWattsPerMile(
        _ snapshots: [BragSheetQSOSnapshot]
    ) -> BragSheetStatValue {
        var bestQSO: BragSheetQSOSnapshot?
        var bestWPM = Double.infinity
        for qso in snapshots {
            guard let power = qso.power, power > 0,
                  let km = qso.distanceKm, km > 0
            else {
                continue
            }
            let miles = km * 0.621371
            let wpm = Double(power) / miles
            if wpm < bestWPM {
                bestWPM = wpm
                bestQSO = qso
            }
        }
        guard let best = bestQSO else {
            return .noData
        }

        let detail = String(
            format: "%dW to %@ at %@ on %@",
            best.power ?? 0,
            best.callsign,
            UnitFormatter.distance(best.distanceKm ?? 0),
            best.band
        )
        return .efficiency(wattsPerMile: bestWPM, detail: detail)
    }
}

// MARK: - Geographic Reach Stats

extension BragSheetComputationActor {
    func computeDXCCEntities(
        _ snapshots: [BragSheetQSOSnapshot]
    ) -> BragSheetStatValue {
        let entities = Set(snapshots.compactMap(\.dxcc))
        return .count(entities.count)
    }

    func computeNewDXCC(
        _ snapshots: [BragSheetQSOSnapshot],
        allSnapshots: [BragSheetQSOSnapshot]?
    ) -> BragSheetStatValue {
        guard let allSnapshots else {
            return .noData
        }

        let periodDXCC = Set(snapshots.compactMap(\.dxcc))
        let periodStart = snapshots.map(\.timestamp).min() ?? Date()

        // Find entities that appear in period but earliest occurrence is in period
        let allByDXCC = Dictionary(grouping: allSnapshots.filter { $0.dxcc != nil }) { $0.dxcc! }
        var newCount = 0
        for dxcc in periodDXCC {
            guard let all = allByDXCC[dxcc] else {
                continue
            }
            let earliest = all.min(by: { $0.timestamp < $1.timestamp })
            if let earliest, earliest.timestamp >= periodStart {
                newCount += 1
            }
        }
        return .count(newCount)
    }

    func computeStatesProvinces(
        _ snapshots: [BragSheetQSOSnapshot]
    ) -> BragSheetStatValue {
        let states = Set(snapshots.compactMap(\.state).filter { !$0.isEmpty })
        return .count(states.count)
    }

    func computeGridSquares(
        _ snapshots: [BragSheetQSOSnapshot]
    ) -> BragSheetStatValue {
        let grids = Set(
            snapshots.compactMap(\.theirGrid)
                .filter { !$0.isEmpty }
                .map { String($0.prefix(4)) }
        )
        return .count(grids.count)
    }

    func computeContinents(
        _ snapshots: [BragSheetQSOSnapshot]
    ) -> BragSheetStatValue {
        // Use DXCC entity number ranges to map continents
        let dxccNumbers = Set(snapshots.compactMap(\.dxcc))
        let continents = Set(dxccNumbers.compactMap { ContinentMapper.continent(forDXCC: $0) })
        guard !continents.isEmpty else {
            return .noData
        }
        return .progress(current: continents.count, total: 6)
    }

    func computeMostContinentsDay(
        _ snapshots: [BragSheetQSOSnapshot]
    ) -> BragSheetStatValue {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let byDay = Dictionary(grouping: snapshots) { calendar.startOfDay(for: $0.timestamp) }
        var best = 0
        for (_, dayQSOs) in byDay {
            let continents = Set(
                dayQSOs.compactMap(\.dxcc)
                    .compactMap { ContinentMapper.continent(forDXCC: $0) }
            )
            best = max(best, continents.count)
        }
        guard best > 0 else {
            return .noData
        }
        return .count(best)
    }

    func computeWASProgress(
        _ snapshots: [BragSheetQSOSnapshot]
    ) -> BragSheetStatValue {
        let usStates = Set(
            snapshots.filter { $0.dxcc == 291 }
                .compactMap(\.state)
                .filter { !$0.isEmpty }
                .map { $0.uppercased() }
        )
        return .progress(current: usStates.count, total: 50)
    }
}
