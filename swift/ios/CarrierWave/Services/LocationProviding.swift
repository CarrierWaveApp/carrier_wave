import CoreLocation

// MARK: - LocationProviding

/// Abstraction over CLLocationManager for testability.
/// Production uses CLLocationManager; tests inject a mock.
protocol LocationProviding: AnyObject {
    var delegate: CLLocationManagerDelegate? { get set }
    var desiredAccuracy: CLLocationAccuracy { get set }
    var authorizationStatus: CLAuthorizationStatus { get }
    func requestWhenInUseAuthorization()
    func startUpdatingLocation()
    func stopUpdatingLocation()
}

// MARK: - CLLocationManager + LocationProviding

extension CLLocationManager: LocationProviding {}
