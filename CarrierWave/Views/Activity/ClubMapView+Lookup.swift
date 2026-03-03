import CoreLocation
import Foundation

// MARK: - ClubMapView+Lookup

extension ClubMapView {
    // MARK: - Main Lookup Flow

    func lookupLocations() async {
        guard !isLoading else {
            return
        }
        isLoading = true
        defer { isLoading = false }

        let cache = MemberLocationCache.shared
        let hamdb = HamDBClient()
        let qrzKey = await Self.acquireQRZSessionKey()
        let members = club.members.map {
            MemberLookupInput(
                callsign: $0.callsign,
                role: $0.role,
                status: memberStatuses[
                    $0.callsign.uppercased()
                ]?.status
            )
        }
        totalCount = members.count
        resolvedCount = 0

        let (cached, uncached) = await resolveCachedMembers(
            members, cache: cache
        )
        var locations = cached
        if !locations.isEmpty {
            memberLocations = locations.sorted {
                $0.callsign < $1.callsign
            }
        }

        locations += await fetchUncachedMembers(
            uncached, qrzSessionKey: qrzKey,
            hamdb: hamdb, cache: cache
        )
        await cache.persist()
        memberLocations = locations.sorted {
            $0.callsign < $1.callsign
        }
    }

    // MARK: - Cache Resolution

    private func resolveCachedMembers(
        _ members: [MemberLookupInput],
        cache: MemberLocationCache
    ) async -> (
        cached: [MemberLocation],
        uncached: [MemberLookupInput]
    ) {
        var cached: [MemberLocation] = []
        var uncached: [MemberLookupInput] = []

        for member in members {
            switch await cache.lookup(callsign: member.callsign) {
            case let .found(coord):
                cached.append(MemberLocation(
                    callsign: member.callsign,
                    coordinate: coord,
                    role: member.role,
                    status: member.status
                ))
                resolvedCount += 1
            case .noLocation:
                resolvedCount += 1
            case .miss:
                uncached.append(member)
            }
        }
        return (cached, uncached)
    }

    // MARK: - Batch Fetch

    private func fetchUncachedMembers(
        _ uncached: [MemberLookupInput],
        qrzSessionKey: String?,
        hamdb: HamDBClient,
        cache: MemberLocationCache
    ) async -> [MemberLocation] {
        var locations: [MemberLocation] = []
        for batch in uncached.chunked(into: 3) {
            await withTaskGroup(
                of: MemberLocation?.self
            ) { group in
                for input in batch {
                    group.addTask {
                        await Self.lookupMember(
                            input: input,
                            qrzSessionKey: qrzSessionKey,
                            hamdb: hamdb,
                            cache: cache
                        )
                    }
                }
                for await location in group {
                    resolvedCount += 1
                    if let location {
                        locations.append(location)
                    }
                }
            }
            try? await Task.sleep(for: .milliseconds(200))
        }
        return locations
    }

    // MARK: - Per-Member Lookup (QRZ → HamDB)

    private static func lookupMember(
        input: MemberLookupInput,
        qrzSessionKey: String?,
        hamdb: HamDBClient,
        cache: MemberLocationCache
    ) async -> MemberLocation? {
        // Try QRZ first (better international coverage)
        if let key = qrzSessionKey,
           let coord = await lookupCoordinatesViaQRZ(
               callsign: input.callsign, sessionKey: key
           )
        {
            await cache.store(
                callsign: input.callsign, coordinate: coord
            )
            return MemberLocation(
                callsign: input.callsign,
                coordinate: coord,
                role: input.role,
                status: input.status
            )
        }

        // Fall back to HamDB (free, US only)
        if let coord = await lookupCoordinatesViaHamDB(
            callsign: input.callsign, hamdb: hamdb
        ) {
            await cache.store(
                callsign: input.callsign, coordinate: coord
            )
            return MemberLocation(
                callsign: input.callsign,
                coordinate: coord,
                role: input.role,
                status: input.status
            )
        }

        await cache.store(
            callsign: input.callsign, coordinate: nil
        )
        return nil
    }

    // MARK: - QRZ XML API

    static func acquireQRZSessionKey()
        async -> String?
    {
        guard let username = try? KeychainHelper.shared
            .readString(
                for: KeychainHelper.Keys.qrzCallbookUsername
            ),
            let password = try? KeychainHelper.shared
            .readString(
                for: KeychainHelper.Keys.qrzCallbookPassword
            )
        else {
            return nil
        }

        let qrzURL = "https://xmldata.qrz.com/xml/current/"
        guard var components = URLComponents(
            string: qrzURL
        ) else {
            return nil
        }
        components.queryItems = [
            URLQueryItem(name: "username", value: username),
            URLQueryItem(name: "password", value: password),
            URLQueryItem(name: "agent", value: "CarrierWave"),
        ]
        guard let url = components.url else {
            return nil
        }

        var request = URLRequest(url: url)
        request.setValue(
            "CarrierWave/1.0",
            forHTTPHeaderField: "User-Agent"
        )
        request.timeoutInterval = 15

        guard let (data, _) = try? await URLSession.shared
            .data(for: request),
            let xml = String(data: data, encoding: .utf8)
        else {
            return nil
        }
        return parseXMLTag("Key", from: xml)
    }

    private static func lookupCoordinatesViaQRZ(
        callsign: String,
        sessionKey: String
    ) async -> CLLocationCoordinate2D? {
        let qrzURL = "https://xmldata.qrz.com/xml/current/"
        guard var components = URLComponents(
            string: qrzURL
        ) else {
            return nil
        }
        components.queryItems = [
            URLQueryItem(name: "s", value: sessionKey),
            URLQueryItem(name: "callsign", value: callsign),
        ]
        guard let url = components.url else {
            return nil
        }

        var request = URLRequest(url: url)
        request.setValue(
            "CarrierWave/1.0",
            forHTTPHeaderField: "User-Agent"
        )
        request.timeoutInterval = 10

        guard let (data, _) = try? await URLSession.shared
            .data(for: request),
            let xml = String(data: data, encoding: .utf8),
            let latStr = parseXMLTag("lat", from: xml),
            let lonStr = parseXMLTag("lon", from: xml),
            let lat = Double(latStr),
            let lon = Double(lonStr),
            lat != 0 || lon != 0
        else {
            return nil
        }
        return CLLocationCoordinate2D(
            latitude: lat, longitude: lon
        )
    }

    // MARK: - HamDB Fallback

    private static func lookupCoordinatesViaHamDB(
        callsign: String,
        hamdb: HamDBClient
    ) async -> CLLocationCoordinate2D? {
        guard let license = try? await hamdb.lookup(
            callsign: callsign
        ),
            let latStr = license.lat,
            let lonStr = license.lon,
            let lat = Double(latStr),
            let lon = Double(lonStr),
            lat != 0 || lon != 0
        else {
            return nil
        }
        return CLLocationCoordinate2D(
            latitude: lat, longitude: lon
        )
    }

    // MARK: - XML Parsing

    private static func parseXMLTag(
        _ tag: String,
        from xml: String
    ) -> String? {
        let open = "<\(tag)>"
        let close = "</\(tag)>"
        guard let start = xml.range(of: open),
              let end = xml.range(
                  of: close,
                  range: start.upperBound ..< xml.endIndex
              )
        else {
            return nil
        }
        let value = String(
            xml[start.upperBound ..< end.lowerBound]
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
