//! NATO/ITU phonetic-alphabet spelling for callsigns. Port of
//! `NATOPhonetics.swift`.

/// Spell `callsign` using the NATO/ITU phonetic alphabet.
///
/// Letters become their NATO word, digits become their spoken form, `/`
/// becomes "Stroke", and any other character passes through unchanged.
///
/// ```
/// use cw_domain::nato_phonetics::spell;
/// assert_eq!(spell("W1AW"), "Whiskey One Alfa Whiskey");
/// assert_eq!(spell("VE3/W1AW"), "Victor Echo Three Stroke Whiskey One Alfa Whiskey");
/// ```
pub fn spell(callsign: &str) -> String {
    callsign
        .chars()
        .flat_map(|c| c.to_uppercase())
        .map(phonetic_word)
        .collect::<Vec<_>>()
        .join(" ")
}

fn phonetic_word(c: char) -> String {
    match c {
        'A' => "Alfa".into(),
        'B' => "Bravo".into(),
        'C' => "Charlie".into(),
        'D' => "Delta".into(),
        'E' => "Echo".into(),
        'F' => "Foxtrot".into(),
        'G' => "Golf".into(),
        'H' => "Hotel".into(),
        'I' => "India".into(),
        'J' => "Juliett".into(),
        'K' => "Kilo".into(),
        'L' => "Lima".into(),
        'M' => "Mike".into(),
        'N' => "November".into(),
        'O' => "Oscar".into(),
        'P' => "Papa".into(),
        'Q' => "Quebec".into(),
        'R' => "Romeo".into(),
        'S' => "Sierra".into(),
        'T' => "Tango".into(),
        'U' => "Uniform".into(),
        'V' => "Victor".into(),
        'W' => "Whiskey".into(),
        'X' => "X-ray".into(),
        'Y' => "Yankee".into(),
        'Z' => "Zulu".into(),
        '0' => "Zero".into(),
        '1' => "One".into(),
        '2' => "Two".into(),
        '3' => "Three".into(),
        '4' => "Four".into(),
        '5' => "Five".into(),
        '6' => "Six".into(),
        '7' => "Seven".into(),
        '8' => "Eight".into(),
        '9' => "Nine".into(),
        '/' => "Stroke".into(),
        other => other.to_string(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn letters_and_digits() {
        assert_eq!(spell("W1AW"), "Whiskey One Alfa Whiskey");
    }

    #[test]
    fn lowercase_normalizes() {
        assert_eq!(spell("w1aw"), "Whiskey One Alfa Whiskey");
    }

    #[test]
    fn slash_becomes_stroke() {
        assert_eq!(spell("VE3/W1AW"), "Victor Echo Three Stroke Whiskey One Alfa Whiskey");
    }

    #[test]
    fn other_characters_pass_through() {
        assert_eq!(spell("@"), "@");
    }
}
