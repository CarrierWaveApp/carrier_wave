import CarrierWaveData
import CoreLocation
import XCTest
@testable import CarrierWave

/// CAR-135: the activation brag sheet map must render offline.
///
/// Covers the two failure modes separately: the location fallback chain
/// (QSOs whose callsign lookups never ran) and the tile fetch failing
/// (MKMapSnapshotter offline → deterministic vector fallback).
final class ActivationShareOfflineMapTests: XCTestCase {
    // MARK: Internal

    override func setUp() {
        super.setUp()
        savedStyle = UserDefaults.standard.string(forKey: "shareMapStyle")
        // Force the MapKit path so the injected snapshot provider is exercised
        // (custom styles render through the Rust FFI and never touch it).
        UserDefaults.standard.set("flat", forKey: "shareMapStyle")
    }

    override func tearDown() {
        if let savedStyle {
            UserDefaults.standard.set(savedStyle, forKey: "shareMapStyle")
        } else {
            UserDefaults.standard.removeObject(forKey: "shareMapStyle")
        }
        super.tearDown()
    }

    // MARK: - Resolver: fallback chain

    func testResolver_gridTakesPrecedenceOverFallbacks() {
        let contact = ActivationShareContact(
            callsign: "K4SWL", theirGrid: "EM66", theirParkReference: "US-0001"
        )
        let lookups = ActivationShareMapResolver.Lookups(
            parkCoordinate: { _ in Self.parkCoordinate },
            summitCoordinate: { _ in nil },
            entityCoordinate: { _ in nil }
        )

        let coordinate = ActivationShareMapResolver.coordinate(for: contact, lookups: lookups)

        XCTAssertNotNil(coordinate)
        // EM66 is in Tennessee, nowhere near the injected park coordinate.
        XCTAssertEqual(coordinate?.latitude ?? 0, 36, accuracy: 1.5)
        XCTAssertEqual(coordinate?.longitude ?? 0, -87, accuracy: 1.5)
    }

    func testResolver_fallsThroughParkSummitEntity_andCountsUnplaced() {
        let contacts = [
            ActivationShareContact(callsign: "W1AAA", theirGrid: "FN31"),
            ActivationShareContact(callsign: "W2BBB", theirParkReference: "US-1234"),
            ActivationShareContact(callsign: "W3CCC", sotaRef: "W6/CT-021"),
            ActivationShareContact(callsign: "DL4DDD"),
            ActivationShareContact(callsign: "NOLOC"),
            ActivationShareContact(callsign: "   "),
        ]
        let lookups = ActivationShareMapResolver.Lookups(
            parkCoordinate: { reference in reference == "US-1234" ? Self.parkCoordinate : nil },
            summitCoordinate: { code in code == "W6/CT-021" ? Self.summitCoordinate : nil },
            entityCoordinate: { callsign in callsign == "DL4DDD" ? Self.entityCoordinate : nil }
        )

        let resolved = ActivationShareMapResolver.resolve(contacts: contacts, lookups: lookups)

        XCTAssertEqual(resolved.markers.count, 4)
        XCTAssertEqual(resolved.withoutLocationCount, 2)
        XCTAssertEqual(resolved.withoutLocationCaption, "2 contacts without location")
        // Each contact lands on the first rung of the chain that resolves.
        XCTAssertEqual(resolved.markers[0].coordinate.latitude, 41.5, accuracy: 1.5)
        XCTAssertEqual(resolved.markers[1].coordinate.latitude, Self.parkCoordinate.latitude)
        XCTAssertEqual(resolved.markers[2].coordinate.longitude, Self.summitCoordinate.longitude)
        XCTAssertEqual(resolved.markers[3].coordinate.latitude, Self.entityCoordinate.latitude)
    }

    func testResolver_shortGridFallsThroughToPark() {
        let contact = ActivationShareContact(
            callsign: "K4SWL", theirGrid: "EM", theirParkReference: "US-0001"
        )
        let lookups = ActivationShareMapResolver.Lookups(
            parkCoordinate: { _ in Self.parkCoordinate },
            summitCoordinate: { _ in nil },
            entityCoordinate: { _ in nil }
        )

        let coordinate = ActivationShareMapResolver.coordinate(for: contact, lookups: lookups)

        XCTAssertEqual(coordinate?.latitude, Self.parkCoordinate.latitude)
    }

    func testResolver_twoFerParkReference_usesFirstResolvablePark() {
        let contact = ActivationShareContact(
            callsign: "K4SWL", theirParkReference: "US-9999, us-1234"
        )
        let lookups = ActivationShareMapResolver.Lookups(
            parkCoordinate: { reference in reference == "US-1234" ? Self.parkCoordinate : nil },
            summitCoordinate: { _ in nil },
            entityCoordinate: { _ in nil }
        )

        let coordinate = ActivationShareMapResolver.coordinate(for: contact, lookups: lookups)

        XCTAssertEqual(coordinate?.longitude, Self.parkCoordinate.longitude)
    }

    func testResolver_liveEntityLookup_placesForeignCallsignInItsCountry() {
        let contact = ActivationShareContact(callsign: "DL1ABC")

        let coordinate = ActivationShareMapResolver.coordinate(for: contact, lookups: .live)

        XCTAssertNotNil(coordinate, "DXCC centroid should place a German callsign")
        XCTAssertEqual(coordinate?.latitude ?? 0, 51, accuracy: 5)
        XCTAssertEqual(coordinate?.longitude ?? 0, 10, accuracy: 6)
    }

    func testWithoutLocationCaption_pluralisation() {
        XCTAssertNil(ActivationShareMapMarkers.caption(forCount: 0))
        XCTAssertEqual(ActivationShareMapMarkers.caption(forCount: 1), "1 contact without location")
        XCTAssertEqual(ActivationShareMapMarkers.caption(forCount: 3), "3 contacts without location")
    }

    // MARK: - Fallback decision: snapshot failure → offline map

    @MainActor
    func testRenderMapImage_failingSnapshot_rendersOfflineFallbackAtMapSize() async {
        let image = await ActivationShareRenderer.renderMapImage(
            markers: Self.markers,
            myCoordinate: Self.operatorCoordinate,
            withoutLocationCount: 2,
            snapshotProvider: .unavailable
        )

        guard let image else {
            return XCTFail("Snapshot failure must fall back to the offline map, not nil")
        }
        XCTAssertEqual(image.size, ActivationShareRenderer.mapSize)
        XCTAssertEqual(image.scale, ActivationShareRenderer.mapScale)
        XCTAssertEqual(image.cgImage?.width, 736)
        XCTAssertEqual(image.cgImage?.height, 400)
    }

    @MainActor
    func testRenderMapImage_snapshotThrowsCustomError_stillFallsBack() async {
        struct TileServerDown: Error {}
        let provider = ShareMapSnapshotProvider { _ in throw TileServerDown() }

        let image = await ActivationShareRenderer.renderMapImage(
            markers: Self.markers,
            myCoordinate: nil,
            withoutLocationCount: 0,
            snapshotProvider: provider
        )

        XCTAssertEqual(image?.size, ActivationShareRenderer.mapSize)
    }

    @MainActor
    func testRenderMapImage_noMarkers_returnsNilForEmptyState() async {
        let image = await ActivationShareRenderer.renderMapImage(
            markers: [],
            myCoordinate: Self.operatorCoordinate,
            withoutLocationCount: 5,
            snapshotProvider: .unavailable
        )

        XCTAssertNil(image)
    }

    @MainActor
    func testOfflineMap_isDeterministic() {
        let first = ActivationShareOfflineMap.render(
            markers: Self.markers, myCoordinate: Self.operatorCoordinate,
            withoutLocationCount: 1,
            size: ActivationShareRenderer.mapSize, scale: ActivationShareRenderer.mapScale
        )
        let second = ActivationShareOfflineMap.render(
            markers: Self.markers, myCoordinate: Self.operatorCoordinate,
            withoutLocationCount: 1,
            size: ActivationShareRenderer.mapSize, scale: ActivationShareRenderer.mapScale
        )

        XCTAssertEqual(first.size, ActivationShareRenderer.mapSize)
        XCTAssertNotNil(first.pngData())
        XCTAssertEqual(first.pngData(), second.pngData())
    }

    @MainActor
    func testRenderWithMap_failingSnapshot_rendersFullCardAtStandardSize() async {
        let qsos = [
            QSO(
                callsign: "K4SWL", band: "20m", mode: "CW",
                timestamp: Date(timeIntervalSince1970: 1_700_000_000),
                myCallsign: "W1ABC", myGrid: "FN31", theirGrid: "EM66",
                parkReference: "US-0189", importSource: .logger
            ),
            QSO(
                callsign: "WA7DEF", band: "40m", mode: "SSB",
                timestamp: Date(timeIntervalSince1970: 1_700_003_600),
                myCallsign: "W1ABC", myGrid: "FN31",
                parkReference: "US-0189", importSource: .logger
            ),
        ]
        let activation = POTAActivation(
            parkReference: "US-0189",
            utcDate: Date(timeIntervalSince1970: 1_700_000_000),
            callsign: "W1ABC",
            qsos: qsos
        )

        let image = await ActivationShareRenderer.renderWithMap(
            source: .pota(activation: activation, parkName: "Test Park"),
            myGrid: "FN31",
            snapshotProvider: .unavailable
        )

        XCTAssertEqual(image?.size.width, 400)
        XCTAssertEqual(image?.size.height, 640)
    }

    // MARK: Private

    private static let parkCoordinate = CLLocationCoordinate2D(latitude: 44.5, longitude: -122.1)
    private static let summitCoordinate = CLLocationCoordinate2D(latitude: 34.2, longitude: -118.3)
    private static let entityCoordinate = CLLocationCoordinate2D(latitude: 51.0, longitude: 10.0)
    private static let operatorCoordinate = CLLocationCoordinate2D(latitude: 41.5, longitude: -72.9)

    private static let markers = [
        ShareMapMarker(
            coordinate: CLLocationCoordinate2D(latitude: 36.0, longitude: -86.9),
            rstColor: .green
        ),
        ShareMapMarker(
            coordinate: CLLocationCoordinate2D(latitude: 47.6, longitude: -122.3),
            rstColor: .orange
        ),
    ]

    private var savedStyle: String?
}
