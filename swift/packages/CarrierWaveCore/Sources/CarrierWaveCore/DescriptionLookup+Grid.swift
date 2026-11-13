//
//  DescriptionLookup+Grid.swift
//  CarrierWaveCore
//
//  Grid field (2-char) to approximate region name lookup.
//  Covers major ham radio population centers. Returns empty string for unknown fields.
//

public extension DescriptionLookup {
    /// Approximate region name for a Maidenhead grid field (first 2 characters).
    /// Coverage: North America, Europe, Japan, Australia, and other active ham regions.
    static func gridFieldDescription(for grid: String) -> String {
        guard grid.count >= 2 else {
            return ""
        }
        let field = String(grid.prefix(2)).uppercased()
        return gridFieldDescriptions[field] ?? ""
    }
}

// MARK: - Grid Field Descriptions

/// Map of 2-character Maidenhead field codes to approximate region names.
/// Only includes fields with significant amateur radio activity.
private let gridFieldDescriptions: [String: String] = [
    // North America
    "CN": "Pacific Northwest",
    "CM": "California",
    "DM": "Southwestern US",
    "DN": "Rocky Mountains",
    "EM": "Central US",
    "EN": "Upper Midwest",
    "EL": "Gulf Coast",
    "FM": "Mid-Atlantic",
    "FN": "Northeastern US / SE Canada",
    "FL": "Southeastern US",
    "DL": "Mexico",
    "DO": "Western Canada",
    "EO": "Central Canada",
    "FO": "Eastern Canada",
    "FP": "Labrador / Newfoundland",

    // Caribbean & Central America
    "FK": "Caribbean",
    "EK": "Central America / Caribbean",

    // South America
    "GG": "Southeastern Brazil",
    "GF": "Southern Brazil / Uruguay",
    "FG": "Northeastern Brazil",
    "FF": "Argentina / Chile",
    "FE": "Southern Argentina",
    "FH": "Northern South America",
    "FI": "Venezuela / Colombia",

    // Europe
    "IO": "United Kingdom / Ireland",
    "IN": "France / Spain",
    "JN": "Central Europe",
    "JO": "Northern Europe / Germany",
    "KO": "Eastern Europe / Scandinavia",
    "KN": "Eastern Europe / Ukraine",
    "KP": "Finland / Northern Scandinavia",
    "JP": "Scandinavia",
    "IM": "Iberian Peninsula",
    "LO": "Russia (Western)",
    "LN": "Russia / Ukraine",

    // Asia
    "PM": "Japan",
    "QM": "Japan (Southern)",
    "OL": "India (Southern)",
    "OM": "India / Southeast Asia",
    "OK": "India (Central)",
    "PL": "Southeast Asia",
    "PK": "Indonesia / Malaysia",
    "NM": "China (Eastern)",
    "NL": "China (Southern)",
    "ON": "China / Mongolia",
    "NN": "China (Central)",

    // Oceania
    "QF": "Southeastern Australia",
    "QG": "Eastern Australia",
    "PF": "Southern Australia",
    "PG": "Western Australia",
    "RF": "New Zealand",
    "RE": "New Zealand (South)",
    "RG": "Pacific Islands",
    "QH": "Papua New Guinea",
    "BL": "Hawaii",

    // Africa
    "JM": "North Africa",
    "KF": "South Africa",
    "KG": "East Africa",
    "KH": "East Africa (North)",
    "JG": "West Africa",
    "JH": "West Africa (North)",
    "JF": "Central Africa",
    "KE": "South Africa (Southern)",

    // Middle East
    "KM": "Middle East",
    "LL": "Middle East / Turkey",
    "LM": "Turkey / Caucasus",

    // Russia / Central Asia
    "MO": "Russia (Central)",
    "NO": "Russia (Siberia)",
    "OO": "Russia (Eastern Siberia)",
    "PO": "Russia (Far East)",
    "MN": "Central Asia",

    // Alaska
    "BP": "Alaska",
    "BO": "Alaska (Western)",
    "AP": "Alaska (Northern)",
]

// swiftlint:enable file_length
