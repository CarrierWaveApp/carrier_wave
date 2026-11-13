import CarrierWaveData
import Foundation
import SwiftData

/// Background actor for loading environmental condition data from LoggingSession
/// and ActivationMetadata. Creates snapshots off the main thread for chart rendering.
actor EnvironmentalDataActor {
    // MARK: Internal

    /// Fetch all condition snapshots within a date range, optionally filtered by grid.
    func fetchSnapshots(
        from startDate: Date,
        to endDate: Date,
        grid: String? = nil,
        container: ModelContainer
    ) async throws -> [EnvironmentalSnapshot] {
        let context = ModelContext(container)
        context.autosaveEnabled = false

        var snapshots: [EnvironmentalSnapshot] = []

        // Load from LoggingSession
        let sessionSnapshots = try fetchFromSessions(
            context: context, from: startDate, to: endDate, grid: grid
        )
        snapshots.append(contentsOf: sessionSnapshots)

        // Load from ActivationMetadata
        let metadataSnapshots = try fetchFromMetadata(
            context: context, from: startDate, to: endDate, grid: grid
        )

        // Merge: prefer session data when both exist for same park/date
        let sessionKeys = Set(sessionSnapshots.compactMap { snapshot -> String? in
            guard let park = snapshot.parkReference else {
                return nil
            }
            let day = Self.dayKey(snapshot.timestamp)
            return "\(park)|\(day)"
        })

        for snapshot in metadataSnapshots {
            if let park = snapshot.parkReference {
                let key = "\(park)|\(Self.dayKey(snapshot.timestamp))"
                if sessionKeys.contains(key) {
                    continue
                }
            }
            snapshots.append(snapshot)
        }

        // Load from SolarSnapshot (hourly polling data)
        let solarSnapshots = try fetchFromSolarSnapshots(
            context: context, from: startDate, to: endDate
        )
        snapshots.append(contentsOf: solarSnapshots)

        return snapshots.sorted { $0.timestamp < $1.timestamp }
    }

    /// Fetch snapshots grouped by 4-char grid square.
    func fetchSnapshotsGroupedByGrid(
        from startDate: Date,
        to endDate: Date,
        container: ModelContainer
    ) async throws -> [String: [EnvironmentalSnapshot]] {
        let all = try await fetchSnapshots(
            from: startDate, to: endDate, container: container
        )

        var grouped: [String: [EnvironmentalSnapshot]] = [:]
        for snapshot in all {
            guard let grid = snapshot.gridSquare, grid.count >= 4 else {
                continue
            }
            let key = String(grid.prefix(4)).uppercased()
            grouped[key, default: []].append(snapshot)
        }
        return grouped
    }

    // MARK: Private

    private static func dayKey(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.string(from: date)
    }

    private func fetchFromSessions(
        context: ModelContext,
        from startDate: Date,
        to endDate: Date,
        grid: String?
    ) throws -> [EnvironmentalSnapshot] {
        var descriptor = FetchDescriptor<LoggingSession>(
            predicate: #Predicate<LoggingSession> {
                $0.startedAt >= startDate && $0.startedAt <= endDate
            },
            sortBy: [SortDescriptor(\.startedAt)]
        )
        descriptor.fetchLimit = 500

        let sessions = (try? context.fetch(descriptor)) ?? []

        return sessions.compactMap { session in
            guard session.hasSolarData || session.hasWeatherData else {
                return nil
            }

            if let filterGrid = grid, let sessionGrid = session.myGrid {
                let filterPrefix = String(filterGrid.prefix(4)).uppercased()
                let sessionPrefix = String(sessionGrid.prefix(4)).uppercased()
                if filterPrefix != sessionPrefix {
                    return nil
                }
            }

            return EnvironmentalSnapshot(
                id: session.id,
                timestamp: session.solarTimestamp ?? session.weatherTimestamp ?? session.startedAt,
                gridSquare: session.myGrid,
                sessionId: session.id,
                parkReference: session.parkReference,
                solarKIndex: session.solarKIndex,
                solarFlux: session.solarFlux,
                solarSunspots: session.solarSunspots,
                solarPropagationRating: session.solarPropagationRating,
                solarAIndex: session.solarAIndex,
                solarBandConditions: session.solarBandConditions,
                weatherTemperatureF: session.weatherTemperatureF,
                weatherTemperatureC: session.weatherTemperatureC,
                weatherHumidity: session.weatherHumidity,
                weatherWindSpeed: session.weatherWindSpeed,
                weatherWindDirection: session.weatherWindDirection,
                weatherDescription: session.weatherDescription
            )
        }
    }

    private func fetchFromSolarSnapshots(
        context: ModelContext,
        from startDate: Date,
        to endDate: Date
    ) throws -> [EnvironmentalSnapshot] {
        var descriptor = FetchDescriptor<SolarSnapshot>(
            predicate: #Predicate<SolarSnapshot> {
                $0.timestamp >= startDate && $0.timestamp <= endDate
            },
            sortBy: [SortDescriptor(\.timestamp)]
        )
        descriptor.fetchLimit = 500

        let snapshots = (try? context.fetch(descriptor)) ?? []

        return snapshots.compactMap { snap in
            guard snap.hasSolarData else {
                return nil
            }
            return EnvironmentalSnapshot(
                id: UUID(),
                timestamp: snap.timestamp,
                gridSquare: nil,
                sessionId: nil,
                parkReference: nil,
                solarKIndex: snap.kIndex,
                solarFlux: snap.solarFlux,
                solarSunspots: snap.sunspots,
                solarPropagationRating: snap.propagationRating,
                solarAIndex: snap.aIndex,
                solarBandConditions: snap.bandConditions,
                weatherTemperatureF: nil,
                weatherTemperatureC: nil,
                weatherHumidity: nil,
                weatherWindSpeed: nil,
                weatherWindDirection: nil,
                weatherDescription: nil
            )
        }
    }

    private func fetchFromMetadata(
        context: ModelContext,
        from startDate: Date,
        to endDate: Date,
        grid: String?
    ) throws -> [EnvironmentalSnapshot] {
        var descriptor = FetchDescriptor<ActivationMetadata>(
            predicate: #Predicate<ActivationMetadata> {
                $0.date >= startDate && $0.date <= endDate
            },
            sortBy: [SortDescriptor(\.date)]
        )
        descriptor.fetchLimit = 500

        let metadata = (try? context.fetch(descriptor)) ?? []

        return metadata.compactMap { meta in
            guard meta.hasSolarData || meta.hasWeatherData else {
                return nil
            }

            // ActivationMetadata doesn't store grid, so grid filtering skips these
            if grid != nil {
                return nil
            }

            return EnvironmentalSnapshot(
                id: UUID(),
                timestamp: meta.solarTimestamp ?? meta.weatherTimestamp ?? meta.date,
                gridSquare: nil,
                sessionId: nil,
                parkReference: meta.parkReference,
                solarKIndex: meta.solarKIndex,
                solarFlux: meta.solarFlux,
                solarSunspots: meta.solarSunspots,
                solarPropagationRating: meta.solarPropagationRating,
                solarAIndex: meta.solarAIndex,
                solarBandConditions: meta.solarBandConditions,
                weatherTemperatureF: meta.weatherTemperatureF,
                weatherTemperatureC: meta.weatherTemperatureC,
                weatherHumidity: meta.weatherHumidity,
                weatherWindSpeed: meta.weatherWindSpeed,
                weatherWindDirection: meta.weatherWindDirection,
                weatherDescription: meta.weatherDescription
            )
        }
    }
}
