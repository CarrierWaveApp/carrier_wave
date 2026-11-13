import CarrierWaveCore
import CarrierWaveData
import CoreLocation
import Foundation

// MARK: - KiwiSDRReceiver

/// A KiwiSDR receiver from the public directory.
/// Explicitly nonisolated — pure value type crossing actor boundaries.
nonisolated struct KiwiSDRReceiver: Identifiable, Equatable {
    let id: String // host:port
    let name: String
    let host: String
    let port: Int
    let latitude: Double
    let longitude: Double
    let bands: String // e.g., "0-30 MHz"
    let users: Int
    let maxUsers: Int
    let location: String // e.g., "Portland, OR, USA"
    let antenna: String

    /// Distance from a reference point in km
    var distanceKm: Double?

    // Enrichment fields from /status
    var snrAll: Int?
    var snrHF: Int?
    var antConnected: Bool?
    var grid: String?
    var asl: Int?
    var parsedAntenna: ParsedAntenna?
    var enrichedAntenna: String?

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var isAvailable: Bool {
        users < maxUsers
    }

    var formattedDistance: String? {
        guard let km = distanceKm else {
            return nil
        }
        return UnitFormatter.distance(km)
    }
}

nonisolated extension KiwiSDRReceiver {
    /// Map from the Rust core's directory record.
    init(ffi: FfiKiwiReceiver) {
        id = ffi.id
        name = ffi.name
        host = ffi.host
        port = Int(ffi.port)
        latitude = ffi.latitude
        longitude = ffi.longitude
        bands = ffi.bands
        users = Int(ffi.users)
        maxUsers = Int(ffi.maxUsers)
        location = ffi.location
        antenna = ffi.antenna
        distanceKm = ffi.distanceKm
        snrAll = ffi.snrAll.map(Int.init)
        snrHF = ffi.snrHf.map(Int.init)
        antConnected = ffi.antConnected
        grid = ffi.grid
        asl = ffi.asl.map(Int.init)
        parsedAntenna = nil
        enrichedAntenna = ffi.enrichedAntenna
    }

    /// Map back to the Rust core's record (for APIs that take a receiver).
    var ffiReceiver: FfiKiwiReceiver {
        FfiKiwiReceiver(
            id: id,
            name: name,
            host: host,
            port: UInt16(port),
            latitude: latitude,
            longitude: longitude,
            bands: bands,
            users: Int32(users),
            maxUsers: Int32(maxUsers),
            location: location,
            antenna: antenna,
            distanceKm: distanceKm,
            snrAll: snrAll.map(Int32.init),
            snrHf: snrHF.map(Int32.init),
            antConnected: antConnected,
            grid: grid,
            asl: asl.map(Int32.init),
            enrichedAntenna: enrichedAntenna,
            isAvailable: isAvailable
        )
    }
}

// MARK: - WebSDRDirectory

/// Finds nearby KiwiSDR receivers. Delegates to the Rust core (`SdrApi`),
/// which owns the public-directory fetch (Skywavelinux JS mirror with the
/// kiwisdr.com HTML fallback), the daily-refresh disk cache, and the
/// distance filtering/sorting.
actor WebSDRDirectory {
    /// Shared singleton
    static let shared = WebSDRDirectory()

    /// Find nearby KiwiSDR receivers sorted by distance.
    /// - Parameter maxDistanceKm: Only return receivers within this radius.
    ///   Defaults to 500 km (regional — same state or neighboring states).
    func findNearby(
        grid: String?,
        latitude: Double? = nil,
        longitude: Double? = nil,
        maxDistanceKm: Double = 500,
        limit: Int = 10
    ) async -> [KiwiSDRReceiver] {
        guard let api = try? SdrApiProvider.shared() else {
            return []
        }
        let receivers = await api.findNearbyReceivers(
            grid: grid,
            latitude: latitude,
            longitude: longitude,
            maxDistanceKm: maxDistanceKm,
            limit: UInt32(limit)
        )
        return receivers.map(KiwiSDRReceiver.init(ffi:))
    }

    /// Force refresh the directory
    func refresh() async {
        guard let api = try? SdrApiProvider.shared() else {
            return
        }
        await api.refreshDirectory()
    }
}
