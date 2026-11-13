import CarrierWaveData
import Foundation

// MARK: - ContestEnrichmentService

/// Derives mode/band/exchange/category/popularity metadata for a contest
/// from the WA7BNM RSS description and title.
///
/// The WA7BNM description is HTML-ish but roughly follows this shape:
///
///     Starts: 2200Z, Feb 27 to 2200Z, Mar 1
///     Mode: CW
///     Bands: 160, 80, 40, 20, 15, 10m
///     Exchange: RST + CQ Zone
///     Work stations: Once per band
///
/// We pattern-match each line. Everything here is best-effort; when a field
/// is missing the enrichment field stays empty and the UI falls back
/// gracefully.
nonisolated enum ContestEnrichmentService {
    // MARK: Internal

    /// Parse the RSS description and enrich against the title.
    /// `templateIds` is the list of template IDs shipped with the app —
    /// used for "Log now" matching. Pass `[]` to skip template matching.
    static func enrich(
        title: String,
        description: String,
        templateIds: [String] = []
    ) -> ContestEnrichment {
        let stripped = stripHTML(description)
        var enr = ContestEnrichment()

        enr.modes = parseModes(from: stripped, title: title)
        let (bands, summary) = parseBands(from: stripped, title: title)
        enr.bands = bands
        enr.bandSummary = summary
        enr.exchangePreview = parseExchange(from: stripped)
        enr.category = inferCategory(title: title, modes: enr.modes, bands: bands)
        enr.popularity = popularityTier(for: title)
        enr.matchedTemplateId = matchTemplate(
            title: title, in: templateIds
        )
        return enr
    }

    // MARK: Private

    private static let modeTokens: [(regex: String, mode: String)] = [
        (#"(?i)\bCW\b"#, "CW"),
        (#"(?i)\b(?:SSB|Phone)\b"#, "SSB"),
        (#"(?i)\bRTTY\b"#, "RTTY"),
        (#"(?i)\bFT8\b"#, "FT8"),
        (#"(?i)\bFT4\b"#, "FT4"),
        (#"(?i)\bPSK(?:31|63)?\b"#, "PSK"),
        (#"(?i)\bDigital\b"#, "Digital"),
        (#"(?i)\bMixed\b"#, "Mixed"),
    ]

    private static let vhfBandRegex = #"(?i)(?:6 ?m|2 ?m|70 ?cm|VHF|UHF|microwave)"#

    /// Known-major contest popularity tiers, matched against the title
    /// substring (case-insensitive).
    private static let popularityTiers: [(needle: String, tier: Int)] = [
        ("CQ WW DX", 5),
        ("CQ WPX", 5),
        ("ARRL DX", 5),
        ("ARRL Sweepstakes", 5),
        ("Sweepstakes", 5),
        ("IARU HF", 4),
        ("CQ WW RTTY", 4),
        ("ARRL Field Day", 5),
        ("Field Day", 4),
        ("NAQP", 4),
        ("North American QSO Party", 4),
        ("WAE", 4),
        ("All Asian", 3),
        ("Russian DX", 3),
        ("CQMM DX", 2),
        ("Holyland", 2),
        ("State Parks on the Air", 2),
        ("Provinces of China", 2),
    ]

    private static let templateIdAliases: [String: [String]] = [
        "cq-ww-cw": ["cq ww dx cw", "cq world wide dx cw"],
        "cq-ww-ssb": ["cq ww dx ssb", "cq ww dx phone", "cq world wide dx ssb"],
        "arrl-dx-dx": ["arrl dx"],
        "arrl-dx-w-ve": ["arrl dx"],
        "arrl-sweepstakes-cw": ["arrl sweepstakes cw", "sweepstakes cw"],
        "arrl-field-day": ["arrl field day", "field day"],
        "naqp-cw": ["naqp cw", "north american qso party cw"],
        "state-qso-party": [],
    ]

    // MARK: - HTML stripping

    private static func stripHTML(_ raw: String) -> String {
        var result = raw
        // WA7BNM descriptions use <br> and <br/> liberally as line separators.
        let breakPatterns = ["<br/>", "<br />", "<br>", "<BR/>", "<BR>"]
        for pattern in breakPatterns {
            result = result.replacingOccurrences(of: pattern, with: "\n")
        }
        // Strip any remaining tags.
        result = result.replacingOccurrences(
            of: "<[^>]+>",
            with: "",
            options: .regularExpression
        )
        // Decode a minimal set of entities.
        result = result
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
        return result
    }

    // MARK: - Mode parsing

    private static func parseModes(from text: String, title: String) -> [String] {
        let haystack = "\(title)\n\(text)"
        guard let modeLine = line(
            prefixed: "Mode", in: text
        ) ?? line(prefixed: "Modes", in: text) else {
            // Fall back to scanning whole blob.
            return uniqueMatches(from: haystack)
        }
        let matches = uniqueMatches(from: modeLine)
        return matches.isEmpty ? uniqueMatches(from: haystack) : matches
    }

    private static func uniqueMatches(from text: String) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for (pattern, mode) in modeTokens where text.range(
            of: pattern, options: .regularExpression
        ) != nil {
            if seen.insert(mode).inserted {
                result.append(mode)
            }
        }
        return result
    }

    // MARK: - Band parsing

    private static func parseBands(
        from text: String,
        title: String
    ) -> (bands: [String], summary: String?) {
        let haystack = "\(title)\n\(text)"
        if haystack.range(of: vhfBandRegex, options: .regularExpression) != nil,
           haystack.range(of: #"(?i)\b(?:80|40|20|15|10)m?\b"#, options: .regularExpression) == nil
        {
            return ([], "VHF+")
        }
        guard let bandLine = line(prefixed: "Bands", in: text) ?? line(prefixed: "Band", in: text) else {
            return ([], nil)
        }
        // "All HF", "HF only", etc.
        if bandLine.range(of: #"(?i)all\s*hf"#, options: .regularExpression) != nil {
            return ([], "All HF")
        }
        // Pull out numeric band tokens in descending wavelength.
        let pattern = #"(?i)\b(160|80|60|40|30|20|17|15|12|10|6|2)\s*m?\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return ([], nil)
        }
        let range = NSRange(bandLine.startIndex..., in: bandLine)
        let matches = regex.matches(in: bandLine, range: range)
        var seen = Set<String>()
        var result: [String] = []
        for match in matches {
            guard match.numberOfRanges > 1,
                  let swiftRange = Range(match.range(at: 1), in: bandLine)
            else {
                continue
            }
            let token = "\(bandLine[swiftRange])m"
            if seen.insert(token).inserted {
                result.append(token)
            }
        }
        return (result, nil)
    }

    // MARK: - Exchange parsing

    private static func parseExchange(from text: String) -> String? {
        guard let raw = line(prefixed: "Exchange", in: text) else {
            return nil
        }
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            return nil
        }
        // Take only the first sentence/clause for compactness.
        if let firstSentence = trimmed.split(
            separator: ".",
            maxSplits: 1,
            omittingEmptySubsequences: true
        ).first {
            return String(firstSentence).trimmingCharacters(in: .whitespaces)
        }
        return trimmed
    }

    // MARK: - Category inference

    private static func inferCategory(
        title: String,
        modes: [String],
        bands _: [String]
    ) -> ContestCategory {
        let lowered = title.lowercased()
        if lowered.contains("field day") {
            return .fieldDay
        }
        if lowered.contains("sprint") {
            return .sprint
        }
        if lowered.contains("state qso party")
            || lowered.contains("qso party")
        {
            return .qsoParty
        }
        if lowered.contains("vhf") || lowered.contains("6m")
            || lowered.contains(" 2m")
        {
            return .vhf
        }
        if lowered.contains("digital") || lowered.contains("rtty")
            || lowered.contains("ft8") || lowered.contains("ft4")
        {
            return .digital
        }
        if lowered.contains(" dx") || lowered.contains("world wide")
            || lowered.contains("dxpedition")
        {
            return .dx
        }
        if modes == ["CW"] {
            return .cw
        }
        if modes == ["SSB"] {
            return .ssb
        }
        return .unknown
    }

    // MARK: - Popularity tier

    private static func popularityTier(for title: String) -> Int? {
        let lowered = title.lowercased()
        for entry in popularityTiers where lowered.contains(
            entry.needle.lowercased()
        ) {
            return entry.tier
        }
        return nil
    }

    // MARK: - Template matching

    private static func matchTemplate(
        title: String,
        in templateIds: [String]
    ) -> String? {
        let lowered = title.lowercased()
        // Direct ID fuzzy match first.
        for tid in templateIds {
            let tlow = tid.lowercased()
            if lowered.contains(tlow) {
                return tid
            }
        }
        // Fall back to alias table.
        for tid in templateIds {
            guard let aliases = templateIdAliases[tid] else {
                continue
            }
            for alias in aliases where lowered.contains(alias.lowercased()) {
                return tid
            }
        }
        return nil
    }

    // MARK: - Line extraction

    /// Find "Prefix: value" (case-insensitive) and return the trailing value.
    private static func line(prefixed prefix: String, in text: String) -> String? {
        let pattern = "(?im)^\\s*\(prefix)\\s*:\\s*(.+)$"
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              match.numberOfRanges > 1,
              let swiftRange = Range(match.range(at: 1), in: text)
        else {
            return nil
        }
        return String(text[swiftRange]).trimmingCharacters(in: .whitespaces)
    }
}
