//! Location-based amateur radio prefix lookup. Port of
//! `LocationPrefixLookup.swift` plus its four region tables
//! (`+Africa`, `+AsiaOceania`, `+Countries`, `+Europe`).
//!
//! Per the migration plan, this is the canonical source of the
//! (DXCC number, name, primary prefix, representative coordinate) tuples for
//! the iOS/macOS apps. The Swift side is regenerated from here.

use crate::maidenhead;

#[derive(Debug, Clone, PartialEq)]
pub struct PrefixCountry {
    /// DXCC entity number.
    pub id: u32,
    pub name: &'static str,
    pub prefix: &'static str,
    pub latitude: f64,
    pub longitude: f64,
}

/// Full DXCC table — the union of the four Swift `countriesAmericas` /
/// `countriesAfrica` / `countriesAsiaOceania` / `countriesEurope` arrays.
pub const COUNTRIES: &[PrefixCountry] = &[
    // ---- Americas ----------------------------------------------------------
    PrefixCountry { id: 291, name: "United States", prefix: "K", latitude: 38.0, longitude: -97.0 },
    PrefixCountry { id: 110, name: "Hawaii", prefix: "KH6", latitude: 21.3, longitude: -157.8 },
    PrefixCountry { id: 6, name: "Alaska", prefix: "KL7", latitude: 61.2, longitude: -150.0 },
    PrefixCountry { id: 202, name: "Puerto Rico", prefix: "KP4", latitude: 18.2, longitude: -66.5 },
    PrefixCountry { id: 285, name: "US Virgin Islands", prefix: "KP2", latitude: 17.7, longitude: -64.8 },
    PrefixCountry { id: 103, name: "Guam", prefix: "KH2", latitude: 13.4, longitude: 144.8 },
    PrefixCountry { id: 9, name: "American Samoa", prefix: "KH8", latitude: -14.3, longitude: -170.7 },
    PrefixCountry { id: 166, name: "Mariana Islands", prefix: "KH0", latitude: 15.2, longitude: 145.7 },
    PrefixCountry { id: 297, name: "Wake Island", prefix: "KH9", latitude: 19.3, longitude: 166.6 },
    PrefixCountry { id: 174, name: "Midway Island", prefix: "KH4", latitude: 28.2, longitude: -177.4 },
    PrefixCountry { id: 1, name: "Canada", prefix: "VE", latitude: 45.3, longitude: -75.0 },
    PrefixCountry { id: 50, name: "Mexico", prefix: "XE", latitude: 19.4, longitude: -99.1 },
    PrefixCountry { id: 62, name: "Brazil", prefix: "PY", latitude: -15.8, longitude: -47.9 },
    PrefixCountry { id: 100, name: "Argentina", prefix: "LU", latitude: -34.6, longitude: -58.4 },
    PrefixCountry { id: 112, name: "Chile", prefix: "CE", latitude: -33.5, longitude: -70.7 },
    PrefixCountry { id: 116, name: "Colombia", prefix: "HK", latitude: 4.6, longitude: -74.1 },
    PrefixCountry { id: 120, name: "Ecuador", prefix: "HC", latitude: -0.2, longitude: -78.5 },
    PrefixCountry { id: 136, name: "Peru", prefix: "OA", latitude: -12.0, longitude: -77.0 },
    PrefixCountry { id: 148, name: "Venezuela", prefix: "YV", latitude: 10.5, longitude: -66.9 },
    PrefixCountry { id: 144, name: "Uruguay", prefix: "CX", latitude: -34.9, longitude: -56.2 },
    PrefixCountry { id: 132, name: "Paraguay", prefix: "ZP", latitude: -25.3, longitude: -57.6 },
    PrefixCountry { id: 104, name: "Bolivia", prefix: "CP", latitude: -16.5, longitude: -68.2 },
    PrefixCountry { id: 108, name: "Guyana", prefix: "8R", latitude: 6.8, longitude: -58.2 },
    PrefixCountry { id: 140, name: "Suriname", prefix: "PZ", latitude: 5.8, longitude: -55.2 },
    PrefixCountry { id: 78, name: "French Guiana", prefix: "FY", latitude: 5.0, longitude: -52.3 },
    PrefixCountry { id: 86, name: "Costa Rica", prefix: "TI", latitude: 9.9, longitude: -84.1 },
    PrefixCountry { id: 90, name: "Guatemala", prefix: "TG", latitude: 14.6, longitude: -90.5 },
    PrefixCountry { id: 92, name: "Honduras", prefix: "HR", latitude: 14.1, longitude: -87.2 },
    PrefixCountry { id: 94, name: "Nicaragua", prefix: "YN", latitude: 12.1, longitude: -86.3 },
    PrefixCountry { id: 88, name: "El Salvador", prefix: "YS", latitude: 13.7, longitude: -89.2 },
    PrefixCountry { id: 80, name: "Panama", prefix: "HP", latitude: 9.0, longitude: -79.5 },
    PrefixCountry { id: 82, name: "Belize", prefix: "V3", latitude: 17.3, longitude: -88.8 },
    PrefixCountry { id: 84, name: "Cuba", prefix: "CO", latitude: 23.1, longitude: -82.4 },
    PrefixCountry { id: 95, name: "Jamaica", prefix: "6Y", latitude: 18.0, longitude: -76.8 },
    PrefixCountry { id: 97, name: "Haiti", prefix: "HH", latitude: 18.5, longitude: -72.3 },
    PrefixCountry { id: 96, name: "Dominican Republic", prefix: "HI", latitude: 18.5, longitude: -69.9 },
    PrefixCountry { id: 99, name: "Bahamas", prefix: "C6", latitude: 25.1, longitude: -77.3 },
    PrefixCountry { id: 98, name: "Bermuda", prefix: "VP9", latitude: 32.3, longitude: -64.8 },
    PrefixCountry { id: 211, name: "Trinidad & Tobago", prefix: "9Y", latitude: 10.5, longitude: -61.3 },
    PrefixCountry { id: 63, name: "Barbados", prefix: "8P", latitude: 13.2, longitude: -59.5 },
    PrefixCountry { id: 77, name: "Martinique", prefix: "FM", latitude: 14.6, longitude: -61.0 },
    PrefixCountry { id: 79, name: "Guadeloupe", prefix: "FG", latitude: 16.3, longitude: -61.5 },
    PrefixCountry { id: 177, name: "Aruba", prefix: "P4", latitude: 12.5, longitude: -70.0 },
    PrefixCountry { id: 517, name: "Curacao", prefix: "PJ2", latitude: 12.2, longitude: -68.9 },

    // ---- Europe ------------------------------------------------------------
    PrefixCountry { id: 223, name: "United Kingdom", prefix: "G", latitude: 51.5, longitude: -0.1 },
    PrefixCountry { id: 279, name: "Scotland", prefix: "GM", latitude: 55.9, longitude: -3.2 },
    PrefixCountry { id: 294, name: "Wales", prefix: "GW", latitude: 51.5, longitude: -3.2 },
    PrefixCountry { id: 265, name: "Northern Ireland", prefix: "GI", latitude: 54.6, longitude: -5.9 },
    PrefixCountry { id: 114, name: "Isle of Man", prefix: "GD", latitude: 54.2, longitude: -4.5 },
    PrefixCountry { id: 122, name: "Jersey", prefix: "GJ", latitude: 49.2, longitude: -2.1 },
    PrefixCountry { id: 106, name: "Guernsey", prefix: "GU", latitude: 49.5, longitude: -2.5 },
    PrefixCountry { id: 227, name: "France", prefix: "F", latitude: 48.9, longitude: 2.3 },
    PrefixCountry { id: 230, name: "Germany", prefix: "DL", latitude: 51.2, longitude: 10.5 },
    PrefixCountry { id: 263, name: "Netherlands", prefix: "PA", latitude: 52.4, longitude: 4.9 },
    PrefixCountry { id: 209, name: "Belgium", prefix: "ON", latitude: 50.8, longitude: 4.3 },
    PrefixCountry { id: 254, name: "Luxembourg", prefix: "LX", latitude: 49.6, longitude: 6.1 },
    PrefixCountry { id: 287, name: "Switzerland", prefix: "HB", latitude: 46.9, longitude: 7.4 },
    PrefixCountry { id: 251, name: "Liechtenstein", prefix: "HB0", latitude: 47.1, longitude: 9.5 },
    PrefixCountry { id: 206, name: "Austria", prefix: "OE", latitude: 48.2, longitude: 16.4 },
    PrefixCountry { id: 248, name: "Italy", prefix: "I", latitude: 41.9, longitude: 12.5 },
    PrefixCountry { id: 281, name: "Spain", prefix: "EA", latitude: 40.4, longitude: -3.7 },
    PrefixCountry { id: 272, name: "Portugal", prefix: "CT", latitude: 38.7, longitude: -9.1 },
    PrefixCountry { id: 221, name: "Denmark", prefix: "OZ", latitude: 55.7, longitude: 12.6 },
    PrefixCountry { id: 266, name: "Norway", prefix: "LA", latitude: 59.9, longitude: 10.8 },
    PrefixCountry { id: 284, name: "Sweden", prefix: "SM", latitude: 59.3, longitude: 18.1 },
    PrefixCountry { id: 224, name: "Finland", prefix: "OH", latitude: 60.2, longitude: 24.9 },
    PrefixCountry { id: 5, name: "Aland Islands", prefix: "OH0", latitude: 60.1, longitude: 20.0 },
    PrefixCountry { id: 167, name: "Market Reef", prefix: "OJ0", latitude: 60.3, longitude: 19.1 },
    PrefixCountry { id: 259, name: "Svalbard", prefix: "JW", latitude: 78.2, longitude: 15.6 },
    PrefixCountry { id: 222, name: "Faroe Islands", prefix: "OY", latitude: 62.0, longitude: -6.8 },
    PrefixCountry { id: 237, name: "Greenland", prefix: "OX", latitude: 64.2, longitude: -51.7 },
    PrefixCountry { id: 242, name: "Iceland", prefix: "TF", latitude: 64.1, longitude: -22.0 },
    PrefixCountry { id: 245, name: "Ireland", prefix: "EI", latitude: 53.3, longitude: -6.3 },
    PrefixCountry { id: 239, name: "Greece", prefix: "SV", latitude: 38.0, longitude: 23.7 },
    PrefixCountry { id: 236, name: "Crete", prefix: "SV9", latitude: 35.3, longitude: 24.9 },
    PrefixCountry { id: 180, name: "Dodecanese", prefix: "SV5", latitude: 36.4, longitude: 28.2 },
    PrefixCountry { id: 212, name: "Turkey", prefix: "TA", latitude: 39.9, longitude: 32.9 },
    PrefixCountry { id: 269, name: "Poland", prefix: "SP", latitude: 52.2, longitude: 21.0 },
    PrefixCountry { id: 503, name: "Czech Republic", prefix: "OK", latitude: 50.1, longitude: 14.4 },
    PrefixCountry { id: 504, name: "Slovakia", prefix: "OM", latitude: 48.2, longitude: 17.1 },
    PrefixCountry { id: 239, name: "Hungary", prefix: "HA", latitude: 47.5, longitude: 19.1 },
    PrefixCountry { id: 275, name: "Romania", prefix: "YO", latitude: 44.4, longitude: 26.1 },
    PrefixCountry { id: 212, name: "Bulgaria", prefix: "LZ", latitude: 42.7, longitude: 23.3 },
    PrefixCountry { id: 296, name: "Serbia", prefix: "YU", latitude: 44.8, longitude: 20.5 },
    PrefixCountry { id: 497, name: "Croatia", prefix: "9A", latitude: 45.8, longitude: 16.0 },
    PrefixCountry { id: 499, name: "Slovenia", prefix: "S5", latitude: 46.1, longitude: 14.5 },
    PrefixCountry { id: 501, name: "Bosnia & Herzegovina", prefix: "E7", latitude: 43.9, longitude: 18.4 },
    PrefixCountry { id: 502, name: "North Macedonia", prefix: "Z3", latitude: 42.0, longitude: 21.4 },
    PrefixCountry { id: 514, name: "Montenegro", prefix: "4O", latitude: 42.4, longitude: 19.3 },
    PrefixCountry { id: 522, name: "Kosovo", prefix: "Z6", latitude: 42.7, longitude: 21.2 },
    PrefixCountry { id: 7, name: "Albania", prefix: "ZA", latitude: 41.3, longitude: 19.8 },
    PrefixCountry { id: 225, name: "Cyprus", prefix: "5B", latitude: 35.2, longitude: 33.4 },
    PrefixCountry { id: 257, name: "Malta", prefix: "9H", latitude: 35.9, longitude: 14.5 },
    PrefixCountry { id: 260, name: "Monaco", prefix: "3A", latitude: 43.7, longitude: 7.4 },
    PrefixCountry { id: 278, name: "San Marino", prefix: "T7", latitude: 43.9, longitude: 12.4 },
    PrefixCountry { id: 246, name: "Vatican City", prefix: "HV", latitude: 41.9, longitude: 12.5 },
    PrefixCountry { id: 208, name: "Andorra", prefix: "C3", latitude: 42.5, longitude: 1.5 },
    PrefixCountry { id: 233, name: "Gibraltar", prefix: "ZB", latitude: 36.1, longitude: -5.4 },
    PrefixCountry { id: 256, name: "Canary Islands", prefix: "EA8", latitude: 28.1, longitude: -15.4 },
    PrefixCountry { id: 32, name: "Ceuta & Melilla", prefix: "EA9", latitude: 35.9, longitude: -5.3 },
    PrefixCountry { id: 18, name: "Azores", prefix: "CU", latitude: 38.7, longitude: -27.2 },
    PrefixCountry { id: 256, name: "Madeira", prefix: "CT3", latitude: 32.6, longitude: -16.9 },
    PrefixCountry { id: 52, name: "Sardinia", prefix: "IS", latitude: 39.2, longitude: 9.1 },
    PrefixCountry { id: 15, name: "Corsica", prefix: "TK", latitude: 42.2, longitude: 9.1 },
    PrefixCountry { id: 54, name: "European Russia", prefix: "UA", latitude: 55.8, longitude: 37.6 },
    PrefixCountry { id: 126, name: "Kaliningrad", prefix: "UA2", latitude: 54.7, longitude: 20.5 },
    PrefixCountry { id: 179, name: "Moldova", prefix: "ER", latitude: 47.0, longitude: 28.8 },
    PrefixCountry { id: 288, name: "Ukraine", prefix: "UR", latitude: 50.4, longitude: 30.5 },
    PrefixCountry { id: 27, name: "Belarus", prefix: "EU", latitude: 53.9, longitude: 27.6 },
    PrefixCountry { id: 145, name: "Lithuania", prefix: "LY", latitude: 54.7, longitude: 25.3 },
    PrefixCountry { id: 146, name: "Latvia", prefix: "YL", latitude: 56.9, longitude: 24.1 },
    PrefixCountry { id: 147, name: "Estonia", prefix: "ES", latitude: 59.4, longitude: 24.8 },
    PrefixCountry { id: 75, name: "Georgia", prefix: "4L", latitude: 41.7, longitude: 44.8 },
    PrefixCountry { id: 14, name: "Armenia", prefix: "EK", latitude: 40.2, longitude: 44.5 },
    PrefixCountry { id: 18, name: "Azerbaijan", prefix: "4J", latitude: 40.4, longitude: 49.9 },

    // ---- Asia & Oceania ----------------------------------------------------
    PrefixCountry { id: 339, name: "Japan", prefix: "JA", latitude: 35.7, longitude: 139.7 },
    PrefixCountry { id: 137, name: "South Korea", prefix: "HL", latitude: 37.6, longitude: 127.0 },
    PrefixCountry { id: 386, name: "Taiwan", prefix: "BV", latitude: 25.0, longitude: 121.5 },
    PrefixCountry { id: 318, name: "China", prefix: "BY", latitude: 39.9, longitude: 116.4 },
    PrefixCountry { id: 375, name: "Hong Kong", prefix: "VR", latitude: 22.3, longitude: 114.2 },
    PrefixCountry { id: 152, name: "Macao", prefix: "XX9", latitude: 22.2, longitude: 113.5 },
    PrefixCountry { id: 363, name: "Mongolia", prefix: "JT", latitude: 47.9, longitude: 106.9 },
    PrefixCountry { id: 375, name: "Philippines", prefix: "DU", latitude: 14.6, longitude: 121.0 },
    PrefixCountry { id: 387, name: "Thailand", prefix: "HS", latitude: 13.8, longitude: 100.5 },
    PrefixCountry { id: 299, name: "Vietnam", prefix: "XV", latitude: 21.0, longitude: 105.9 },
    PrefixCountry { id: 312, name: "Cambodia", prefix: "XU", latitude: 11.6, longitude: 104.9 },
    PrefixCountry { id: 371, name: "Laos", prefix: "XW", latitude: 18.0, longitude: 102.6 },
    PrefixCountry { id: 309, name: "Myanmar", prefix: "XZ", latitude: 16.9, longitude: 96.2 },
    PrefixCountry { id: 247, name: "Indonesia", prefix: "YB", latitude: -6.2, longitude: 106.8 },
    PrefixCountry { id: 305, name: "Malaysia", prefix: "9M", latitude: 3.1, longitude: 101.7 },
    PrefixCountry { id: 381, name: "Singapore", prefix: "9V", latitude: 1.3, longitude: 103.8 },
    PrefixCountry { id: 345, name: "Brunei", prefix: "V8", latitude: 4.9, longitude: 114.9 },
    PrefixCountry { id: 324, name: "India", prefix: "VU", latitude: 28.6, longitude: 77.2 },
    PrefixCountry { id: 315, name: "Sri Lanka", prefix: "4S", latitude: 6.9, longitude: 79.9 },
    PrefixCountry { id: 369, name: "Pakistan", prefix: "AP", latitude: 33.7, longitude: 73.1 },
    PrefixCountry { id: 348, name: "Bangladesh", prefix: "S2", latitude: 23.7, longitude: 90.4 },
    PrefixCountry { id: 366, name: "Nepal", prefix: "9N", latitude: 27.7, longitude: 85.3 },
    PrefixCountry { id: 306, name: "Maldives", prefix: "8Q", latitude: 4.2, longitude: 73.5 },
    PrefixCountry { id: 130, name: "Kazakhstan", prefix: "UN", latitude: 51.2, longitude: 71.4 },
    PrefixCountry { id: 291, name: "Uzbekistan", prefix: "UK", latitude: 41.3, longitude: 69.3 },
    PrefixCountry { id: 262, name: "Turkmenistan", prefix: "EZ", latitude: 37.9, longitude: 58.4 },
    PrefixCountry { id: 135, name: "Kyrgyzstan", prefix: "EX", latitude: 42.9, longitude: 74.6 },
    PrefixCountry { id: 386, name: "Tajikistan", prefix: "EY", latitude: 38.6, longitude: 68.8 },
    PrefixCountry { id: 391, name: "Israel", prefix: "4X", latitude: 32.1, longitude: 34.8 },
    PrefixCountry { id: 333, name: "Iraq", prefix: "YI", latitude: 33.3, longitude: 44.4 },
    PrefixCountry { id: 330, name: "Iran", prefix: "EP", latitude: 35.7, longitude: 51.4 },
    PrefixCountry { id: 378, name: "Saudi Arabia", prefix: "HZ", latitude: 24.7, longitude: 46.7 },
    PrefixCountry { id: 301, name: "United Arab Emirates", prefix: "A6", latitude: 24.5, longitude: 54.7 },
    PrefixCountry { id: 376, name: "Oman", prefix: "A4", latitude: 23.6, longitude: 58.5 },
    PrefixCountry { id: 304, name: "Kuwait", prefix: "9K", latitude: 29.4, longitude: 47.9 },
    PrefixCountry { id: 384, name: "Qatar", prefix: "A7", latitude: 25.3, longitude: 51.5 },
    PrefixCountry { id: 372, name: "Bahrain", prefix: "A9", latitude: 26.2, longitude: 50.6 },
    PrefixCountry { id: 293, name: "Yemen", prefix: "7O", latitude: 15.4, longitude: 44.2 },
    PrefixCountry { id: 336, name: "Jordan", prefix: "JY", latitude: 31.9, longitude: 35.9 },
    PrefixCountry { id: 354, name: "Lebanon", prefix: "OD", latitude: 33.9, longitude: 35.5 },
    PrefixCountry { id: 384, name: "Syria", prefix: "YK", latitude: 33.5, longitude: 36.3 },
    PrefixCountry { id: 150, name: "Australia", prefix: "VK", latitude: -33.9, longitude: 151.2 },
    PrefixCountry { id: 170, name: "New Zealand", prefix: "ZL", latitude: -41.3, longitude: 174.8 },
    PrefixCountry { id: 169, name: "Norfolk Island", prefix: "VK9N", latitude: -29.0, longitude: 168.0 },
    PrefixCountry { id: 171, name: "New Caledonia", prefix: "FK", latitude: -22.3, longitude: 166.5 },
    PrefixCountry { id: 175, name: "Fiji", prefix: "3D2", latitude: -18.1, longitude: 178.4 },
    PrefixCountry { id: 168, name: "Papua New Guinea", prefix: "P2", latitude: -6.0, longitude: 147.0 },
    PrefixCountry { id: 160, name: "Tonga", prefix: "A3", latitude: -21.2, longitude: -175.2 },
    PrefixCountry { id: 190, name: "Samoa", prefix: "5W", latitude: -13.8, longitude: -171.8 },
    PrefixCountry { id: 176, name: "French Polynesia", prefix: "FO", latitude: -17.5, longitude: -149.6 },
    PrefixCountry { id: 157, name: "Cook Islands", prefix: "E5", latitude: -21.2, longitude: -159.8 },
    PrefixCountry { id: 172, name: "Vanuatu", prefix: "YJ", latitude: -17.7, longitude: 168.3 },
    PrefixCountry { id: 185, name: "Solomon Islands", prefix: "H4", latitude: -9.4, longitude: 160.0 },
    PrefixCountry { id: 161, name: "Kiribati", prefix: "T3", latitude: 1.5, longitude: 173.0 },
    PrefixCountry { id: 158, name: "Nauru", prefix: "C2", latitude: -0.5, longitude: 166.9 },
    PrefixCountry { id: 155, name: "Tuvalu", prefix: "T2", latitude: -8.5, longitude: 179.2 },
    PrefixCountry { id: 164, name: "Palau", prefix: "T8", latitude: 7.3, longitude: 134.5 },
    PrefixCountry { id: 173, name: "Marshall Islands", prefix: "V7", latitude: 7.1, longitude: 171.4 },
    PrefixCountry { id: 163, name: "Fed. States of Micronesia", prefix: "V6", latitude: 6.9, longitude: 158.2 },
    PrefixCountry { id: 15, name: "Asiatic Russia", prefix: "UA0", latitude: 56.0, longitude: 93.0 },

    // ---- Africa ------------------------------------------------------------
    PrefixCountry { id: 478, name: "South Africa", prefix: "ZS", latitude: -33.9, longitude: 18.4 },
    PrefixCountry { id: 474, name: "Egypt", prefix: "SU", latitude: 30.0, longitude: 31.2 },
    PrefixCountry { id: 446, name: "Morocco", prefix: "CN", latitude: 33.6, longitude: -7.6 },
    PrefixCountry { id: 400, name: "Algeria", prefix: "7X", latitude: 36.8, longitude: 3.0 },
    PrefixCountry { id: 474, name: "Tunisia", prefix: "3V", latitude: 36.8, longitude: 10.2 },
    PrefixCountry { id: 436, name: "Libya", prefix: "5A", latitude: 32.9, longitude: 13.2 },
    PrefixCountry { id: 468, name: "Nigeria", prefix: "5N", latitude: 9.1, longitude: 7.5 },
    PrefixCountry { id: 434, name: "Kenya", prefix: "5Z", latitude: -1.3, longitude: 36.8 },
    PrefixCountry { id: 482, name: "Tanzania", prefix: "5H", latitude: -6.8, longitude: 39.3 },
    PrefixCountry { id: 488, name: "Uganda", prefix: "5X", latitude: 0.3, longitude: 32.6 },
    PrefixCountry { id: 414, name: "Ethiopia", prefix: "ET", latitude: 9.0, longitude: 38.7 },
    PrefixCountry { id: 432, name: "Ghana", prefix: "9G", latitude: 5.6, longitude: -0.2 },
    PrefixCountry { id: 456, name: "Senegal", prefix: "6W", latitude: 14.7, longitude: -17.5 },
    PrefixCountry { id: 412, name: "Ivory Coast", prefix: "TU", latitude: 5.3, longitude: -4.0 },
    PrefixCountry { id: 450, name: "Cameroon", prefix: "TJ", latitude: 3.9, longitude: 11.5 },
    PrefixCountry { id: 406, name: "Congo (DRC)", prefix: "9Q", latitude: -4.3, longitude: 15.3 },
    PrefixCountry { id: 404, name: "Congo (Republic)", prefix: "TN", latitude: -4.3, longitude: 15.3 },
    PrefixCountry { id: 438, name: "Angola", prefix: "D2", latitude: -8.8, longitude: 13.2 },
    PrefixCountry { id: 462, name: "Mozambique", prefix: "C9", latitude: -25.9, longitude: 32.6 },
    PrefixCountry { id: 452, name: "Zimbabwe", prefix: "Z2", latitude: -17.8, longitude: 31.1 },
    PrefixCountry { id: 490, name: "Zambia", prefix: "9J", latitude: -15.4, longitude: 28.3 },
    PrefixCountry { id: 430, name: "Malawi", prefix: "7Q", latitude: -13.9, longitude: 33.8 },
    PrefixCountry { id: 440, name: "Madagascar", prefix: "5R", latitude: -18.9, longitude: 47.5 },
    PrefixCountry { id: 460, name: "Mauritius", prefix: "3B8", latitude: -20.2, longitude: 57.5 },
    PrefixCountry { id: 453, name: "Reunion", prefix: "FR", latitude: -21.1, longitude: 55.5 },
    PrefixCountry { id: 444, name: "Namibia", prefix: "V5", latitude: -22.6, longitude: 17.1 },
    PrefixCountry { id: 466, name: "Botswana", prefix: "A2", latitude: -24.7, longitude: 25.9 },
    PrefixCountry { id: 411, name: "Lesotho", prefix: "7P", latitude: -29.3, longitude: 28.5 },
    PrefixCountry { id: 413, name: "Eswatini", prefix: "3DA", latitude: -26.3, longitude: 31.1 },
    PrefixCountry { id: 486, name: "Sudan", prefix: "ST", latitude: 15.6, longitude: 32.5 },
    PrefixCountry { id: 521, name: "South Sudan", prefix: "Z8", latitude: 4.9, longitude: 31.6 },
    PrefixCountry { id: 470, name: "Somalia", prefix: "6O", latitude: 2.0, longitude: 45.3 },
    PrefixCountry { id: 416, name: "Eritrea", prefix: "E3", latitude: 15.3, longitude: 38.9 },
    PrefixCountry { id: 410, name: "Djibouti", prefix: "J2", latitude: 11.6, longitude: 43.1 },
    PrefixCountry { id: 409, name: "Cape Verde", prefix: "D4", latitude: 15.0, longitude: -23.6 },
    PrefixCountry { id: 424, name: "Seychelles", prefix: "S7", latitude: -4.6, longitude: 55.5 },
    PrefixCountry { id: 219, name: "Canary Islands", prefix: "EA8", latitude: 28.1, longitude: -15.4 },
];

/// Haversine distance in kilometers between two coordinates.
fn haversine_km(lat1: f64, lon1: f64, lat2: f64, lon2: f64) -> f64 {
    use std::f64::consts::PI;
    const EARTH_RADIUS_KM: f64 = 6_371.0;
    let d_lat = (lat2 - lat1) * PI / 180.0;
    let d_lon = (lon2 - lon1) * PI / 180.0;
    let rad_lat1 = lat1 * PI / 180.0;
    let rad_lat2 = lat2 * PI / 180.0;
    let s_lat = (d_lat / 2.0).sin();
    let s_lon = (d_lon / 2.0).sin();
    let a = s_lat * s_lat + rad_lat1.cos() * rad_lat2.cos() * s_lon * s_lon;
    let c = 2.0 * a.sqrt().atan2((1.0 - a).sqrt());
    EARTH_RADIUS_KM * c
}

/// Find the DXCC entity closest to the given coordinate (nearest-neighbor
/// over `COUNTRIES`). Returns `None` only if the table is empty (it isn't).
pub fn nearest(latitude: f64, longitude: f64) -> Option<&'static PrefixCountry> {
    COUNTRIES
        .iter()
        .min_by(|a, b| {
            let da = haversine_km(latitude, longitude, a.latitude, a.longitude);
            let db = haversine_km(latitude, longitude, b.latitude, b.longitude);
            da.partial_cmp(&db).unwrap_or(std::cmp::Ordering::Equal)
        })
}

/// Find the DXCC entity closest to the center of a Maidenhead grid.
pub fn nearest_for_grid(grid: &str) -> Option<&'static PrefixCountry> {
    let coord = maidenhead::coordinate_from_grid(grid)?;
    nearest(coord.latitude, coord.longitude)
}

/// Resolve a callsign to its DXCC entity via longest-prefix match against the
/// primary-prefix table. Mirrors the Swift `entity(forCallsign:)` minus the
/// `prefixesByEntity` extended-prefix lookup — that table comes from the
/// description lookup (not yet ported) and the iOS shim can layer it on top
/// using the same per-entity prefix list later.
pub fn entity_for_callsign(callsign: &str) -> Option<&'static PrefixCountry> {
    let upper = callsign.to_uppercase();
    let base = if upper.contains('/') {
        upper
            .split('/')
            .max_by_key(|seg| seg.len())
            .unwrap_or(&upper)
            .to_string()
    } else {
        upper.clone()
    };
    let mut best: Option<&PrefixCountry> = None;
    let mut best_len = 0usize;
    for country in COUNTRIES {
        if base.starts_with(country.prefix) && country.prefix.len() > best_len {
            best = Some(country);
            best_len = country.prefix.len();
        }
    }
    best
}

/// Filter countries by name (substring, case-insensitive) or by prefix
/// (case-insensitive prefix match). Empty query returns all countries.
pub fn search(query: &str) -> Vec<&'static PrefixCountry> {
    if query.is_empty() {
        return COUNTRIES.iter().collect();
    }
    let upper = query.to_uppercase();
    let lower = query.to_lowercase();
    COUNTRIES
        .iter()
        .filter(|c| {
            c.name.to_lowercase().contains(&lower)
                || c.prefix.to_uppercase().starts_with(&upper)
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn nearest_picks_closest_country() {
        // ~SF Bay Area
        let c = nearest(37.7, -122.4).unwrap();
        assert_eq!(c.name, "United States");
    }

    #[test]
    fn nearest_for_london_grid() {
        let c = nearest_for_grid("IO91").unwrap();
        assert_eq!(c.name, "United Kingdom");
    }

    #[test]
    fn entity_for_callsign_longest_primary_prefix() {
        // `entity_for_callsign` matches against the primary-prefix column of
        // the COUNTRIES table — not the full extended-prefix lookup Swift's
        // DescriptionLookup carries. So a US callsign like "W6JY" wouldn't
        // resolve here (W isn't the primary prefix for entity 291); use
        // primary-prefix-aligned inputs instead.
        let c = entity_for_callsign("KH6XYZ").unwrap();
        assert_eq!(c.name, "Hawaii");
        let c = entity_for_callsign("VE3XYZ").unwrap();
        assert_eq!(c.name, "Canada");
    }

    #[test]
    fn entity_for_portable_picks_longest_segment() {
        // "VE3/KH6FOO" — longest segment is "KH6FOO" (6 chars) — matches Hawaii.
        let c = entity_for_callsign("VE3/KH6FOO").unwrap();
        assert_eq!(c.prefix, "KH6");
    }

    #[test]
    fn entity_for_unmatchable_returns_none() {
        // "W6JY" starts with W which isn't a primary prefix in the table.
        assert!(entity_for_callsign("W6JY").is_none());
    }

    #[test]
    fn search_filters_by_name_or_prefix() {
        let by_name = search("Japan");
        assert!(by_name.iter().any(|c| c.name == "Japan"));

        let by_prefix = search("kh6");
        assert!(by_prefix.iter().any(|c| c.prefix == "KH6"));

        let empty = search("");
        assert_eq!(empty.len(), COUNTRIES.len());
    }
}
