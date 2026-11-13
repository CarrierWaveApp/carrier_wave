// Location Prefix Lookup — Asia & Oceania
//
// DXCC entities for Asia and Oceania with representative coordinates and primary prefixes.

import Foundation

extension LocationPrefixLookup {
    static let countriesAsiaOceania: [PrefixCountry] = [
        // East Asia
        PrefixCountry(id: 339, name: "Japan", prefix: "JA", latitude: 35.7, longitude: 139.7),
        PrefixCountry(id: 137, name: "South Korea", prefix: "HL", latitude: 37.6, longitude: 127.0),
        PrefixCountry(id: 386, name: "Taiwan", prefix: "BV", latitude: 25.0, longitude: 121.5),
        PrefixCountry(id: 318, name: "China", prefix: "BY", latitude: 39.9, longitude: 116.4),
        PrefixCountry(id: 375, name: "Hong Kong", prefix: "VR", latitude: 22.3, longitude: 114.2),
        PrefixCountry(id: 152, name: "Macao", prefix: "XX9", latitude: 22.2, longitude: 113.5),
        PrefixCountry(id: 363, name: "Mongolia", prefix: "JT", latitude: 47.9, longitude: 106.9),

        // Southeast Asia
        PrefixCountry(id: 375, name: "Philippines", prefix: "DU", latitude: 14.6, longitude: 121.0),
        PrefixCountry(id: 387, name: "Thailand", prefix: "HS", latitude: 13.8, longitude: 100.5),
        PrefixCountry(id: 299, name: "Vietnam", prefix: "XV", latitude: 21.0, longitude: 105.9),
        PrefixCountry(id: 312, name: "Cambodia", prefix: "XU", latitude: 11.6, longitude: 104.9),
        PrefixCountry(id: 371, name: "Laos", prefix: "XW", latitude: 18.0, longitude: 102.6),
        PrefixCountry(id: 309, name: "Myanmar", prefix: "XZ", latitude: 16.9, longitude: 96.2),
        PrefixCountry(id: 247, name: "Indonesia", prefix: "YB", latitude: -6.2, longitude: 106.8),
        PrefixCountry(id: 305, name: "Malaysia", prefix: "9M", latitude: 3.1, longitude: 101.7),
        PrefixCountry(id: 381, name: "Singapore", prefix: "9V", latitude: 1.3, longitude: 103.8),
        PrefixCountry(id: 345, name: "Brunei", prefix: "V8", latitude: 4.9, longitude: 114.9),

        // South Asia
        PrefixCountry(id: 324, name: "India", prefix: "VU", latitude: 28.6, longitude: 77.2),
        PrefixCountry(id: 315, name: "Sri Lanka", prefix: "4S", latitude: 6.9, longitude: 79.9),
        PrefixCountry(id: 369, name: "Pakistan", prefix: "AP", latitude: 33.7, longitude: 73.1),
        PrefixCountry(id: 348, name: "Bangladesh", prefix: "S2", latitude: 23.7, longitude: 90.4),
        PrefixCountry(id: 366, name: "Nepal", prefix: "9N", latitude: 27.7, longitude: 85.3),
        PrefixCountry(id: 306, name: "Maldives", prefix: "8Q", latitude: 4.2, longitude: 73.5),

        // Central Asia
        PrefixCountry(id: 130, name: "Kazakhstan", prefix: "UN", latitude: 51.2, longitude: 71.4),
        PrefixCountry(id: 291, name: "Uzbekistan", prefix: "UK", latitude: 41.3, longitude: 69.3),
        PrefixCountry(id: 262, name: "Turkmenistan", prefix: "EZ", latitude: 37.9, longitude: 58.4),
        PrefixCountry(id: 135, name: "Kyrgyzstan", prefix: "EX", latitude: 42.9, longitude: 74.6),
        PrefixCountry(id: 386, name: "Tajikistan", prefix: "EY", latitude: 38.6, longitude: 68.8),

        // Middle East
        PrefixCountry(id: 391, name: "Israel", prefix: "4X", latitude: 32.1, longitude: 34.8),
        PrefixCountry(id: 333, name: "Iraq", prefix: "YI", latitude: 33.3, longitude: 44.4),
        PrefixCountry(id: 330, name: "Iran", prefix: "EP", latitude: 35.7, longitude: 51.4),
        PrefixCountry(id: 378, name: "Saudi Arabia", prefix: "HZ", latitude: 24.7, longitude: 46.7),
        PrefixCountry(id: 301, name: "United Arab Emirates", prefix: "A6", latitude: 24.5, longitude: 54.7),
        PrefixCountry(id: 376, name: "Oman", prefix: "A4", latitude: 23.6, longitude: 58.5),
        PrefixCountry(id: 304, name: "Kuwait", prefix: "9K", latitude: 29.4, longitude: 47.9),
        PrefixCountry(id: 384, name: "Qatar", prefix: "A7", latitude: 25.3, longitude: 51.5),
        PrefixCountry(id: 372, name: "Bahrain", prefix: "A9", latitude: 26.2, longitude: 50.6),
        PrefixCountry(id: 293, name: "Yemen", prefix: "7O", latitude: 15.4, longitude: 44.2),
        PrefixCountry(id: 336, name: "Jordan", prefix: "JY", latitude: 31.9, longitude: 35.9),
        PrefixCountry(id: 354, name: "Lebanon", prefix: "OD", latitude: 33.9, longitude: 35.5),
        PrefixCountry(id: 384, name: "Syria", prefix: "YK", latitude: 33.5, longitude: 36.3),

        // Oceania
        PrefixCountry(id: 150, name: "Australia", prefix: "VK", latitude: -33.9, longitude: 151.2),
        PrefixCountry(id: 170, name: "New Zealand", prefix: "ZL", latitude: -41.3, longitude: 174.8),
        PrefixCountry(id: 169, name: "Norfolk Island", prefix: "VK9N", latitude: -29.0, longitude: 168.0),
        PrefixCountry(id: 171, name: "New Caledonia", prefix: "FK", latitude: -22.3, longitude: 166.5),
        PrefixCountry(id: 175, name: "Fiji", prefix: "3D2", latitude: -18.1, longitude: 178.4),
        PrefixCountry(id: 168, name: "Papua New Guinea", prefix: "P2", latitude: -6.0, longitude: 147.0),
        PrefixCountry(id: 160, name: "Tonga", prefix: "A3", latitude: -21.2, longitude: -175.2),
        PrefixCountry(id: 190, name: "Samoa", prefix: "5W", latitude: -13.8, longitude: -171.8),
        PrefixCountry(id: 176, name: "French Polynesia", prefix: "FO", latitude: -17.5, longitude: -149.6),
        PrefixCountry(id: 157, name: "Cook Islands", prefix: "E5", latitude: -21.2, longitude: -159.8),
        PrefixCountry(id: 172, name: "Vanuatu", prefix: "YJ", latitude: -17.7, longitude: 168.3),
        PrefixCountry(id: 185, name: "Solomon Islands", prefix: "H4", latitude: -9.4, longitude: 160.0),
        PrefixCountry(id: 161, name: "Kiribati", prefix: "T3", latitude: 1.5, longitude: 173.0),
        PrefixCountry(id: 158, name: "Nauru", prefix: "C2", latitude: -0.5, longitude: 166.9),
        PrefixCountry(id: 155, name: "Tuvalu", prefix: "T2", latitude: -8.5, longitude: 179.2),
        PrefixCountry(id: 164, name: "Palau", prefix: "T8", latitude: 7.3, longitude: 134.5),
        PrefixCountry(id: 173, name: "Marshall Islands", prefix: "V7", latitude: 7.1, longitude: 171.4),
        PrefixCountry(
            id: 163, name: "Fed. States of Micronesia", prefix: "V6",
            latitude: 6.9, longitude: 158.2
        ),

        // Asiatic Russia
        PrefixCountry(id: 15, name: "Asiatic Russia", prefix: "UA0", latitude: 56.0, longitude: 93.0),
    ]
}
