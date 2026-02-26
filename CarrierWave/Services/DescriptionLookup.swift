import Foundation

// MARK: - DXCCEntity

nonisolated struct DXCCEntity: Hashable {
    let number: Int
    let name: String
}

// MARK: - DescriptionLookup

nonisolated enum DescriptionLookup {
    // MARK: - Entity Descriptions (Callsign Prefix -> Country)

    static func entityDescription(for prefix: String) -> String {
        let upper = prefix.uppercased()

        // Try exact match first
        if let desc = entityDescriptions[upper] {
            return desc
        }

        // Try progressively shorter prefixes
        for length in stride(from: min(upper.count, 3), through: 1, by: -1) {
            let shortPrefix = String(upper.prefix(length))
            if let desc = entityDescriptions[shortPrefix] {
                return desc
            }
        }

        return "Unknown"
    }

    // MARK: - Band Descriptions

    static func bandDescription(for band: String) -> String {
        let descriptions: [String: String] = [
            "160m": "1.8 MHz",
            "80m": "3.5 MHz",
            "60m": "5 MHz",
            "40m": "7 MHz",
            "30m": "10 MHz",
            "20m": "14 MHz",
            "17m": "18 MHz",
            "15m": "21 MHz",
            "12m": "24 MHz",
            "10m": "28 MHz",
            "6m": "50 MHz",
            "2m": "144 MHz",
            "70cm": "430 MHz",
            "23cm": "1.2 GHz",
        ]
        return descriptions[band.lowercased()] ?? ""
    }

    // MARK: - Mode Descriptions

    static func modeDescription(for mode: String) -> String {
        let descriptions: [String: String] = [
            "SSB": "Single Sideband Voice",
            "LSB": "Lower Sideband Voice",
            "USB": "Upper Sideband Voice",
            "CW": "Continuous Wave (Morse)",
            "FM": "Frequency Modulation Voice",
            "AM": "Amplitude Modulation Voice",
            "FT8": "Digital - FT8",
            "FT4": "Digital - FT4",
            "JS8": "Digital - JS8Call",
            "RTTY": "Radio Teletype",
            "PSK31": "Digital - PSK31",
            "SSTV": "Slow-Scan Television",
            "MFSK": "Multi-Frequency Shift Keying",
            "OLIVIA": "Digital - Olivia",
            "JT65": "Digital - JT65",
            "JT9": "Digital - JT9",
            "WSPR": "Weak Signal Propagation Reporter",
        ]
        return descriptions[mode.uppercased()] ?? ""
    }

    // MARK: - Grid Descriptions

    static func gridDescription(for grid: String) -> String {
        // Grid squares are geographic - could expand to show region names
        // For now, return empty (grid itself is descriptive)
        ""
    }

    // MARK: - Park Descriptions

    static func parkDescription(for parkReference: String) -> String {
        // Park names would come from QSO data or POTA API
        // For now, return empty
        ""
    }
}

// DXCC entity lookup and data are in DescriptionLookup+DXCC.swift
