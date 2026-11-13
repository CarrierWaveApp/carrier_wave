//
//  MorseCode.swift
//  CarrierWaveCore
//

import Foundation

// MARK: - MorseCode

/// Morse code lookup table and utilities
public enum MorseCode: Sendable {
    // MARK: - Timing Constants

    /// Standard Morse timing relationships
    /// All times are relative to one "unit" (the length of a dit)
    public enum Timing: Sendable {
        /// Dit length = 1 unit
        public static let ditUnits: Double = 1.0

        /// Dah length = 3 units
        public static let dahUnits: Double = 3.0

        /// Inter-element gap (within character) = 1 unit
        public static let elementGapUnits: Double = 1.0

        /// Inter-character gap = 3 units
        public static let charGapUnits: Double = 3.0

        /// Inter-word gap = 7 units
        public static let wordGapUnits: Double = 7.0

        /// Calculate unit duration in seconds from WPM
        /// PARIS standard: "PARIS" = 50 units, so at W WPM, unit = 1.2/W seconds
        public static func unitDuration(forWPM wpm: Int) -> TimeInterval {
            1.2 / Double(wpm)
        }

        /// Calculate WPM from unit duration
        public static func wpm(fromUnitDuration duration: TimeInterval) -> Int {
            guard duration > 0 else {
                return 20
            }
            return max(5, min(60, Int(1.2 / duration)))
        }
    }

    // MARK: - Morse to Character Mapping

    /// Standard International Morse Code mapping
    /// Key: morse pattern (. = dit, - = dah)
    /// Value: decoded character
    public static let morseToChar: [String: String] = [
        // Letters
        ".-": "A",
        "-...": "B",
        "-.-.": "C",
        "-..": "D",
        ".": "E",
        "..-.": "F",
        "--.": "G",
        "....": "H",
        "..": "I",
        ".---": "J",
        "-.-": "K",
        ".-..": "L",
        "--": "M",
        "-.": "N",
        "---": "O",
        ".--.": "P",
        "--.-": "Q",
        ".-.": "R",
        "...": "S",
        "-": "T",
        "..-": "U",
        "...-": "V",
        ".--": "W",
        "-..-": "X",
        "-.--": "Y",
        "--..": "Z",

        // Numbers
        ".----": "1",
        "..---": "2",
        "...--": "3",
        "....-": "4",
        ".....": "5",
        "-....": "6",
        "--...": "7",
        "---..": "8",
        "----.": "9",
        "-----": "0",

        // Punctuation
        ".-.-.-": ".",
        "--..--": ",",
        "..--..": "?",
        ".----.": "'",
        "-.-.--": "!",
        "-..-.": "/",
        "-.--.": "(",
        "-.--.-": ")",
        ".-...": "&",
        "---...": ":",
        "-.-.-.": ";",
        "-...-": "=",
        ".-.-.": "+",
        "-....-": "-",
        "..--.-": "_",
        ".-..-.": "\"",
        "...-..-": "$",
        ".--.-.": "@",

        // Prosigns (procedural signals) - common in amateur radio
        // Note: Some prosigns share patterns with punctuation/letters.
        // The standard characters are preferred; prosigns are documented in abbreviations.
        "-.-.-": "<CT>", // Start copying / attention
        ".-.-": "<AA>", // New line / new section
        "...-.": "<SN>", // Understood / verified
        "........": "<HH>", // Error / correction
        // SK/VA = "...-.-", BT = "-...-", AS = ".-...", K = "-.-", KN = "-.--."
        // These conflict with =, &, (, ), K - standard chars take precedence
    ]

    /// Character to Morse mapping (reverse of morseToChar)
    public static let charToMorse: [String: String] = {
        var result: [String: String] = [:]
        for (morse, char) in morseToChar where !char.hasPrefix("<") {
            // Skip prosigns for reverse lookup (use letter form)
            result[char] = morse
        }
        return result
    }()

    // MARK: - Common QSO Abbreviations

    /// Common CW abbreviations used in amateur radio QSOs
    public static let abbreviations: [String: String] = [
        "CQ": "Calling any station",
        "DE": "From (this is)",
        "K": "Go ahead / over",
        "KN": "Go ahead, named station only",
        "BK": "Break (back to you)",
        "SK": "End of contact",
        "73": "Best regards",
        "88": "Love and kisses",
        "RST": "Readability, Strength, Tone",
        "UR": "Your / You are",
        "R": "Received / Roger",
        "QTH": "Location",
        "QSL": "Confirmation / I confirm",
        "QRZ": "Who is calling?",
        "QRS": "Send slower",
        "QRQ": "Send faster",
        "QRM": "Interference",
        "QRN": "Static / noise",
        "QSB": "Fading",
        "QSY": "Change frequency",
        "AGN": "Again",
        "ANT": "Antenna",
        "BT": "Break / separator",
        "CFM": "Confirm",
        "CL": "Closing station",
        "CUL": "See you later",
        "FB": "Fine business (great)",
        "FER": "For",
        "GA": "Good afternoon / Go ahead",
        "GE": "Good evening",
        "GM": "Good morning",
        "GN": "Good night",
        "HI": "Laughter",
        "HR": "Here",
        "HW": "How",
        "NR": "Number",
        "OM": "Old man (male operator)",
        "OP": "Operator",
        "PSE": "Please",
        "PWR": "Power",
        "RIG": "Radio equipment",
        "RPT": "Repeat",
        "SIG": "Signal",
        "TNX": "Thanks",
        "TU": "Thank you",
        "VY": "Very",
        "WX": "Weather",
        "XYL": "Wife",
        "YL": "Young lady (female operator)",
    ]

    // MARK: - Decoding

    /// Decode a morse pattern to a character
    /// - Parameter pattern: Morse pattern string (e.g., ".-" for A)
    /// - Returns: Decoded character or nil if not found
    public static func decode(_ pattern: String) -> String? {
        morseToChar[pattern]
    }

    /// Encode a character to morse
    /// - Parameter char: Character to encode
    /// - Returns: Morse pattern or nil if not encodable
    public static func encode(_ char: Character) -> String? {
        charToMorse[String(char).uppercased()]
    }
}
