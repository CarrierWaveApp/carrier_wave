/// Decode a morse pattern (e.g. ".-") to a character.
pub fn decode_pattern(pattern: &str) -> Option<char> {
    match pattern {
        // Letters
        ".-" => Some('A'),
        "-..." => Some('B'),
        "-.-." => Some('C'),
        "-.." => Some('D'),
        "." => Some('E'),
        "..-." => Some('F'),
        "--." => Some('G'),
        "...." => Some('H'),
        ".." => Some('I'),
        ".---" => Some('J'),
        "-.-" => Some('K'),
        ".-.." => Some('L'),
        "--" => Some('M'),
        "-." => Some('N'),
        "---" => Some('O'),
        ".--." => Some('P'),
        "--.-" => Some('Q'),
        ".-." => Some('R'),
        "..." => Some('S'),
        "-" => Some('T'),
        "..-" => Some('U'),
        "...-" => Some('V'),
        ".--" => Some('W'),
        "-..-" => Some('X'),
        "-.--" => Some('Y'),
        "--.." => Some('Z'),

        // Digits
        "-----" => Some('0'),
        ".----" => Some('1'),
        "..---" => Some('2'),
        "...--" => Some('3'),
        "....-" => Some('4'),
        "....." => Some('5'),
        "-...." => Some('6'),
        "--..." => Some('7'),
        "---.." => Some('8'),
        "----." => Some('9'),

        // Punctuation
        ".-.-.-" => Some('.'),
        "--..--" => Some(','),
        "..--.." => Some('?'),
        "-..-." => Some('/'),
        "-...-" => Some('='),
        ".-.-." => Some('+'),
        ".--.-." => Some('@'),

        _ => None,
    }
}

/// Encode a character to its morse pattern.
pub fn encode_char(ch: char) -> Option<&'static str> {
    match ch.to_ascii_uppercase() {
        // Letters
        'A' => Some(".-"),
        'B' => Some("-..."),
        'C' => Some("-.-."),
        'D' => Some("-.."),
        'E' => Some("."),
        'F' => Some("..-."),
        'G' => Some("--."),
        'H' => Some("...."),
        'I' => Some(".."),
        'J' => Some(".---"),
        'K' => Some("-.-"),
        'L' => Some(".-.."),
        'M' => Some("--"),
        'N' => Some("-."),
        'O' => Some("---"),
        'P' => Some(".--."),
        'Q' => Some("--.-"),
        'R' => Some(".-."),
        'S' => Some("..."),
        'T' => Some("-"),
        'U' => Some("..-"),
        'V' => Some("...-"),
        'W' => Some(".--"),
        'X' => Some("-..-"),
        'Y' => Some("-.--"),
        'Z' => Some("--.."),

        // Digits
        '0' => Some("-----"),
        '1' => Some(".----"),
        '2' => Some("..---"),
        '3' => Some("...--"),
        '4' => Some("....-"),
        '5' => Some("....."),
        '6' => Some("-...."),
        '7' => Some("--..."),
        '8' => Some("---.."),
        '9' => Some("----."),

        // Punctuation
        '.' => Some(".-.-.-"),
        ',' => Some("--..--"),
        '?' => Some("..--.."),
        '/' => Some("-..-."),
        '=' => Some("-...-"),
        '+' => Some(".-.-."),
        '@' => Some(".--.-."),

        _ => None,
    }
}

/// Return all valid (pattern, character) pairs for building lookup structures.
pub fn all_patterns() -> Vec<(&'static str, char)> {
    let mut result = Vec::new();
    for ch in ('A'..='Z').chain('0'..='9') {
        if let Some(pat) = encode_char(ch) {
            result.push((pat, ch));
        }
    }
    // Punctuation
    for &(pat, ch) in &[
        (".-.-.-", '.'),
        ("--..--", ','),
        ("..--..", '?'),
        ("-..-.", '/'),
        ("-...-", '='),
        (".-.-.", '+'),
        (".--.-.", '@'),
    ] {
        result.push((pat, ch));
    }
    result
}

/// Try to split an unrecognized pattern into two or more valid morse
/// characters. Uses greedy matching from the left: finds the longest
/// prefix that decodes, emits it, then recurses on the remainder.
///
/// Returns `None` if no valid split exists.
pub fn split_pattern(pattern: &str) -> Option<Vec<char>> {
    if pattern.is_empty() {
        return Some(Vec::new());
    }

    // Try longest prefix first (most morse chars are 1-6 elements)
    let max_len = pattern.len().min(6);
    for prefix_len in (1..=max_len).rev() {
        let prefix = &pattern[..prefix_len];
        if let Some(ch) = decode_pattern(prefix) {
            let rest = &pattern[prefix_len..];
            if rest.is_empty() {
                return Some(vec![ch]);
            }
            if let Some(mut rest_chars) = split_pattern(rest) {
                let mut result = vec![ch];
                result.append(&mut rest_chars);
                return Some(result);
            }
        }
    }

    None
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn decode_all_letters() {
        assert_eq!(decode_pattern(".-"), Some('A'));
        assert_eq!(decode_pattern("-..."), Some('B'));
        assert_eq!(decode_pattern("-.-."), Some('C'));
        assert_eq!(decode_pattern("-.."), Some('D'));
        assert_eq!(decode_pattern("."), Some('E'));
        assert_eq!(decode_pattern("..-."), Some('F'));
        assert_eq!(decode_pattern("--."), Some('G'));
        assert_eq!(decode_pattern("...."), Some('H'));
        assert_eq!(decode_pattern(".."), Some('I'));
        assert_eq!(decode_pattern(".---"), Some('J'));
        assert_eq!(decode_pattern("-.-"), Some('K'));
        assert_eq!(decode_pattern(".-.."), Some('L'));
        assert_eq!(decode_pattern("--"), Some('M'));
        assert_eq!(decode_pattern("-."), Some('N'));
        assert_eq!(decode_pattern("---"), Some('O'));
        assert_eq!(decode_pattern(".--."), Some('P'));
        assert_eq!(decode_pattern("--.-"), Some('Q'));
        assert_eq!(decode_pattern(".-."), Some('R'));
        assert_eq!(decode_pattern("..."), Some('S'));
        assert_eq!(decode_pattern("-"), Some('T'));
        assert_eq!(decode_pattern("..-"), Some('U'));
        assert_eq!(decode_pattern("...-"), Some('V'));
        assert_eq!(decode_pattern(".--"), Some('W'));
        assert_eq!(decode_pattern("-..-"), Some('X'));
        assert_eq!(decode_pattern("-.--"), Some('Y'));
        assert_eq!(decode_pattern("--.."), Some('Z'));
    }

    #[test]
    fn decode_all_digits() {
        assert_eq!(decode_pattern("-----"), Some('0'));
        assert_eq!(decode_pattern(".----"), Some('1'));
        assert_eq!(decode_pattern("..---"), Some('2'));
        assert_eq!(decode_pattern("...--"), Some('3'));
        assert_eq!(decode_pattern("....-"), Some('4'));
        assert_eq!(decode_pattern("....."), Some('5'));
        assert_eq!(decode_pattern("-...."), Some('6'));
        assert_eq!(decode_pattern("--..."), Some('7'));
        assert_eq!(decode_pattern("---.."), Some('8'));
        assert_eq!(decode_pattern("----."), Some('9'));
    }

    #[test]
    fn decode_punctuation() {
        assert_eq!(decode_pattern(".-.-.-"), Some('.'));
        assert_eq!(decode_pattern("--..--"), Some(','));
        assert_eq!(decode_pattern("..--.."), Some('?'));
        assert_eq!(decode_pattern("-..-."), Some('/'));
        assert_eq!(decode_pattern("-...-"), Some('='));
    }

    #[test]
    fn decode_unknown_returns_none() {
        assert_eq!(decode_pattern("........"), None);
        assert_eq!(decode_pattern(""), None);
        assert_eq!(decode_pattern("abc"), None);
    }

    #[test]
    fn encode_roundtrip_letters() {
        for ch in 'A'..='Z' {
            let pattern = encode_char(ch).unwrap();
            let decoded = decode_pattern(pattern).unwrap();
            assert_eq!(decoded, ch, "roundtrip failed for {ch}");
        }
    }

    #[test]
    fn encode_roundtrip_digits() {
        for ch in '0'..='9' {
            let pattern = encode_char(ch).unwrap();
            let decoded = decode_pattern(pattern).unwrap();
            assert_eq!(decoded, ch, "roundtrip failed for {ch}");
        }
    }

    #[test]
    fn encode_lowercase_works() {
        assert_eq!(encode_char('a'), Some(".-"));
        assert_eq!(encode_char('z'), Some("--.."));
    }

    #[test]
    fn encode_unknown_returns_none() {
        assert_eq!(encode_char('!'), None);
        assert_eq!(encode_char('#'), None);
    }

    #[test]
    fn split_two_chars() {
        // "----" = O(---) + T(-) or M(--) + M(--)
        let result = split_pattern("----").unwrap();
        assert!(
            result.len() >= 2,
            "expected at least 2 chars from '----', got {:?}",
            result
        );
    }

    #[test]
    fn split_three_chars() {
        // "-...--" = B(-...) + M(--) or T(-) + S(...) + M(--)
        let result = split_pattern("-...--");
        assert!(result.is_some(), "should split '-...--'");
    }

    #[test]
    fn split_single_valid_char() {
        let result = split_pattern(".-").unwrap();
        assert_eq!(result, vec!['A']);
    }

    #[test]
    fn split_unsplittable() {
        // Pattern of all dashes longer than any valid char
        let result = split_pattern("..........");
        // Should still be splittable: 5×E + 5×E or similar
        assert!(result.is_some());
    }
}
