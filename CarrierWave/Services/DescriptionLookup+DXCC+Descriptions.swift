import Foundation

// MARK: - Entity Descriptions (for simple prefix -> country name lookup)

nonisolated extension DescriptionLookup {
    /// Common callsign prefix to country name mappings for entityDescription
    static let entityDescriptions: [String: String] = [
        // USA
        "K": "United States", "W": "United States", "N": "United States", "A": "United States",
        // Europe
        "G": "England", "M": "England",
        "F": "France",
        "DL": "Germany", "DA": "Germany", "DB": "Germany", "DC": "Germany", "DD": "Germany",
        "DF": "Germany", "DG": "Germany", "DH": "Germany", "DI": "Germany", "DJ": "Germany",
        "DK": "Germany", "DM": "Germany", "DO": "Germany", "DP": "Germany", "DQ": "Germany",
        "DR": "Germany",
        "I": "Italy",
        "EA": "Spain", "EB": "Spain", "EC": "Spain", "ED": "Spain", "EE": "Spain",
        "EF": "Spain", "EG": "Spain", "EH": "Spain",
        "PA": "Netherlands", "PB": "Netherlands", "PC": "Netherlands", "PD": "Netherlands",
        "PE": "Netherlands", "PF": "Netherlands", "PG": "Netherlands", "PH": "Netherlands",
        "PI": "Netherlands",
        "ON": "Belgium",
        "OE": "Austria",
        "HB": "Switzerland", "HB9": "Switzerland",
        "SM": "Sweden",
        "LA": "Norway",
        "OZ": "Denmark",
        "OH": "Finland",
        "SP": "Poland",
        "OK": "Czech Republic",
        "OM": "Slovakia",
        "HA": "Hungary",
        "YO": "Romania",
        "LZ": "Bulgaria",
        "SV": "Greece",
        "YU": "Serbia",
        "9A": "Croatia",
        "S5": "Slovenia",
        // UK
        "GW": "Wales", "GM": "Scotland", "GI": "Northern Ireland", "GD": "Isle of Man",
        "GJ": "Jersey", "GU": "Guernsey",
        // Americas
        "VE": "Canada", "VA": "Canada", "VY": "Canada", "VO": "Canada",
        "XE": "Mexico", "XA": "Mexico", "XB": "Mexico", "XC": "Mexico", "XD": "Mexico",
        "XF": "Mexico",
        "LU": "Argentina",
        "PY": "Brazil", "PP": "Brazil", "PQ": "Brazil", "PR": "Brazil", "PS": "Brazil",
        "PT": "Brazil", "PU": "Brazil", "PV": "Brazil", "PW": "Brazil", "PX": "Brazil",
        "CE": "Chile",
        "HK": "Colombia",
        "HC": "Ecuador",
        "OA": "Peru",
        "YV": "Venezuela",
        // Asia/Pacific
        "JA": "Japan", "JD": "Japan", "JE": "Japan", "JF": "Japan", "JG": "Japan",
        "JH": "Japan", "JI": "Japan", "JJ": "Japan", "JK": "Japan", "JL": "Japan",
        "JM": "Japan", "JN": "Japan", "JO": "Japan", "JP": "Japan", "JQ": "Japan",
        "JR": "Japan", "JS": "Japan",
        "HL": "South Korea",
        "BV": "Taiwan",
        "VK": "Australia",
        "ZL": "New Zealand",
        "DU": "Philippines",
        "HS": "Thailand",
        "9M": "Malaysia",
        "9V": "Singapore",
        "YB": "Indonesia",
        "VU": "India",
        // Russia
        "UA": "Russia", "R": "Russia",
        // Africa
        "ZS": "South Africa",
        "SU": "Egypt",
        "CN": "Morocco",
        "EA8": "Canary Islands", "EA9": "Ceuta & Melilla",
        // Caribbean
        "KP4": "Puerto Rico", "KP3": "Puerto Rico", "NP4": "Puerto Rico", "WP4": "Puerto Rico",
        "KP2": "US Virgin Islands",
        "KH6": "Hawaii",
        "KL7": "Alaska",
    ]
}
