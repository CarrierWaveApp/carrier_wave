import CoreLocation
import Testing
@testable import CarrierWave

// MARK: - MockLocationProvider

@MainActor
final class MockLocationProvider: LocationProviding {
    var delegate: (any CLLocationManagerDelegate)?
    var desiredAccuracy: CLLocationAccuracy = 0
    var mockAuthorizationStatus: CLAuthorizationStatus = .notDetermined
    private(set) var startUpdatesCalled = 0
    private(set) var stopUpdatesCalled = 0
    private(set) var authRequested = false

    var authorizationStatus: CLAuthorizationStatus {
        mockAuthorizationStatus
    }

    func requestWhenInUseAuthorization() {
        authRequested = true
    }

    func startUpdatingLocation() {
        startUpdatesCalled += 1
    }

    func stopUpdatingLocation() {
        stopUpdatesCalled += 1
    }

    /// Simulate a location fix by calling the delegate
    func simulateLocation(latitude: Double, longitude: Double) {
        let location = CLLocation(latitude: latitude, longitude: longitude)
        delegate?.locationManager?(
            CLLocationManager(),
            didUpdateLocations: [location]
        )
    }

    /// Simulate a location error
    func simulateError(_ error: Error) {
        delegate?.locationManager?(
            CLLocationManager(),
            didFailWithError: error
        )
    }

    /// Simulate an authorization change. The service reads status from
    /// self.locationProvider (this mock), not the passed CLLocationManager.
    func simulateAuthorizationChange(_ status: CLAuthorizationStatus) {
        mockAuthorizationStatus = status
        let tempManager = CLLocationManager()
        delegate?.locationManagerDidChangeAuthorization?(tempManager)
    }
}

// MARK: - LocationSessionServiceTests

struct LocationSessionServiceTests {
    @MainActor
    @Test("start requests authorization when not determined")
    func startRequestsAuth() {
        let mock = MockLocationProvider()
        mock.mockAuthorizationStatus = .notDetermined
        let service = LocationSessionService(locationProvider: mock)

        service.start()

        #expect(mock.authRequested)
        #expect(mock.startUpdatesCalled == 0)
        #expect(service.isMonitoring)
    }

    @MainActor
    @Test("start begins monitoring when authorized")
    func startBeginsMonitoring() {
        let mock = MockLocationProvider()
        mock.mockAuthorizationStatus = .authorizedWhenInUse
        let service = LocationSessionService(locationProvider: mock)

        service.start()

        #expect(mock.startUpdatesCalled == 1)
        #expect(service.isMonitoring)
        #expect(service.locationAuthorized)
    }

    @MainActor
    @Test("start sets error when denied")
    func startSetsErrorWhenDenied() {
        let mock = MockLocationProvider()
        mock.mockAuthorizationStatus = .denied
        let service = LocationSessionService(locationProvider: mock)

        service.start()

        #expect(service.locationError != nil)
        #expect(mock.startUpdatesCalled == 0)
    }

    @MainActor
    @Test("stop decrements reference count")
    func stopDecrementsRefCount() {
        let mock = MockLocationProvider()
        mock.mockAuthorizationStatus = .authorizedWhenInUse
        let service = LocationSessionService(locationProvider: mock)

        service.start()
        service.start()
        service.stop()

        #expect(service.isMonitoring)
        #expect(mock.stopUpdatesCalled == 0)

        service.stop()

        #expect(!service.isMonitoring)
        #expect(mock.stopUpdatesCalled == 1)
    }

    @MainActor
    @Test("grid updates after 2 consecutive fixes at same grid")
    func gridDebounce() async {
        let mock = MockLocationProvider()
        mock.mockAuthorizationStatus = .authorizedWhenInUse
        let service = LocationSessionService(locationProvider: mock)
        service.start()

        // FN31 center is approx 41.0, -74.0
        mock.simulateLocation(latitude: 41.0, longitude: -74.0)
        await Task.yield()
        #expect(service.currentGrid == nil)

        mock.simulateLocation(latitude: 41.0, longitude: -74.0)
        await Task.yield()
        #expect(service.currentGrid != nil)
    }

    @MainActor
    @Test("grid does not update on alternating fixes")
    func gridNoUpdateOnAlternating() async {
        let mock = MockLocationProvider()
        mock.mockAuthorizationStatus = .authorizedWhenInUse
        let service = LocationSessionService(locationProvider: mock)
        service.start()

        mock.simulateLocation(latitude: 41.0, longitude: -74.0)
        await Task.yield()
        mock.simulateLocation(latitude: 35.0, longitude: -80.0)
        await Task.yield()
        mock.simulateLocation(latitude: 41.0, longitude: -74.0)
        await Task.yield()

        #expect(service.currentGrid == nil)
    }

    @MainActor
    @Test("forceStop resets reference count")
    func forceStopResetsCount() {
        let mock = MockLocationProvider()
        mock.mockAuthorizationStatus = .authorizedWhenInUse
        let service = LocationSessionService(locationProvider: mock)

        service.start()
        service.start()
        service.forceStop()

        #expect(!service.isMonitoring)
        #expect(mock.stopUpdatesCalled == 1)
    }
}
