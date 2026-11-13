//! Position-local callsign prefix suggestions for the logger's prefix
//! hot-key row (CAR-290).
//!
//! Ranks the hot-key prefixes (letters through the first digit, e.g.
//! `W6JY` -> `W6`, `KN6ABC` -> `KN6`, `VK3XYZ` -> `VK3`) of QSOs the
//! operator logged near their current position. Locality is a hard
//! requirement: prefixes are drawn only from QSOs whose `my_grid` lies
//! within a radius of the anchor position, widening once before falling
//! back to the country-level prefix for the position. Logbook history
//! and home entity never inject prefixes from somewhere else.

use std::collections::HashMap;

use crate::location_prefix;
use crate::maidenhead;

/// Minimal QSO projection needed for suggestion ranking.
pub struct SuggestionQso {
    pub callsign: String,
    pub my_grid: Option<String>,
    pub qso_date: i64,
}

/// QSOs logged within this distance of the anchor count as "near".
pub const NEAR_RADIUS_KM: f64 = 150.0;
/// Widened radius used only when the near radius produces nothing.
pub const WIDE_RADIUS_KM: f64 = 700.0;
/// Suggestion count when the caller passes `limit = 0`.
pub const DEFAULT_LIMIT: usize = 8;

/// Extracts the hot-key prefix from a callsign: everything through the
/// first digit, skipping a leading digit so `4X4ABC` -> `4X4` and
/// `9A2AA` -> `9A2`. Returns `None` when there is no digit, the prefix
/// has an implausible length, there is no suffix after it, or a
/// non-alphanumeric (portable `/` notation) lands inside it.
pub fn callsign_prefix(callsign: &str) -> Option<String> {
    let upper = callsign.trim().to_ascii_uppercase();
    let bytes = upper.as_bytes();
    let mut digit_at = None;
    for (index, byte) in bytes.iter().enumerate() {
        if index >= 1 && byte.is_ascii_digit() {
            digit_at = Some(index);
            break;
        }
    }
    let end = digit_at? + 1;
    if !(2..=4).contains(&end) || end >= upper.len() {
        return None;
    }
    if !upper[..end].chars().all(|c| c.is_ascii_alphanumeric()) {
        return None;
    }
    Some(upper[..end].to_string())
}

/// Ranks prefix suggestions anchored on `current_grid` (any maidenhead
/// precision). With no usable current grid, anchors on the operator grid
/// of the most recent QSO that has one; with no anchor at all, returns
/// nothing (the row simply hides). Ranking is by count of nearby QSOs,
/// ties broken by most recent, then alphabetically for stability.
pub fn suggested_prefixes(
    qsos: &[SuggestionQso],
    current_grid: Option<&str>,
    limit: usize,
) -> Vec<String> {
    let limit = if limit == 0 { DEFAULT_LIMIT } else { limit };
    let anchor: Option<String> = match current_grid.filter(|g| maidenhead::is_valid(g)) {
        Some(grid) => Some(grid.to_string()),
        None => qsos
            .iter()
            .filter(|q| {
                q.my_grid
                    .as_deref()
                    .map(maidenhead::is_valid)
                    .unwrap_or(false)
            })
            .max_by_key(|q| q.qso_date)
            .and_then(|q| q.my_grid.clone()),
    };
    let Some(anchor) = anchor else {
        return Vec::new();
    };

    for radius in [NEAR_RADIUS_KM, WIDE_RADIUS_KM] {
        let ranked = rank_within(qsos, &anchor, radius, limit);
        if !ranked.is_empty() {
            return ranked;
        }
    }

    location_prefix::nearest_for_grid(&anchor)
        .map(|country| vec![country.prefix.to_string()])
        .unwrap_or_default()
}

fn rank_within(
    qsos: &[SuggestionQso],
    anchor: &str,
    radius_km: f64,
    limit: usize,
) -> Vec<String> {
    let mut counts: HashMap<String, (usize, i64)> = HashMap::new();
    for qso in qsos {
        let Some(grid) = qso.my_grid.as_deref() else {
            continue;
        };
        let Some(distance) = maidenhead::distance_km(anchor, grid) else {
            continue;
        };
        if distance > radius_km {
            continue;
        }
        let Some(prefix) = callsign_prefix(&qso.callsign) else {
            continue;
        };
        let entry = counts.entry(prefix).or_insert((0, i64::MIN));
        entry.0 += 1;
        entry.1 = entry.1.max(qso.qso_date);
    }
    let mut ranked: Vec<(String, usize, i64)> = counts
        .into_iter()
        .map(|(prefix, (count, latest))| (prefix, count, latest))
        .collect();
    ranked.sort_by(|a, b| b.1.cmp(&a.1).then(b.2.cmp(&a.2)).then(a.0.cmp(&b.0)));
    ranked.into_iter().take(limit).map(|(p, _, _)| p).collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn qso(callsign: &str, grid: Option<&str>, date: i64) -> SuggestionQso {
        SuggestionQso {
            callsign: callsign.to_string(),
            my_grid: grid.map(str::to_string),
            qso_date: date,
        }
    }

    #[test]
    fn prefix_extraction() {
        assert_eq!(callsign_prefix("W6JY"), Some("W6".to_string()));
        assert_eq!(callsign_prefix("kn6abc"), Some("KN6".to_string()));
        assert_eq!(callsign_prefix("VK3XYZ"), Some("VK3".to_string()));
        assert_eq!(callsign_prefix("4X4ABC"), Some("4X4".to_string()));
        assert_eq!(callsign_prefix("9A2AA"), Some("9A2".to_string()));
        assert_eq!(callsign_prefix("W6/G4ABC"), Some("W6".to_string()));
        assert_eq!(callsign_prefix("NOCALL"), None);
        assert_eq!(callsign_prefix("W6"), None);
        assert_eq!(callsign_prefix(""), None);
    }

    #[test]
    fn ranks_only_nearby_qsos() {
        // CM97 is central California; QF44 is Canberra. Only the QSOs
        // logged from California may contribute when anchored there.
        let qsos = vec![
            qso("W6ABC", Some("CM97ab"), 100),
            qso("W6DEF", Some("CM97cd"), 101),
            qso("K6GHI", Some("CM87xx"), 102),
            qso("VK1AA", Some("QF44mr"), 103),
            qso("VK2BB", Some("QF44mr"), 104),
        ];
        let near_ca = suggested_prefixes(&qsos, Some("CM97ab"), 8);
        assert_eq!(near_ca, vec!["W6".to_string(), "K6".to_string()]);

        // Equal counts: recency breaks the tie, so VK2 (newer) leads.
        let near_vk = suggested_prefixes(&qsos, Some("QF44mr"), 8);
        assert_eq!(near_vk, vec!["VK2".to_string(), "VK1".to_string()]);
    }

    #[test]
    fn count_then_recency_ordering() {
        let qsos = vec![
            qso("K6AAA", Some("CM97"), 10),
            qso("K6BBB", Some("CM97"), 11),
            qso("W6CCC", Some("CM97"), 12),
            qso("N6DDD", Some("CM97"), 99),
        ];
        // K6 wins on count; N6 beats W6 on recency.
        let ranked = suggested_prefixes(&qsos, Some("CM97"), 8);
        assert_eq!(
            ranked,
            vec!["K6".to_string(), "N6".to_string(), "W6".to_string()]
        );
    }

    #[test]
    fn anchors_on_most_recent_grid_without_current_position() {
        let qsos = vec![
            qso("W6ABC", Some("CM97ab"), 100),
            qso("VK1AA", Some("QF44mr"), 999),
        ];
        // No current grid: the most recent logged position (Canberra) wins.
        let ranked = suggested_prefixes(&qsos, None, 8);
        assert_eq!(ranked, vec!["VK1".to_string()]);
    }

    #[test]
    fn falls_back_to_country_prefix_when_log_is_empty_nearby() {
        let qsos = vec![qso("W6ABC", Some("CM97ab"), 100)];
        // Anchored in Japan with no QSOs within either radius: fall back
        // to the country-level prefix for the position.
        let ranked = suggested_prefixes(&qsos, Some("PM95"), 8);
        assert_eq!(ranked.len(), 1);
        assert!(ranked[0].starts_with('J'), "got {ranked:?}");
    }

    #[test]
    fn no_anchor_means_no_suggestions() {
        let qsos = vec![qso("W6ABC", None, 100)];
        assert!(suggested_prefixes(&qsos, None, 8).is_empty());
        assert!(suggested_prefixes(&[], None, 8).is_empty());
    }

    #[test]
    fn respects_limit_and_default() {
        let qsos: Vec<SuggestionQso> = (0..12)
            .map(|i| {
                let call = format!("{}6ZZZ", char::from(b'A' + i as u8));
                qso(&call, Some("CM97"), i as i64)
            })
            .collect();
        assert_eq!(suggested_prefixes(&qsos, Some("CM97"), 3).len(), 3);
        assert_eq!(
            suggested_prefixes(&qsos, Some("CM97"), 0).len(),
            DEFAULT_LIMIT
        );
    }
}
