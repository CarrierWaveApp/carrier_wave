/// NATO/ITU phonetic alphabet utilities for callsign readback
public enum NATOPhonetics {
    // MARK: Public

    /// Returns the NATO phonetic spelling of a callsign.
    ///
    /// Letters become their NATO word, digits become their spoken form,
    /// "/" becomes "stroke", and other characters pass through unchanged.
    ///
    ///     NATOPhonetics.spell("W1AW")
    ///     // "Whiskey One Alfa Whiskey"
    ///
    ///     NATOPhonetics.spell("VE3/W1AW")
    ///     // "Victor Echo Three Stroke Whiskey One Alfa Whiskey"
    public static func spell(_ callsign: String) -> String {
        callsign.uppercased()
            .map { phoneticWord(for: $0) }
            .joined(separator: " ")
    }

    // MARK: Private

    // swiftlint:disable cyclomatic_complexity
    private static func phoneticWord(for character: Character) -> String {
        switch character {
        case "A": "Alfa"
        case "B": "Bravo"
        case "C": "Charlie"
        case "D": "Delta"
        case "E": "Echo"
        case "F": "Foxtrot"
        case "G": "Golf"
        case "H": "Hotel"
        case "I": "India"
        case "J": "Juliett"
        case "K": "Kilo"
        case "L": "Lima"
        case "M": "Mike"
        case "N": "November"
        case "O": "Oscar"
        case "P": "Papa"
        case "Q": "Quebec"
        case "R": "Romeo"
        case "S": "Sierra"
        case "T": "Tango"
        case "U": "Uniform"
        case "V": "Victor"
        case "W": "Whiskey"
        case "X": "X-ray"
        case "Y": "Yankee"
        case "Z": "Zulu"
        case "0": "Zero"
        case "1": "One"
        case "2": "Two"
        case "3": "Three"
        case "4": "Four"
        case "5": "Five"
        case "6": "Six"
        case "7": "Seven"
        case "8": "Eight"
        case "9": "Nine"
        case "/": "Stroke"
        default: String(character)
        }
    }
    // swiftlint:enable cyclomatic_complexity
}
