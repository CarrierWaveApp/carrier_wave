import CarrierWaveData
import Foundation

// MARK: - POTAClient Grid Lookup

extension POTAClient {
    /// Derive US state from Maidenhead grid square (4 or 6 character)
    /// Returns the most likely state abbreviation for US grid squares.
    /// This is approximate - grid squares can span state boundaries.
    static func gridToUSState(_ grid: String) -> String? {
        guard grid.count >= 4 else {
            return nil
        }

        let field = grid.prefix(2).uppercased()
        let square = String(grid.dropFirst(2).prefix(2))

        // Try specific field+square mapping first
        if let state = specificGridToState(field: field, square: square) {
            return state
        }

        // Fall back to field-level approximation
        return fieldToState(field: field)
    }

    private static func specificGridToState(field: String, square: String) -> String? {
        switch field {
        case "CM",
             "DM": westCoastGridState(field: field, square: square)
        case "CN": pacificNorthwestGridState(square: square)
        case "DN": mountainGridState(square: square)
        case "EM",
             "EL": southernGridState(field: field, square: square)
        case "FN": northeastGridState(square: square)
        default: nil
        }
    }

    private static func westCoastGridState(field: String, square: String) -> String? {
        switch (field, square) {
        // California
        case ("CM", "87"),
             ("CM", "88"),
             ("CM", "97"),
             ("CM", "98"): "CA"
        case ("DM", "03"),
             ("DM", "04"),
             ("DM", "05"),
             ("DM", "06"),
             ("DM", "07"): "CA"
        case ("DM", "12"),
             ("DM", "13"),
             ("DM", "14"): "CA"
        // Arizona
        case ("DM", "31"),
             ("DM", "32"),
             ("DM", "33"): "AZ"
        case ("DM", "41"),
             ("DM", "42"),
             ("DM", "43"): "AZ"
        // Nevada
        case ("DM", "08"),
             ("DM", "09"),
             ("DM", "18"),
             ("DM", "19"): "NV"
        case ("DM", "26"),
             ("DM", "27"): "NV"
        // Colorado (DM squares)
        case ("DM", "69"),
             ("DM", "79"),
             ("DM", "78"): "CO"
        default: nil
        }
    }

    private static func pacificNorthwestGridState(square: String) -> String? {
        switch square {
        // Washington
        case "74",
             "75",
             "84",
             "85",
             "86",
             "87",
             "88": "WA"
        // Oregon
        case "73",
             "82",
             "83",
             "93",
             "94",
             "95": "OR"
        default: nil
        }
    }

    private static func mountainGridState(square: String) -> String? {
        switch square {
        // Colorado
        case "60",
             "70": "CO"
        default: nil
        }
    }

    private static func southernGridState(field: String, square: String) -> String? {
        switch (field, square) {
        // Texas
        case ("EM", "00"),
             ("EM", "01"),
             ("EM", "10"),
             ("EM", "11"): "TX"
        case ("EM", "12"),
             ("EM", "13"),
             ("EM", "20"),
             ("EM", "21"): "TX"
        // Florida
        case ("EL", "87"),
             ("EL", "88"),
             ("EL", "96"),
             ("EL", "97"),
             ("EL", "98"): "FL"
        default: nil
        }
    }

    private static func northeastGridState(square: String) -> String? {
        switch square {
        // New York
        case "10",
             "11",
             "20",
             "21",
             "30",
             "31": "NY"
        default: nil
        }
    }

    private static func fieldToState(field: String) -> String? {
        switch field {
        case "CM",
             "DM": "CA"
        case "CN": "WA"
        case "DN": "CO"
        case "EM": "TX"
        case "EN": "WI"
        case "EL": "FL"
        case "FM": "VA"
        case "FN": "NY"
        default: nil
        }
    }
}
