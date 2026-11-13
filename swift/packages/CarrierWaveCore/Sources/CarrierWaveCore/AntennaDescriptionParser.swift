//
//  AntennaDescriptionParser.swift
//  CarrierWaveCore
//

import Foundation

// MARK: - ParsedAntenna

/// Parsed antenna description from a KiwiSDR receiver
public struct ParsedAntenna: Sendable, Codable, Equatable {
    // MARK: Lifecycle

    public init(
        type: AntennaType?,
        bands: [String],
        directionality: String?,
        modelName: String?,
        rawDescription: String
    ) {
        self.type = type
        self.bands = bands
        self.directionality = directionality
        self.modelName = modelName
        self.rawDescription = rawDescription
    }

    // MARK: Public

    public let type: AntennaType?
    public let bands: [String]
    public let directionality: String?
    public let modelName: String?
    public let rawDescription: String
}

// MARK: - AntennaType

public enum AntennaType: String, Sendable, Codable, CaseIterable {
    case dipole
    case vertical
    case loop
    case yagi
    case logPeriodic
    case whip
    case beverage
    case longwire
    case endFed
    case hexBeam
    case unknown
}

// MARK: - AntennaDescriptionParser

public enum AntennaDescriptionParser {
    // MARK: Public

    /// Parse a KiwiSDR antenna description into structured data
    public static func parse(_ description: String) -> ParsedAntenna {
        let trimmed = description.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return ParsedAntenna(
                type: nil, bands: [], directionality: nil,
                modelName: nil, rawDescription: description
            )
        }

        let lower = trimmed.lowercased()

        // 1. Known model lookup
        if let model = matchKnownModel(lower) {
            let bands = model.bands ?? extractBands(from: lower)
            let direction = model.direction ?? extractDirectionality(from: lower)
            return ParsedAntenna(
                type: model.type, bands: bands, directionality: direction,
                modelName: model.name, rawDescription: description
            )
        }

        // 2. Type keyword extraction
        let type = extractType(from: lower)

        // 3. Band extraction
        let bands = extractBands(from: lower)

        // 4. Directionality
        let direction = extractDirectionality(from: lower)

        return ParsedAntenna(
            type: type, bands: bands, directionality: direction,
            modelName: nil, rawDescription: description
        )
    }

    // MARK: Private

    // MARK: - Known Models

    private struct KnownModel {
        let name: String
        let type: AntennaType
        let bands: [String]?
        let direction: String?
    }

    // MARK: - Band Extraction

    private struct BandRange {
        let name: String
        let low: Double
        let high: Double
    }

    private static let knownModels: [KnownModel] = [
        KnownModel(name: "TCI 530", type: .logPeriodic, bands: nil, direction: "omni"),
        KnownModel(name: "ALA1530", type: .loop, bands: nil, direction: "omni"),
        KnownModel(name: "Mini-Whip", type: .whip, bands: nil, direction: "omni"),
        KnownModel(name: "mini whip", type: .whip, bands: nil, direction: "omni"),
        KnownModel(name: "miniwhip", type: .whip, bands: nil, direction: "omni"),
        KnownModel(name: "W6LVP", type: .loop, bands: nil, direction: "omni"),
        KnownModel(name: "T2FD", type: .dipole, bands: nil, direction: nil),
        KnownModel(name: "Wellbrook", type: .loop, bands: nil, direction: "omni"),
        KnownModel(name: "PA0RDT", type: .whip, bands: nil, direction: "omni"),
    ]

    /// Band frequency ranges in MHz for mapping MHz ranges to band names
    private static let bandRanges: [BandRange] = [
        BandRange(name: "160m", low: 1.8, high: 2.0),
        BandRange(name: "80m", low: 3.5, high: 4.0),
        BandRange(name: "60m", low: 5.3, high: 5.4),
        BandRange(name: "40m", low: 7.0, high: 7.3),
        BandRange(name: "30m", low: 10.1, high: 10.15),
        BandRange(name: "20m", low: 14.0, high: 14.35),
        BandRange(name: "17m", low: 18.068, high: 18.168),
        BandRange(name: "15m", low: 21.0, high: 21.45),
        BandRange(name: "12m", low: 24.89, high: 24.99),
        BandRange(name: "10m", low: 28.0, high: 29.7),
        BandRange(name: "6m", low: 50.0, high: 54.0),
    ]

    private static let bandPattern: NSRegularExpression = {
        do {
            return try NSRegularExpression(
                pattern: #"(?:^|\b)(160|80|60|40|30|20|17|15|12|10|6|2)\s*m(?:eter)?s?\b"#,
                options: .caseInsensitive
            )
        } catch {
            fatalError("Invalid bandPattern regex: \(error)")
        }
    }()

    private static let mhzRangePattern: NSRegularExpression = {
        do {
            return try NSRegularExpression(
                pattern: #"(\d+(?:\.\d+)?)\s*[-–]\s*(\d+(?:\.\d+)?)\s*[Mm][Hh][Zz]"#,
                options: []
            )
        } catch {
            fatalError("Invalid mhzRangePattern regex: \(error)")
        }
    }()

    // MARK: - Directionality

    private static let compassDirections =
        "N|S|E|W|NE|NW|SE|SW|NNE|NNW|SSE|SSW|ENE|ESE|WNW|WSW"

    private static let compassPattern: NSRegularExpression = {
        do {
            return try NSRegularExpression(
                pattern: #"\b("# + compassDirections
                    + #")\s*/\s*("# + compassDirections + #")\b"#,
                options: []
            )
        } catch {
            fatalError("Invalid compassPattern regex: \(error)")
        }
    }()

    private static func matchKnownModel(_ lower: String) -> KnownModel? {
        knownModels.first { lower.contains($0.name.lowercased()) }
    }

    // MARK: - Type Extraction

    private static func extractType(from lower: String) -> AntennaType? {
        // Order matters: check multi-word patterns first
        if lower.contains("log periodic") || lower.contains("lpda")
            || lower.contains("log-periodic")
        {
            return .logPeriodic
        }
        if lower.contains("hex beam") || lower.contains("hexbeam") {
            return .hexBeam
        }
        if lower.contains("end-fed") || lower.contains("end fed") || lower.contains("efhw") {
            return .endFed
        }
        if lower.contains("long wire") || lower.contains("longwire") {
            return .longwire
        }
        if lower.contains("beverage") {
            return .beverage
        }
        if lower.contains("yagi") {
            return .yagi
        }
        if lower.contains("dipole") || lower.contains("inverted-v")
            || lower.contains("inverted v")
        {
            return .dipole
        }
        if lower.contains("vertical") || lower.contains("vert ") || lower.hasPrefix("vert") {
            return .vertical
        }
        if lower.contains("loop") {
            return .loop
        }
        if lower.contains("whip") {
            return .whip
        }
        return nil
    }

    private static func extractBands(from lower: String) -> [String] {
        var bands: [String] = []

        // Match explicit band mentions (e.g., "40m", "80m")
        let nsLower = lower as NSString
        let bandMatches = bandPattern.matches(
            in: lower, range: NSRange(location: 0, length: nsLower.length)
        )
        for match in bandMatches {
            let number = nsLower.substring(with: match.range(at: 1))
            let bandName = "\(number)m"
            if !bands.contains(bandName) {
                bands.append(bandName)
            }
        }

        // Match MHz ranges (e.g., "0.01-30MHz") and convert to band list
        let rangeMatches = mhzRangePattern.matches(
            in: lower, range: NSRange(location: 0, length: nsLower.length)
        )
        for match in rangeMatches where bands.isEmpty {
            let lowStr = nsLower.substring(with: match.range(at: 1))
            let highStr = nsLower.substring(with: match.range(at: 2))
            if let low = Double(lowStr), let high = Double(highStr) {
                let rangeBands = bandsInRange(lowMHz: low, highMHz: high)
                for band in rangeBands where !bands.contains(band) {
                    bands.append(band)
                }
            }
        }

        // Sort by frequency order
        return bands.sorted { lhs, rhs in
            let lIdx = BandUtilities.bandOrder.firstIndex(of: lhs) ?? Int.max
            let rIdx = BandUtilities.bandOrder.firstIndex(of: rhs) ?? Int.max
            return lIdx < rIdx
        }
    }

    private static func bandsInRange(lowMHz: Double, highMHz: Double) -> [String] {
        bandRanges.compactMap { range in
            // Band overlaps if its low end is below the range high and high end is above the range low
            if range.low < highMHz, range.high > lowMHz {
                return range.name
            }
            return nil
        }
    }

    private static func extractDirectionality(from lower: String) -> String? {
        if lower.contains("omni") {
            return "omni"
        }

        // Check compass patterns in original (case-sensitive for compass)
        let nsLower = lower as NSString
        let compassMatches = compassPattern.matches(
            in: lower, range: NSRange(location: 0, length: nsLower.length)
        )
        if let match = compassMatches.first {
            return nsLower.substring(with: match.range)
                .replacingOccurrences(of: " ", with: "")
                .uppercased()
        }

        if lower.contains("broadside") {
            // Check if direction follows broadside
            let parts = lower.components(separatedBy: "broadside")
            if parts.count > 1 {
                let after = parts[1].trimmingCharacters(in: .whitespaces)
                let words = after.components(separatedBy: .whitespaces)
                if let dir = words.first, !dir.isEmpty {
                    let upper = dir.uppercased()
                    if upper.contains("/") {
                        return upper
                    }
                }
            }
        }

        if lower.contains("directional") {
            return "directional"
        }
        return nil
    }
}
