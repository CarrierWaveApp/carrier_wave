import Foundation

// MARK: - Search & Nearby Lookup

extension POTAParksCache {
    /// Search parks by name using sorted index for O(log n) prefix matching.
    /// When `homeLat`/`homeLon` are provided, results are sorted by distance.
    nonisolated func searchByName(
        _ query: String,
        limit: Int = 20,
        homeLat: Double? = nil,
        homeLon: Double? = nil
    ) -> [POTAPark] {
        let queryWords = query.lowercased()
            .components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }

        guard !queryWords.isEmpty else {
            return []
        }

        var matchingRefs: Set<String>?

        for word in queryWords {
            let wordMatches = refsMatchingPrefix(word)

            if let existing = matchingRefs {
                matchingRefs = existing.intersection(wordMatches)
            } else {
                matchingRefs = wordMatches
            }

            if matchingRefs?.isEmpty == true {
                return []
            }
        }

        guard let refs = matchingRefs else {
            return []
        }

        var results = refs.compactMap { park(inStorage: $0) }

        if let hLat = homeLat, let hLon = homeLon {
            results.sort { lhs, rhs in
                let distL = parkDistance(lhs, lat: hLat, lon: hLon)
                let distR = parkDistance(rhs, lat: hLat, lon: hLon)
                return distL < distR
            }
        } else {
            results.sort { lhs, rhs in
                if lhs.name.count != rhs.name.count {
                    return lhs.name.count < rhs.name.count
                }
                return lhs.name < rhs.name
            }
        }

        return Array(results.prefix(limit))
    }

    /// Distance from a park to a reference point. Parks without coordinates sort last.
    nonisolated private func parkDistance(
        _ park: POTAPark, lat: Double, lon: Double
    ) -> Double {
        guard let pLat = park.latitude, let pLon = park.longitude else {
            return .greatestFiniteMagnitude
        }
        return haversineDistance(lat1: lat, lon1: lon, lat2: pLat, lon2: pLon)
    }

    /// Find parks near a location, sorted by distance.
    nonisolated func nearbyParks(
        latitude: Double,
        longitude: Double,
        limit: Int = 20,
        maxDistanceKm: Double = 100
    ) -> [(park: POTAPark, distanceKm: Double)] {
        var results: [(park: POTAPark, distanceKm: Double)] = []
        let snapshot = parksSnapshot()

        for park in snapshot.values {
            guard let parkLat = park.latitude,
                  let parkLon = park.longitude
            else {
                continue
            }

            let dist = haversineDistance(
                lat1: latitude, lon1: longitude,
                lat2: parkLat, lon2: parkLon
            )

            if dist <= maxDistanceKm {
                results.append((park: park, distanceKm: dist))
            }
        }

        results.sort { $0.distanceKm < $1.distanceKm }
        return Array(results.prefix(limit))
    }

    /// Binary search the sorted index for all refs whose word starts with `prefix`.
    nonisolated func refsMatchingPrefix(_ prefix: String) -> Set<String> {
        // POTA uses (word, refs) tuples; convert to shared format
        let snapshot = nameIndexSnapshot()
        let converted = snapshot.map { (word: $0.word, codes: $0.refs) }
        return NameIndexSearch.codesMatchingPrefix(prefix, in: converted)
    }

    /// Haversine distance between two coordinates in kilometers.
    nonisolated func haversineDistance(
        lat1: Double, lon1: Double,
        lat2: Double, lon2: Double
    ) -> Double {
        HaversineDistance.distance(lat1: lat1, lon1: lon1, lat2: lat2, lon2: lon2)
    }
}
