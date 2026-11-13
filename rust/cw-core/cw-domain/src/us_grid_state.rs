//! Maidenhead grid square → US state approximation. Port of
//! `POTAClient+GridLookup.swift` (`gridToUSState`). Used as the fallback in the
//! POTA `statesActivated` award when a park has no `location_desc` state.
//!
//! This is deliberately approximate — grid squares can span state borders, so the
//! table returns the most likely state for a field+square, falling back to a
//! field-level guess. It must match the Swift table case-for-case for parity.

/// Derive a US state abbreviation from a 4+ character Maidenhead grid square.
/// Returns `None` for grids shorter than 4 chars or fields not in the table.
pub fn grid_to_us_state(grid: &str) -> Option<String> {
    if grid.chars().count() < 4 {
        return None;
    }
    let upper = grid.to_uppercase();
    let chars: Vec<char> = upper.chars().collect();
    let field: String = chars[0..2].iter().collect();
    // Swift takes the *original* grid's chars 2..4 for the square (not uppercased),
    // but squares are digits, so case is irrelevant; use the uppercased copy.
    let square: String = chars[2..4].iter().collect();

    specific_grid_to_state(&field, &square).or_else(|| field_to_state(&field))
}

fn specific_grid_to_state(field: &str, square: &str) -> Option<String> {
    match field {
        "CM" | "DM" => west_coast_grid_state(field, square),
        "CN" => pacific_northwest_grid_state(square),
        "DN" => mountain_grid_state(square),
        "EM" | "EL" => southern_grid_state(field, square),
        "FN" => northeast_grid_state(square),
        _ => None,
    }
}

fn west_coast_grid_state(field: &str, square: &str) -> Option<String> {
    let state = match (field, square) {
        // California
        ("CM", "87") | ("CM", "88") | ("CM", "97") | ("CM", "98") => "CA",
        ("DM", "03") | ("DM", "04") | ("DM", "05") | ("DM", "06") | ("DM", "07") => "CA",
        ("DM", "12") | ("DM", "13") | ("DM", "14") => "CA",
        // Arizona
        ("DM", "31") | ("DM", "32") | ("DM", "33") => "AZ",
        ("DM", "41") | ("DM", "42") | ("DM", "43") => "AZ",
        // Nevada
        ("DM", "08") | ("DM", "09") | ("DM", "18") | ("DM", "19") => "NV",
        ("DM", "26") | ("DM", "27") => "NV",
        // Colorado (DM squares)
        ("DM", "69") | ("DM", "79") | ("DM", "78") => "CO",
        _ => return None,
    };
    Some(state.to_string())
}

fn pacific_northwest_grid_state(square: &str) -> Option<String> {
    let state = match square {
        // Washington
        "74" | "75" | "84" | "85" | "86" | "87" | "88" => "WA",
        // Oregon
        "73" | "82" | "83" | "93" | "94" | "95" => "OR",
        _ => return None,
    };
    Some(state.to_string())
}

fn mountain_grid_state(square: &str) -> Option<String> {
    match square {
        // Colorado
        "60" | "70" => Some("CO".to_string()),
        _ => None,
    }
}

fn southern_grid_state(field: &str, square: &str) -> Option<String> {
    let state = match (field, square) {
        // Texas
        ("EM", "00") | ("EM", "01") | ("EM", "10") | ("EM", "11") => "TX",
        ("EM", "12") | ("EM", "13") | ("EM", "20") | ("EM", "21") => "TX",
        // Florida
        ("EL", "87") | ("EL", "88") | ("EL", "96") | ("EL", "97") | ("EL", "98") => "FL",
        _ => return None,
    };
    Some(state.to_string())
}

fn northeast_grid_state(square: &str) -> Option<String> {
    match square {
        // New York
        "10" | "11" | "20" | "21" | "30" | "31" => Some("NY".to_string()),
        _ => None,
    }
}

fn field_to_state(field: &str) -> Option<String> {
    let state = match field {
        "CM" | "DM" => "CA",
        "CN" => "WA",
        "DN" => "CO",
        "EM" => "TX",
        "EN" => "WI",
        "EL" => "FL",
        "FM" => "VA",
        "FN" => "NY",
        _ => return None,
    };
    Some(state.to_string())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn too_short_returns_none() {
        assert_eq!(grid_to_us_state("DN"), None);
        assert_eq!(grid_to_us_state("DN4"), None);
    }

    #[test]
    fn specific_square_wins_over_field() {
        // DM03 is specifically CA (matches the field default too, but exercises the path).
        assert_eq!(grid_to_us_state("DM03xx").as_deref(), Some("CA"));
        // DM31 is AZ — overrides the DM→CA field default.
        assert_eq!(grid_to_us_state("DM31").as_deref(), Some("AZ"));
        // DM08 is NV — overrides the DM→CA field default.
        assert_eq!(grid_to_us_state("DM08").as_deref(), Some("NV"));
    }

    #[test]
    fn field_level_fallback() {
        // DN60/DN70 are CO specifically; an unlisted DN square falls back to DN→CO.
        assert_eq!(grid_to_us_state("DN44").as_deref(), Some("CO"));
        assert_eq!(grid_to_us_state("EN50").as_deref(), Some("WI"));
        assert_eq!(grid_to_us_state("FM18").as_deref(), Some("VA"));
    }

    #[test]
    fn unknown_field_is_none() {
        assert_eq!(grid_to_us_state("JO65"), None);
    }

    #[test]
    fn case_insensitive_field() {
        assert_eq!(grid_to_us_state("dm31").as_deref(), Some("AZ"));
    }
}
