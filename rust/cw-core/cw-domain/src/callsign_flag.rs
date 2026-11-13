//! Callsign-prefix → country flag emoji.
//!
//! Faithful port of the iOS `CallsignFlagHelper`: a small, intentionally
//! partial hand-rolled table (not full DXCC). The list is ordered so 2-char
//! prefixes match before 1-char ones, since the match is a plain `starts_with`
//! on the uppercased callsign and the first hit wins.

/// (prefix, flag) pairs in match order — longest/2-char prefixes first.
const PREFIX_FLAGS: &[(&str, &str)] = &[
    ("VE", "🇨🇦"),
    ("VA", "🇨🇦"),
    ("DL", "🇩🇪"),
    ("DA", "🇩🇪"),
    ("DB", "🇩🇪"),
    ("DC", "🇩🇪"),
    ("JA", "🇯🇵"),
    ("JH", "🇯🇵"),
    ("JR", "🇯🇵"),
    ("VK", "🇦🇺"),
    ("ZL", "🇳🇿"),
    ("EA", "🇪🇸"),
    ("PA", "🇳🇱"),
    ("PD", "🇳🇱"),
    ("PE", "🇳🇱"),
    ("ON", "🇧🇪"),
    ("OZ", "🇩🇰"),
    ("SM", "🇸🇪"),
    ("SA", "🇸🇪"),
    ("LA", "🇳🇴"),
    ("OH", "🇫🇮"),
    ("W", "🇺🇸"),
    ("K", "🇺🇸"),
    ("N", "🇺🇸"),
    ("A", "🇺🇸"),
    ("G", "🇬🇧"),
    ("M", "🇬🇧"),
    ("F", "🇫🇷"),
    ("I", "🇮🇹"),
];

/// First flag whose prefix the uppercased `callsign` starts with, or `None`.
pub fn flag_for_callsign(callsign: &str) -> Option<String> {
    let upper = callsign.to_uppercase();
    PREFIX_FLAGS
        .iter()
        .find(|(prefix, _)| upper.starts_with(prefix))
        .map(|(_, flag)| (*flag).to_string())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn two_char_prefix_wins_over_one_char() {
        // VE7… must resolve Canada, not fall through to a 1-char US prefix.
        assert_eq!(flag_for_callsign("VE7AB").as_deref(), Some("🇨🇦"));
        assert_eq!(flag_for_callsign("VA3XYZ").as_deref(), Some("🇨🇦"));
    }

    #[test]
    fn one_char_us_prefixes() {
        for call in ["W6JY", "K1ABC", "N0CALL", "AA7BQ"] {
            assert_eq!(flag_for_callsign(call).as_deref(), Some("🇺🇸"), "{call}");
        }
    }

    #[test]
    fn lowercase_input_is_uppercased() {
        assert_eq!(flag_for_callsign("g3xyz").as_deref(), Some("🇬🇧"));
    }

    #[test]
    fn unknown_prefix_is_none() {
        assert!(flag_for_callsign("ZS6ABC").is_none());
        assert!(flag_for_callsign("").is_none());
    }
}
