//! Goal-profile → SQL compiler for the Band Scope v2 filter system.
//!
//! A profile is ONE system for goal config and feed filtering (spec §16):
//! it decides which goals compute `needed` (host-side, via
//! `NeedsPreferences`), which clubs light the `club` tier, and the base
//! include/exclude predicate for the feed. This module compiles the
//! predicate + quick toggles into `SELECT spot_id FROM scope.spots …`
//! queries the host runs through `SpotEngineApi::run_query`; the resulting
//! id sets drive per-lens enforcement (spec §17, amended 2026-07-04 —
//! Scope now hides rather than dims):
//!
//! - **Scope** hides the complement of `scope_pass` (the scrubber keeps
//!   dimmed ticks as the occupancy picture; gap math stays unfiltered).
//! - **Heard** hard-hides → complement of `heard_pass` is dropped.
//! - The WPM ceiling participates in `scope_pass` and is emitted
//!   separately as `wpm_dim`, which Heard renders as a dim.
//!
//! `run_query` has no bind-parameter surface, so every interpolated value
//! goes through `escape_sql_string` — strict single-quote doubling with
//! control characters rejected.

/// Which built-in shape a profile's feed predicate takes. Closed set — no
/// raw SQL crosses the FFI, which keeps the injection surface to the
/// escaped club keys below.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum BasePredicate {
    /// No exclusion (the `Everything` profile): tier colors alone carry
    /// priority.
    All,
    /// Park activity only: any spot carrying a park reference.
    Parks,
    /// Spots that advance DXCC (new entity or new band slot), per the
    /// needs matcher's `scope.spot_needs` projection. The `qsos` mirror
    /// can't answer this directly — its `dxcc` column is a numeric ADIF
    /// code while the spot projection carries the CTY entity name.
    DxccNeeded,
    /// Members of the profile's clubs (`scope.club_members` roster).
    ClubMembers,
    /// Spots with at least one matched need under the active profile
    /// (`scope.spot_needs` projection).
    NeededOnly,
}

/// A goal profile as the compiler sees it. `tracked_goals`/club selection
/// also feed the host's `NeedsPreferences`; here only the predicate and
/// club keys matter.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct GoalProfile {
    pub id: String,
    pub name: String,
    pub base_predicate: BasePredicate,
    /// Club keys for `ClubMembers` (e.g. "skcc", "licw", "cwops").
    pub clubs: Vec<String>,
    /// `NeedCategory::key()` values that count as "needed" under this
    /// profile (`NeededOnly` predicate + host tier assignment). Empty =
    /// every category. The engine's needs matching stays global — the
    /// profile only *selects* from it, so Hunter Log needs are untouched.
    pub need_categories: Vec<String>,
}

/// Quick-toggle state (spec §17).
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct QuickToggles {
    /// Dim spots faster than this (RBN-sourced speed). `None` = off.
    pub wpm_ceiling: Option<u32>,
    /// Hide (Heard) / dim (Scope) stations already worked today.
    pub suppress_worked_today: bool,
    /// The main volume valve: skimmer-only spots hidden (Heard) or
    /// dimmed (Scope) when false.
    pub rbn_enabled: bool,
    /// Radio-mode filter: uppercase mode strings a spot must match
    /// (hide in Heard, dim in Scope). Empty = no mode filtering.
    pub enabled_modes: Vec<String>,
}

/// The compiled per-lens query set. All queries emit a `spot_id` column
/// and are read-only by construction.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct CompiledProfileQueries {
    /// Spots that pass ALL filtering — Scope dims the complement.
    pub scope_pass: String,
    /// Spots that survive Heard's hide semantics (profile + RBN +
    /// worked-today; WPM excluded — it only dims).
    pub heard_pass: String,
    /// Spots within the WPM ceiling; Heard dims the complement. `None`
    /// when the ceiling toggle is off.
    pub wpm_dim: Option<String>,
}

/// Escape a string literal for inline SQL: single quotes doubled, control
/// characters stripped. Interpolated values are internal keys (club names,
/// callsigns), so stripping rather than erroring keeps the compiler total.
pub fn escape_sql_string(value: &str) -> String {
    value.chars().filter(|ch| !ch.is_control()).collect::<String>().replace('\'', "''")
}

fn predicate_sql(profile: &GoalProfile) -> Option<String> {
    match &profile.base_predicate {
        BasePredicate::All => None,
        BasePredicate::Parks => Some("spots.park_ref IS NOT NULL".to_string()),
        BasePredicate::DxccNeeded => Some(
            "EXISTS (SELECT 1 FROM scope.spot_needs n
                     WHERE n.spot_id = spots.spot_id
                       AND n.category IN ('dxcc', 'dxcc_band'))"
                .to_string(),
        ),
        BasePredicate::ClubMembers => {
            let clubs = profile
                .clubs
                .iter()
                .map(|club| format!("'{}'", escape_sql_string(club)))
                .collect::<Vec<_>>()
                .join(", ");
            if clubs.is_empty() {
                // A club profile with no clubs matches nothing rather
                // than silently matching everything.
                Some("0 = 1".to_string())
            } else {
                Some(format!(
                    "spots.callsign IN (SELECT callsign FROM scope.club_members WHERE club IN ({clubs}))"
                ))
            }
        }
        BasePredicate::NeededOnly => {
            let categories = profile
                .need_categories
                .iter()
                .map(|key| format!("'{}'", escape_sql_string(key)))
                .collect::<Vec<_>>()
                .join(", ");
            if categories.is_empty() {
                Some(
                    "EXISTS (SELECT 1 FROM scope.spot_needs n WHERE n.spot_id = spots.spot_id)"
                        .to_string(),
                )
            } else {
                Some(format!(
                    "EXISTS (SELECT 1 FROM scope.spot_needs n
                     WHERE n.spot_id = spots.spot_id
                       AND n.category IN ({categories}))"
                ))
            }
        }
    }
}

/// Worked-today: a QSO with this callsign+band since UTC midnight in the
/// mirrored `qsos` table. SQLite's `strftime` runs in UTC by default,
/// matching the app's day-boundary convention.
const WORKED_TODAY_SQL: &str = "NOT EXISTS (
    SELECT 1 FROM qsos q
    WHERE q.is_hidden = 0
      AND q.callsign = spots.callsign
      AND q.band = spots.band
      AND q.timestamp >= CAST(strftime('%s', 'now', 'start of day') AS REAL)
)";

/// RBN valve: the projection's `source` is the winning (highest-priority)
/// source, so a spot only counts as skimmer noise when NOTHING human ever
/// spotted it.
const RBN_OFF_SQL: &str = "(spots.source IS NULL OR spots.source <> 'rbn')";

/// WPM ceiling: the spot's speed is the fastest observation on this
/// callsign+band (observation `spot_id`s are per-source, so the join is
/// on callsign+band). Spots with no reported speed pass.
fn wpm_sql(ceiling: u32) -> String {
    format!(
        "COALESCE((
            SELECT MAX(o.speed_wpm) FROM scope.spot_observations o
            WHERE o.callsign = spots.callsign AND o.band = spots.band
        ), 0) <= {ceiling}"
    )
}

fn select_where(conditions: &[String]) -> String {
    if conditions.is_empty() {
        "SELECT spot_id FROM scope.spots".to_string()
    } else {
        format!("SELECT spot_id FROM scope.spots WHERE {}", conditions.join("\n  AND "))
    }
}

/// Compile a profile + toggles into the per-lens query set.
pub fn compile_profile_queries(
    profile: &GoalProfile,
    toggles: &QuickToggles,
) -> CompiledProfileQueries {
    let base = predicate_sql(profile);

    let mut hide_conditions: Vec<String> = Vec::new();
    if let Some(base) = &base {
        hide_conditions.push(base.clone());
    }
    if !toggles.rbn_enabled {
        hide_conditions.push(RBN_OFF_SQL.to_string());
    }
    if toggles.suppress_worked_today {
        hide_conditions.push(WORKED_TODAY_SQL.to_string());
    }
    if !toggles.enabled_modes.is_empty() {
        let modes = toggles
            .enabled_modes
            .iter()
            .map(|mode| format!("'{}'", escape_sql_string(&mode.to_uppercase())))
            .collect::<Vec<_>>()
            .join(", ");
        hide_conditions.push(format!("UPPER(spots.mode) IN ({modes})"));
    }

    let heard_pass = select_where(&hide_conditions);

    let mut scope_conditions = hide_conditions;
    if let Some(ceiling) = toggles.wpm_ceiling {
        scope_conditions.push(wpm_sql(ceiling));
    }
    let scope_pass = select_where(&scope_conditions);

    let wpm_dim = toggles.wpm_ceiling.map(|ceiling| select_where(&[wpm_sql(ceiling)]));

    CompiledProfileQueries { scope_pass, heard_pass, wpm_dim }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn profile(predicate: BasePredicate, clubs: &[&str]) -> GoalProfile {
        GoalProfile {
            id: "test".to_string(),
            name: "Test".to_string(),
            base_predicate: predicate,
            clubs: clubs.iter().map(|club| club.to_string()).collect(),
            need_categories: Vec::new(),
        }
    }

    const OFF: QuickToggles = QuickToggles {
        wpm_ceiling: None,
        suppress_worked_today: false,
        rbn_enabled: true,
        enabled_modes: Vec::new(),
    };

    #[test]
    fn everything_profile_compiles_to_unfiltered_select() {
        let queries = compile_profile_queries(&profile(BasePredicate::All, &[]), &OFF);
        assert_eq!(queries.scope_pass, "SELECT spot_id FROM scope.spots");
        assert_eq!(queries.heard_pass, "SELECT spot_id FROM scope.spots");
        assert_eq!(queries.wpm_dim, None);
    }

    #[test]
    fn parks_profile_filters_on_park_ref() {
        let queries = compile_profile_queries(&profile(BasePredicate::Parks, &[]), &OFF);
        assert_eq!(
            queries.scope_pass,
            "SELECT spot_id FROM scope.spots WHERE spots.park_ref IS NOT NULL"
        );
        assert_eq!(queries.scope_pass, queries.heard_pass);
    }

    #[test]
    fn dxcc_profile_reads_spot_needs_projection() {
        let queries = compile_profile_queries(&profile(BasePredicate::DxccNeeded, &[]), &OFF);
        assert!(queries.scope_pass.contains("scope.spot_needs"));
        assert!(queries.scope_pass.contains("'dxcc', 'dxcc_band'"));
    }

    #[test]
    fn club_profile_escapes_and_lists_clubs() {
        let queries =
            compile_profile_queries(&profile(BasePredicate::ClubMembers, &["skcc", "licw"]), &OFF);
        assert!(queries.scope_pass.contains("club IN ('skcc', 'licw')"));
    }

    #[test]
    fn club_profile_with_no_clubs_matches_nothing() {
        let queries = compile_profile_queries(&profile(BasePredicate::ClubMembers, &[]), &OFF);
        assert!(queries.scope_pass.contains("0 = 1"));
    }

    #[test]
    fn toggles_split_by_lens_semantics() {
        let toggles = QuickToggles {
            wpm_ceiling: Some(18),
            suppress_worked_today: true,
            rbn_enabled: false,
            enabled_modes: Vec::new(),
        };
        let queries = compile_profile_queries(&profile(BasePredicate::All, &[]), &toggles);
        // Scope pass includes everything (dim covers all filters).
        assert!(queries.scope_pass.contains("<> 'rbn'"));
        assert!(queries.scope_pass.contains("start of day"));
        assert!(queries.scope_pass.contains("<= 18"));
        // Heard's hide set excludes the WPM ceiling — it only dims there.
        assert!(queries.heard_pass.contains("<> 'rbn'"));
        assert!(queries.heard_pass.contains("start of day"));
        assert!(!queries.heard_pass.contains("speed_wpm"));
        // The dim query carries WPM alone.
        let wpm_dim = queries.wpm_dim.expect("wpm dim query");
        assert!(wpm_dim.contains("<= 18"));
        assert!(!wpm_dim.contains("rbn"));
    }

    #[test]
    fn needed_only_filters_by_profile_categories() {
        let mut needy = profile(BasePredicate::NeededOnly, &[]);
        let queries = compile_profile_queries(&needy, &OFF);
        // No categories → any matched need counts.
        assert!(queries.scope_pass.contains("spot_needs"));
        assert!(!queries.scope_pass.contains("n.category IN"));

        needy.need_categories = vec!["pota_new_park".to_string(), "wwff".to_string()];
        let queries = compile_profile_queries(&needy, &OFF);
        assert!(queries.scope_pass.contains("n.category IN ('pota_new_park', 'wwff')"));
    }

    #[test]
    fn mode_filter_hides_in_both_lenses() {
        let toggles = QuickToggles {
            wpm_ceiling: None,
            suppress_worked_today: false,
            rbn_enabled: true,
            enabled_modes: vec!["cw".to_string(), "FT8".to_string()],
        };
        let queries = compile_profile_queries(&profile(BasePredicate::All, &[]), &toggles);
        // Modes uppercase on the way in; the filter hides in Heard and
        // participates in the Scope pass (dim), like the base predicate.
        assert!(queries.scope_pass.contains("UPPER(spots.mode) IN ('CW', 'FT8')"));
        assert!(queries.heard_pass.contains("UPPER(spots.mode) IN ('CW', 'FT8')"));
        assert_eq!(queries.wpm_dim, None);
    }

    #[test]
    fn mode_filter_escapes_hostile_modes() {
        let toggles = QuickToggles {
            wpm_ceiling: None,
            suppress_worked_today: false,
            rbn_enabled: true,
            enabled_modes: vec!["x') OR ('1'='1".to_string()],
        };
        let queries = compile_profile_queries(&profile(BasePredicate::All, &[]), &toggles);
        assert!(queries.scope_pass.contains("'X'') OR (''1''=''1'"));
    }

    #[test]
    fn escape_neutralizes_injection() {
        assert_eq!(escape_sql_string("O'BRIEN"), "O''BRIEN");
        assert_eq!(escape_sql_string("'; DROP TABLE spots; --"), "''; DROP TABLE spots; --");
        // Control characters are stripped outright.
        assert_eq!(escape_sql_string("a\n'b\u{7}"), "a''b");

        let hostile = profile(BasePredicate::ClubMembers, &["x') OR ('1'='1"]);
        let queries = compile_profile_queries(&hostile, &OFF);
        // The doubled quotes keep the hostile text inside one literal.
        assert!(queries.scope_pass.contains("'x'') OR (''1''=''1'"));
    }
}
