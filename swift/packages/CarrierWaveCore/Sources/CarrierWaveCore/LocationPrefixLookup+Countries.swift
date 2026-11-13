// Location Prefix Lookup — Country Database
//
// Representative coordinates and primary prefixes for DXCC entities.
// Coordinates are approximate center points from CTY.dat reference data.
// Latitude is positive North, longitude is positive East.

import Foundation

// MARK: - Country Data (Americas)

extension LocationPrefixLookup {
    static let countriesAmericas: [PrefixCountry] = [
        PrefixCountry(id: 291, name: "United States", prefix: "K", latitude: 38.0, longitude: -97.0),
        PrefixCountry(id: 110, name: "Hawaii", prefix: "KH6", latitude: 21.3, longitude: -157.8),
        PrefixCountry(id: 6, name: "Alaska", prefix: "KL7", latitude: 61.2, longitude: -150.0),
        PrefixCountry(id: 202, name: "Puerto Rico", prefix: "KP4", latitude: 18.2, longitude: -66.5),
        PrefixCountry(id: 285, name: "US Virgin Islands", prefix: "KP2", latitude: 17.7, longitude: -64.8),
        PrefixCountry(id: 103, name: "Guam", prefix: "KH2", latitude: 13.4, longitude: 144.8),
        PrefixCountry(id: 9, name: "American Samoa", prefix: "KH8", latitude: -14.3, longitude: -170.7),
        PrefixCountry(id: 166, name: "Mariana Islands", prefix: "KH0", latitude: 15.2, longitude: 145.7),
        PrefixCountry(id: 297, name: "Wake Island", prefix: "KH9", latitude: 19.3, longitude: 166.6),
        PrefixCountry(id: 174, name: "Midway Island", prefix: "KH4", latitude: 28.2, longitude: -177.4),
        PrefixCountry(id: 1, name: "Canada", prefix: "VE", latitude: 45.3, longitude: -75.0),
        PrefixCountry(id: 50, name: "Mexico", prefix: "XE", latitude: 19.4, longitude: -99.1),
        PrefixCountry(id: 62, name: "Brazil", prefix: "PY", latitude: -15.8, longitude: -47.9),
        PrefixCountry(id: 100, name: "Argentina", prefix: "LU", latitude: -34.6, longitude: -58.4),
        PrefixCountry(id: 112, name: "Chile", prefix: "CE", latitude: -33.5, longitude: -70.7),
        PrefixCountry(id: 116, name: "Colombia", prefix: "HK", latitude: 4.6, longitude: -74.1),
        PrefixCountry(id: 120, name: "Ecuador", prefix: "HC", latitude: -0.2, longitude: -78.5),
        PrefixCountry(id: 136, name: "Peru", prefix: "OA", latitude: -12.0, longitude: -77.0),
        PrefixCountry(id: 148, name: "Venezuela", prefix: "YV", latitude: 10.5, longitude: -66.9),
        PrefixCountry(id: 144, name: "Uruguay", prefix: "CX", latitude: -34.9, longitude: -56.2),
        PrefixCountry(id: 132, name: "Paraguay", prefix: "ZP", latitude: -25.3, longitude: -57.6),
        PrefixCountry(id: 104, name: "Bolivia", prefix: "CP", latitude: -16.5, longitude: -68.2),
        PrefixCountry(id: 108, name: "Guyana", prefix: "8R", latitude: 6.8, longitude: -58.2),
        PrefixCountry(id: 140, name: "Suriname", prefix: "PZ", latitude: 5.8, longitude: -55.2),
        PrefixCountry(id: 78, name: "French Guiana", prefix: "FY", latitude: 5.0, longitude: -52.3),
        PrefixCountry(id: 86, name: "Costa Rica", prefix: "TI", latitude: 9.9, longitude: -84.1),
        PrefixCountry(id: 90, name: "Guatemala", prefix: "TG", latitude: 14.6, longitude: -90.5),
        PrefixCountry(id: 92, name: "Honduras", prefix: "HR", latitude: 14.1, longitude: -87.2),
        PrefixCountry(id: 94, name: "Nicaragua", prefix: "YN", latitude: 12.1, longitude: -86.3),
        PrefixCountry(id: 88, name: "El Salvador", prefix: "YS", latitude: 13.7, longitude: -89.2),
        PrefixCountry(id: 80, name: "Panama", prefix: "HP", latitude: 9.0, longitude: -79.5),
        PrefixCountry(id: 82, name: "Belize", prefix: "V3", latitude: 17.3, longitude: -88.8),
        PrefixCountry(id: 84, name: "Cuba", prefix: "CO", latitude: 23.1, longitude: -82.4),
        PrefixCountry(id: 95, name: "Jamaica", prefix: "6Y", latitude: 18.0, longitude: -76.8),
        PrefixCountry(id: 97, name: "Haiti", prefix: "HH", latitude: 18.5, longitude: -72.3),
        PrefixCountry(id: 96, name: "Dominican Republic", prefix: "HI", latitude: 18.5, longitude: -69.9),
        PrefixCountry(id: 99, name: "Bahamas", prefix: "C6", latitude: 25.1, longitude: -77.3),
        PrefixCountry(id: 98, name: "Bermuda", prefix: "VP9", latitude: 32.3, longitude: -64.8),
        PrefixCountry(id: 211, name: "Trinidad & Tobago", prefix: "9Y", latitude: 10.5, longitude: -61.3),
        PrefixCountry(id: 63, name: "Barbados", prefix: "8P", latitude: 13.2, longitude: -59.5),
        PrefixCountry(id: 77, name: "Martinique", prefix: "FM", latitude: 14.6, longitude: -61.0),
        PrefixCountry(id: 79, name: "Guadeloupe", prefix: "FG", latitude: 16.3, longitude: -61.5),
        PrefixCountry(id: 177, name: "Aruba", prefix: "P4", latitude: 12.5, longitude: -70.0),
        PrefixCountry(id: 517, name: "Curacao", prefix: "PJ2", latitude: 12.2, longitude: -68.9),
    ]
}
