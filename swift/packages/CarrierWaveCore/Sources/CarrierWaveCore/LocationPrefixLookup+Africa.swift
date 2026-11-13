// Location Prefix Lookup — Africa & Combined List
//
// DXCC entities for Africa with representative coordinates and primary prefixes,
// plus the combined country list used by the lookup engine.

import Foundation

// MARK: - Country Data (Africa)

extension LocationPrefixLookup {
    static let countriesAfrica: [PrefixCountry] = [
        PrefixCountry(id: 478, name: "South Africa", prefix: "ZS", latitude: -33.9, longitude: 18.4),
        PrefixCountry(id: 474, name: "Egypt", prefix: "SU", latitude: 30.0, longitude: 31.2),
        PrefixCountry(id: 446, name: "Morocco", prefix: "CN", latitude: 33.6, longitude: -7.6),
        PrefixCountry(id: 400, name: "Algeria", prefix: "7X", latitude: 36.8, longitude: 3.0),
        PrefixCountry(id: 474, name: "Tunisia", prefix: "3V", latitude: 36.8, longitude: 10.2),
        PrefixCountry(id: 436, name: "Libya", prefix: "5A", latitude: 32.9, longitude: 13.2),
        PrefixCountry(id: 468, name: "Nigeria", prefix: "5N", latitude: 9.1, longitude: 7.5),
        PrefixCountry(id: 434, name: "Kenya", prefix: "5Z", latitude: -1.3, longitude: 36.8),
        PrefixCountry(id: 482, name: "Tanzania", prefix: "5H", latitude: -6.8, longitude: 39.3),
        PrefixCountry(id: 488, name: "Uganda", prefix: "5X", latitude: 0.3, longitude: 32.6),
        PrefixCountry(id: 414, name: "Ethiopia", prefix: "ET", latitude: 9.0, longitude: 38.7),
        PrefixCountry(id: 432, name: "Ghana", prefix: "9G", latitude: 5.6, longitude: -0.2),
        PrefixCountry(id: 456, name: "Senegal", prefix: "6W", latitude: 14.7, longitude: -17.5),
        PrefixCountry(id: 412, name: "Ivory Coast", prefix: "TU", latitude: 5.3, longitude: -4.0),
        PrefixCountry(id: 450, name: "Cameroon", prefix: "TJ", latitude: 3.9, longitude: 11.5),
        PrefixCountry(id: 406, name: "Congo (DRC)", prefix: "9Q", latitude: -4.3, longitude: 15.3),
        PrefixCountry(id: 404, name: "Congo (Republic)", prefix: "TN", latitude: -4.3, longitude: 15.3),
        PrefixCountry(id: 438, name: "Angola", prefix: "D2", latitude: -8.8, longitude: 13.2),
        PrefixCountry(id: 462, name: "Mozambique", prefix: "C9", latitude: -25.9, longitude: 32.6),
        PrefixCountry(id: 452, name: "Zimbabwe", prefix: "Z2", latitude: -17.8, longitude: 31.1),
        PrefixCountry(id: 490, name: "Zambia", prefix: "9J", latitude: -15.4, longitude: 28.3),
        PrefixCountry(id: 430, name: "Malawi", prefix: "7Q", latitude: -13.9, longitude: 33.8),
        PrefixCountry(id: 440, name: "Madagascar", prefix: "5R", latitude: -18.9, longitude: 47.5),
        PrefixCountry(id: 460, name: "Mauritius", prefix: "3B8", latitude: -20.2, longitude: 57.5),
        PrefixCountry(id: 453, name: "Reunion", prefix: "FR", latitude: -21.1, longitude: 55.5),
        PrefixCountry(id: 444, name: "Namibia", prefix: "V5", latitude: -22.6, longitude: 17.1),
        PrefixCountry(id: 466, name: "Botswana", prefix: "A2", latitude: -24.7, longitude: 25.9),
        PrefixCountry(id: 411, name: "Lesotho", prefix: "7P", latitude: -29.3, longitude: 28.5),
        PrefixCountry(id: 413, name: "Eswatini", prefix: "3DA", latitude: -26.3, longitude: 31.1),
        PrefixCountry(id: 486, name: "Sudan", prefix: "ST", latitude: 15.6, longitude: 32.5),
        PrefixCountry(id: 521, name: "South Sudan", prefix: "Z8", latitude: 4.9, longitude: 31.6),
        PrefixCountry(id: 470, name: "Somalia", prefix: "6O", latitude: 2.0, longitude: 45.3),
        PrefixCountry(id: 416, name: "Eritrea", prefix: "E3", latitude: 15.3, longitude: 38.9),
        PrefixCountry(id: 410, name: "Djibouti", prefix: "J2", latitude: 11.6, longitude: 43.1),

        // Atlantic / Indian Ocean Islands
        PrefixCountry(id: 409, name: "Cape Verde", prefix: "D4", latitude: 15.0, longitude: -23.6),
        PrefixCountry(id: 424, name: "Seychelles", prefix: "S7", latitude: -4.6, longitude: 55.5),
        PrefixCountry(id: 219, name: "Canary Islands", prefix: "EA8", latitude: 28.1, longitude: -15.4),
    ]
}

// MARK: - Combined Country List

extension LocationPrefixLookup {
    /// All DXCC entities with prefix and coordinates, assembled from regional lists.
    static let countries: [PrefixCountry] =
        countriesAmericas
            + countriesEurope
            + countriesAsiaOceania
            + countriesAfrica
}
