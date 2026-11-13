import CarrierWaveData
import Foundation

// MARK: - VimFilterResult

struct VimFilterResult: Equatable {
    var modeFilter: String?
    var bandFilter: String?
    var sourceFilter: String?
    var neededOnly: Bool = false
    var dupeOnly: Bool = false
    var neededOnBand: String?
    var neededOnMode: String?
    var callsignPrefix: String?

    var isEmpty: Bool {
        modeFilter == nil && bandFilter == nil && sourceFilter == nil
            && !neededOnly && !dupeOnly && neededOnBand == nil
            && neededOnMode == nil && callsignPrefix == nil
    }

    func matches(_ spot: EnrichedSpot) -> Bool {
        if let mode = modeFilter, spot.spot.mode.uppercased() != mode {
            return false
        }
        if let band = bandFilter, spot.spot.band.uppercased() != band {
            return false
        }
        if let source = sourceFilter, spot.spot.source.rawValue.uppercased() != source {
            return false
        }
        if let prefix = callsignPrefix, !spot.spot.callsign.uppercased().hasPrefix(prefix) {
            return false
        }
        return true
    }
}

// MARK: - VimFilterParser

enum VimFilterParser {
    // MARK: Internal

    static func parse(_ input: String) -> VimFilterResult {
        var result = VimFilterResult()
        let tokens = input.split(separator: " ").map(String.init)

        for token in tokens {
            let upper = token.uppercased()

            // Explicit prefix syntax
            if let colonIndex = token.firstIndex(of: ":") {
                let prefix = String(token[token.startIndex ..< colonIndex]).lowercased()
                let value = String(token[token.index(after: colonIndex)...]).uppercased()
                switch prefix {
                case "mode": result.modeFilter = value
                case "band": result.bandFilter = value
                case "src": result.sourceFilter = value
                case "call": result.callsignPrefix = value
                case "need":
                    if bandNames.contains(value) {
                        result.neededOnBand = value
                    } else if modeNames.contains(value) {
                        result.neededOnMode = value
                    }
                default: break
                }
                continue
            }

            // Keywords (matched in priority order)
            if upper == "NEW" {
                result.neededOnly = true
            } else if upper == "DUPE" {
                result.dupeOnly = true
            } else if modeNames.contains(upper) {
                result.modeFilter = upper
            } else if bandNames.contains(upper) {
                result.bandFilter = upper
            } else if sourceNames.contains(upper) {
                result.sourceFilter = upper
            } else {
                // Unrecognized — treat as callsign prefix
                result.callsignPrefix = upper
            }
        }

        return result
    }

    // MARK: Private

    /// Known keywords
    private static let modeNames: Set<String> = [
        "CW", "SSB", "USB", "LSB", "FM", "AM", "FT8", "FT4",
        "RTTY", "JTTY", "PSK31", "JS8", "DIGITAL",
    ]

    private static let bandNames: Set<String> = [
        "160M", "80M", "60M", "40M", "30M", "20M", "17M",
        "15M", "12M", "10M", "6M", "2M", "70CM",
    ]

    private static let sourceNames: Set<String> = [
        "POTA", "SOTA", "WWFF", "RBN", "CLUSTER", "DXSUMMIT", "DXHEAT",
    ]
}
