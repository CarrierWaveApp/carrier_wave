//! BKG log type rules — greenfield (no Swift source to mirror).
//!
//! A BKG contact is a 2 m CW QSO, direct or through a linear V/U satellite,
//! in which both stations exchange their 6-character Maidenhead grid on the
//! key. This module owns the parts every platform must agree on:
//!
//! - the locked mode/band and the satellite constants ([`MODE`], [`BAND`],
//!   [`SAT_BAND_RX`], [`SAT_MODE`], [`PROP_MODE_SAT`]);
//! - 6-character grid validation ([`normalize_grid6`]);
//! - turning the logger's form state into QSO field values
//!   ([`build_qso_fields`]): `STX_STRING`/`SRX_STRING` carry the grids when
//!   the matching "sent in CW" switch is on;
//! - the four grids of a 4-grid corner for `MY_VUCC_GRIDS`
//!   ([`corner_grids_near`], [`normalize_corner_grids`]);
//! - the pre-upload check of a stored QSO ([`check_qso`]).
//!
//! Hosts keep only layout and wiring; nothing here touches a store or a clock.

use crate::maidenhead;

/// Program slug stored in `LoggingSession.programs_raw_value`. Kept as
/// `"bkg"` so sessions logged before the rename still match.
pub const PROGRAM_SLUG: &str = "bkg";
/// What the app calls the log type on screen.
pub const DISPLAY_NAME: &str = "BKG Turf Wars";
/// A station within this many metres of the point where four 4-character
/// grids meet counts as operating from that corner.
pub const CORNER_RADIUS_M: f64 = 500.0;
/// The only mode a BKG session logs.
pub const MODE: &str = "CW";
/// The only (transmit) band a BKG session logs.
pub const BAND: &str = "2m";
/// 2 m band edges in MHz (US allocation, 144–148).
pub const BAND_LOW_MHZ: f64 = 144.0;
pub const BAND_HIGH_MHZ: f64 = 148.0;
/// Session frequency used when the wizard has none or one outside 2 m: the
/// bottom of the US 2 m CW/weak-signal segment.
pub const DEFAULT_FREQUENCY_MHZ: f64 = 144.1;
/// ADIF PROP_MODE for a satellite contact.
pub const PROP_MODE_SAT: &str = "SAT";
/// ADIF BAND_RX for a V/U satellite contact (70 cm downlink).
pub const SAT_BAND_RX: &str = "70cm";
/// ADIF SAT_MODE for a V/U satellite contact (2 m up, 70 cm down).
pub const SAT_MODE: &str = "VU";

/// Why a grid is not usable as a BKG exchange.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum GridError {
    /// Blank after trimming.
    Missing,
    /// Not exactly six characters (a 4-character grid is not enough).
    NotSixCharacters,
    /// Six characters that are not a Maidenhead locator.
    Invalid,
}

/// Trim, validate and canonicalize a 6-character grid to upper case
/// (`"cm87xk"` → `"CM87XK"`), the form sent on the key and written to
/// `STX_STRING`/`SRX_STRING`.
pub fn normalize_grid6(raw: &str) -> Result<String, GridError> {
    let grid = raw.trim().to_uppercase();
    if grid.is_empty() {
        return Err(GridError::Missing);
    }
    if grid.chars().count() != 6 {
        return Err(GridError::NotSixCharacters);
    }
    let chars: Vec<char> = grid.chars().collect();
    // Fields run A..R, squares 0..9, subsquares A..X.
    let shape_ok = ('A'..='R').contains(&chars[0])
        && ('A'..='R').contains(&chars[1])
        && chars[2].is_ascii_digit()
        && chars[3].is_ascii_digit()
        && ('A'..='X').contains(&chars[4])
        && ('A'..='X').contains(&chars[5]);
    if !shape_ok || !maidenhead::is_valid(&grid) {
        return Err(GridError::Invalid);
    }
    Ok(grid)
}

/// `true` when `frequency_mhz` is inside 2 m.
pub fn is_in_band(frequency_mhz: f64) -> bool {
    (BAND_LOW_MHZ..=BAND_HIGH_MHZ).contains(&frequency_mhz)
}

/// The logger's BKG form state for one contact.
#[derive(Debug, Clone, Default, PartialEq)]
pub struct QsoInput {
    pub my_grid: String,
    pub their_grid: String,
    /// "I sent my grid in CW".
    pub sent_my_grid: bool,
    /// "They sent theirs".
    pub received_their_grid: bool,
    /// Worked through a linear V/U satellite.
    pub via_satellite: bool,
    /// Satellite short name (e.g. "RS-44"); optional, only read when
    /// `via_satellite`.
    pub sat_name: Option<String>,
}

/// QSO field values for a BKG contact, ready to hand to the logger.
#[derive(Debug, Clone, PartialEq)]
pub struct QsoFields {
    pub mode: String,
    pub band: String,
    pub my_grid: String,
    pub their_grid: String,
    /// ADIF STX_STRING — my grid, only when I sent it in CW.
    pub exchange_sent: Option<String>,
    /// ADIF SRX_STRING — their grid, only when they sent it.
    pub exchange_received: Option<String>,
    pub prop_mode: Option<String>,
    pub sat_name: Option<String>,
    pub band_rx: Option<String>,
    pub sat_mode: Option<String>,
}

/// A problem with the form that blocks logging.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum InputError {
    MyGrid(GridError),
    TheirGrid(GridError),
}

/// Build the QSO field values from the form. Fails only on the hard rule —
/// both grids must be valid 6-character locators. The switches never block
/// logging; they decide whether the exchange fields are written.
pub fn build_qso_fields(input: &QsoInput) -> Result<QsoFields, InputError> {
    let my_grid = normalize_grid6(&input.my_grid).map_err(InputError::MyGrid)?;
    let their_grid = normalize_grid6(&input.their_grid).map_err(InputError::TheirGrid)?;
    let sat_name = input
        .sat_name
        .as_deref()
        .map(str::trim)
        .filter(|name| !name.is_empty())
        .map(str::to_uppercase)
        .filter(|_| input.via_satellite);

    Ok(QsoFields {
        mode: MODE.to_string(),
        band: BAND.to_string(),
        exchange_sent: input.sent_my_grid.then(|| my_grid.clone()),
        exchange_received: input.received_their_grid.then(|| their_grid.clone()),
        my_grid,
        their_grid,
        prop_mode: input.via_satellite.then(|| PROP_MODE_SAT.to_string()),
        sat_name,
        band_rx: input.via_satellite.then(|| SAT_BAND_RX.to_string()),
        sat_mode: input.via_satellite.then(|| SAT_MODE.to_string()),
    })
}

/// `(BAND_RX, SAT_MODE)` for a stored QSO: set when its PROP_MODE is `SAT`.
/// The store has no columns for these, so the BKG export derives them — every
/// BKG satellite contact is V/U by rule.
pub fn satellite_export_fields(prop_mode: Option<&str>) -> Option<(&'static str, &'static str)> {
    let is_sat = prop_mode.map(|mode| mode.trim().eq_ignore_ascii_case(PROP_MODE_SAT)).unwrap_or(false);
    is_sat.then_some((SAT_BAND_RX, SAT_MODE))
}

// ---------- 4-grid corner ----------

/// Number of 4-character squares around the globe per axis (18 fields × 10).
const SQUARES_PER_AXIS: i64 = 180;

/// `(lon index, lat index)` of a 4-character square, each `0..180`.
fn square_index(grid4: &str) -> Option<(i64, i64)> {
    let chars: Vec<char> = grid4.trim().to_uppercase().chars().collect();
    if chars.len() != 4 {
        return None;
    }
    let field = |c: char| (('A'..='R').contains(&c)).then(|| c as i64 - 'A' as i64);
    let digit = |c: char| c.to_digit(10).map(i64::from);
    Some((field(chars[0])? * 10 + digit(chars[2])?, field(chars[1])? * 10 + digit(chars[3])?))
}

fn square_name(lon_index: i64, lat_index: i64) -> String {
    let lon = lon_index.rem_euclid(SQUARES_PER_AXIS);
    let mut out = String::with_capacity(4);
    out.push((b'A' + (lon / 10) as u8) as char);
    out.push((b'A' + (lat_index / 10) as u8) as char);
    out.push((b'0' + (lon % 10) as u8) as char);
    out.push((b'0' + (lat_index % 10) as u8) as char);
    out
}

/// The four 4-character grids meeting at the corner nearest to a 6-character
/// grid, sorted (e.g. `"CM87xx"` → `CM87, CM88, CM97, CM98`). Longitude wraps
/// at the antimeridian. `None` for an invalid grid or one whose nearest
/// corner sits on a pole edge, where there is no four-grid corner.
pub fn corner_grids_near(grid6: &str) -> Option<Vec<String>> {
    let grid = normalize_grid6(grid6).ok()?;
    let (lon_index, lat_index) = square_index(&grid[..4])?;
    let chars: Vec<char> = grid.chars().collect();
    // Subsquare letters run A..X (24 per axis); the upper half is nearer the
    // east / north edge.
    let lon_step = if (chars[4] as i64 - 'A' as i64) >= 12 { 1 } else { -1 };
    let lat_step = if (chars[5] as i64 - 'A' as i64) >= 12 { 1 } else { -1 };
    let other_lat = lat_index + lat_step;
    if !(0..SQUARES_PER_AXIS).contains(&other_lat) {
        return None;
    }
    let mut grids = vec![
        square_name(lon_index, lat_index),
        square_name(lon_index + lon_step, lat_index),
        square_name(lon_index, other_lat),
        square_name(lon_index + lon_step, other_lat),
    ];
    grids.sort();
    Some(grids)
}

/// Validate a hand-entered corner: exactly four distinct 4-character grids
/// forming a 2×2 block. Returns them upper-cased and sorted, the order written
/// to `MY_VUCC_GRIDS`. `None` when they are not a corner.
pub fn normalize_corner_grids(grids: &[String]) -> Option<Vec<String>> {
    if grids.len() != 4 {
        return None;
    }
    let indexes: Vec<(i64, i64)> = grids.iter().map(|grid| square_index(grid)).collect::<Option<_>>()?;
    let mut lats: Vec<i64> = indexes.iter().map(|index| index.1).collect();
    lats.sort_unstable();
    lats.dedup();
    let mut lons: Vec<i64> = indexes.iter().map(|index| index.0).collect();
    lons.sort_unstable();
    lons.dedup();
    if lats.len() != 2 || lons.len() != 2 || lats[1] - lats[0] != 1 {
        return None;
    }
    let lon_gap = lons[1] - lons[0];
    if lon_gap != 1 && lon_gap != SQUARES_PER_AXIS - 1 {
        return None;
    }
    let mut out: Vec<String> = indexes.iter().map(|&(lon, lat)| square_name(lon, lat)).collect();
    out.sort();
    out.dedup();
    (out.len() == 4).then_some(out)
}

/// `MY_VUCC_GRIDS` value for a corner (`"CM87,CM88,CM97,CM98"`).
pub fn vucc_grids_field(grids: &[String]) -> Option<String> {
    normalize_corner_grids(grids).map(|grids| grids.join(","))
}

// ---------- GPS position ----------

/// Where a GPS fix puts the station for BKG Turf Wars.
#[derive(Debug, Clone, PartialEq)]
pub struct Position {
    /// The 6-character grid of the fix, upper case.
    pub grid: String,
    /// The four 4-character grids meeting at the nearest corner, sorted.
    /// Empty only near a pole, where no four grids meet.
    pub nearest_corner_grids: Vec<String>,
    /// Great-circle distance from the fix to that corner, in metres.
    pub corner_distance_m: f64,
    /// `true` when the fix is within [`CORNER_RADIUS_M`] of the corner.
    pub at_corner: bool,
}

/// Grid and nearest 4-grid corner for a GPS fix. Squares are 2° of
/// longitude by 1° of latitude, so corners sit on even longitudes and whole
/// latitudes. `None` for a coordinate off the globe.
pub fn position_from_coordinate(latitude: f64, longitude: f64) -> Option<Position> {
    if !(-90.0..=90.0).contains(&latitude) || !(-180.0..=180.0).contains(&longitude) {
        return None;
    }
    let coord = maidenhead::Coordinate::new(latitude, longitude);
    let grid = maidenhead::grid_from_coordinate(coord, maidenhead::Precision::Six).to_uppercase();

    let corner_lat = latitude.round();
    let corner_lon = (longitude / 2.0).round() * 2.0;
    // Square indexes of the squares north-east of the corner.
    let lat_index = (corner_lat + 90.0) as i64;
    let lon_index = ((corner_lon + 180.0) / 2.0) as i64;
    if lat_index <= 0 || lat_index >= SQUARES_PER_AXIS {
        return Some(Position {
            grid,
            nearest_corner_grids: Vec::new(),
            corner_distance_m: f64::INFINITY,
            at_corner: false,
        });
    }
    let mut grids = vec![
        square_name(lon_index, lat_index),
        square_name(lon_index - 1, lat_index),
        square_name(lon_index, lat_index - 1),
        square_name(lon_index - 1, lat_index - 1),
    ];
    grids.sort();
    let distance_m =
        maidenhead::distance_km_between(coord, maidenhead::Coordinate::new(corner_lat, corner_lon)) * 1000.0;
    Some(Position {
        grid,
        nearest_corner_grids: grids,
        corner_distance_m: distance_m,
        at_corner: distance_m <= CORNER_RADIUS_M,
    })
}

// ---------- pre-upload check ----------

/// One thing about a stored QSO that the BKG rules would not accept. Hosts map
/// these to copy; [`Issue::message`] is the shared English wording.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Issue {
    NotCw,
    NotTwoMeters,
    MyGridNotSixCharacters,
    TheirGridNotSixCharacters,
    /// STX_STRING missing: my grid was not marked as sent in CW.
    MyGridNotSent,
    /// SRX_STRING missing: their grid was not marked as received in CW.
    TheirGridNotReceived,
    /// STX_STRING or SRX_STRING is set but differs from the logged grid.
    ExchangeMismatch,
}

impl Issue {
    pub fn message(self) -> &'static str {
        match self {
            Issue::NotCw => "Mode is not CW",
            Issue::NotTwoMeters => "Band is not 2m",
            Issue::MyGridNotSixCharacters => "My grid is not a 6-character grid",
            Issue::TheirGridNotSixCharacters => "Their grid is not a 6-character grid",
            Issue::MyGridNotSent => "My grid was not sent in CW",
            Issue::TheirGridNotReceived => "Their grid was not received in CW",
            Issue::ExchangeMismatch => "Exchange does not match the logged grid",
        }
    }
}

/// The stored fields [`check_qso`] reads.
#[derive(Debug, Clone, Default, PartialEq)]
pub struct StoredQso<'a> {
    pub mode: Option<&'a str>,
    pub band: Option<&'a str>,
    pub my_grid: Option<&'a str>,
    pub their_grid: Option<&'a str>,
    pub exchange_sent: Option<&'a str>,
    pub exchange_received: Option<&'a str>,
}

/// Check a stored QSO against the BKG rules. Empty ⇒ ready to upload. This is
/// the app's own pre-check; the BKG server has the final say.
pub fn check_qso(qso: &StoredQso) -> Vec<Issue> {
    let mut issues = Vec::new();
    if !qso.mode.map(|mode| mode.trim().eq_ignore_ascii_case(MODE)).unwrap_or(false) {
        issues.push(Issue::NotCw);
    }
    if !qso.band.map(|band| band.trim().eq_ignore_ascii_case(BAND)).unwrap_or(false) {
        issues.push(Issue::NotTwoMeters);
    }
    let my_grid = normalize_grid6(qso.my_grid.unwrap_or_default()).ok();
    let their_grid = normalize_grid6(qso.their_grid.unwrap_or_default()).ok();
    if my_grid.is_none() {
        issues.push(Issue::MyGridNotSixCharacters);
    }
    if their_grid.is_none() {
        issues.push(Issue::TheirGridNotSixCharacters);
    }

    let sent = qso.exchange_sent.map(str::trim).filter(|value| !value.is_empty());
    let received = qso.exchange_received.map(str::trim).filter(|value| !value.is_empty());
    if sent.is_none() {
        issues.push(Issue::MyGridNotSent);
    }
    if received.is_none() {
        issues.push(Issue::TheirGridNotReceived);
    }
    let differs = |exchange: Option<&str>, grid: &Option<String>| match (exchange, grid) {
        (Some(exchange), Some(grid)) => !exchange.eq_ignore_ascii_case(grid),
        _ => false,
    };
    if differs(sent, &my_grid) || differs(received, &their_grid) {
        issues.push(Issue::ExchangeMismatch);
    }
    issues
}

#[cfg(test)]
mod tests {
    use super::*;

    fn form() -> QsoInput {
        QsoInput {
            my_grid: "cm87xk".to_string(),
            their_grid: " CM97ab ".to_string(),
            sent_my_grid: true,
            received_their_grid: true,
            via_satellite: false,
            sat_name: None,
        }
    }

    #[test]
    fn grid_must_be_six_characters() {
        assert_eq!(normalize_grid6(" cm87xk "), Ok("CM87XK".to_string()));
        assert_eq!(normalize_grid6(""), Err(GridError::Missing));
        assert_eq!(normalize_grid6("CM87"), Err(GridError::NotSixCharacters));
        assert_eq!(normalize_grid6("CM87xk12"), Err(GridError::NotSixCharacters));
        assert_eq!(normalize_grid6("CM87x1"), Err(GridError::Invalid));
        assert_eq!(normalize_grid6("ZZ87xk"), Err(GridError::Invalid));
        assert_eq!(normalize_grid6("CM87yy"), Err(GridError::Invalid));
    }

    #[test]
    fn terrestrial_contact_locks_mode_and_band() {
        let fields = build_qso_fields(&form()).unwrap();
        assert_eq!(fields.mode, "CW");
        assert_eq!(fields.band, "2m");
        assert_eq!(fields.my_grid, "CM87XK");
        assert_eq!(fields.their_grid, "CM97AB");
        assert_eq!(fields.exchange_sent.as_deref(), Some("CM87XK"));
        assert_eq!(fields.exchange_received.as_deref(), Some("CM97AB"));
        assert_eq!(fields.prop_mode, None);
        assert_eq!(fields.band_rx, None);
        assert_eq!(fields.sat_mode, None);
    }

    #[test]
    fn switches_gate_the_exchange_fields() {
        let mut input = form();
        input.sent_my_grid = false;
        let fields = build_qso_fields(&input).unwrap();
        assert_eq!(fields.exchange_sent, None);
        assert_eq!(fields.exchange_received.as_deref(), Some("CM97AB"));

        input.sent_my_grid = true;
        input.received_their_grid = false;
        let fields = build_qso_fields(&input).unwrap();
        assert_eq!(fields.exchange_sent.as_deref(), Some("CM87XK"));
        assert_eq!(fields.exchange_received, None);
    }

    #[test]
    fn satellite_contact_is_vu() {
        let mut input = form();
        input.via_satellite = true;
        input.sat_name = Some(" rs-44 ".to_string());
        let fields = build_qso_fields(&input).unwrap();
        assert_eq!(fields.band, "2m");
        assert_eq!(fields.prop_mode.as_deref(), Some("SAT"));
        assert_eq!(fields.sat_name.as_deref(), Some("RS-44"));
        assert_eq!(fields.band_rx.as_deref(), Some("70cm"));
        assert_eq!(fields.sat_mode.as_deref(), Some("VU"));
    }

    #[test]
    fn satellite_name_is_dropped_when_not_via_satellite() {
        let mut input = form();
        input.sat_name = Some("RS-44".to_string());
        assert_eq!(build_qso_fields(&input).unwrap().sat_name, None);
    }

    #[test]
    fn four_character_grids_block_logging() {
        let mut input = form();
        input.their_grid = "CM97".to_string();
        assert_eq!(build_qso_fields(&input), Err(InputError::TheirGrid(GridError::NotSixCharacters)));
        input.their_grid = "CM97ab".to_string();
        input.my_grid = String::new();
        assert_eq!(build_qso_fields(&input), Err(InputError::MyGrid(GridError::Missing)));
    }

    #[test]
    fn satellite_export_fields_follow_prop_mode() {
        assert_eq!(satellite_export_fields(Some("SAT")), Some(("70cm", "VU")));
        assert_eq!(satellite_export_fields(Some("sat")), Some(("70cm", "VU")));
        assert_eq!(satellite_export_fields(Some("TR")), None);
        assert_eq!(satellite_export_fields(None), None);
    }

    #[test]
    fn corner_follows_the_nearest_edges() {
        let grids = |grid: &str| corner_grids_near(grid).unwrap().join(",");
        // NE subsquare of CM87 → corner shared with CM97 / CM88 / CM98.
        assert_eq!(grids("CM87xx"), "CM87,CM88,CM97,CM98");
        // SW subsquare → corner shared with CM77 / CM86 / CM76.
        assert_eq!(grids("CM87aa"), "CM76,CM77,CM86,CM87");
        // NW and SE.
        assert_eq!(grids("CM87ax"), "CM77,CM78,CM87,CM88");
        assert_eq!(grids("CM87xa"), "CM86,CM87,CM96,CM97");
    }

    #[test]
    fn corner_crosses_field_boundaries_and_the_antimeridian() {
        // CM99 NE corner crosses into fields D (lon) and N (lat).
        assert_eq!(corner_grids_near("CM99xx").unwrap().join(","), "CM99,CN90,DM09,DN00");
        // AA00 is the westmost column; its west neighbour wraps to field R.
        assert_eq!(corner_grids_near("AB00ax").unwrap().join(","), "AB00,AB01,RB90,RB91");
        // No corner below the south edge.
        assert_eq!(corner_grids_near("AA00aa"), None);
        assert_eq!(corner_grids_near("CM87"), None);
    }

    #[test]
    fn hand_entered_corner_must_be_a_two_by_two_block() {
        let corner = |grids: [&str; 4]| normalize_corner_grids(&grids.map(String::from));
        assert_eq!(
            corner(["cm98", "CM87", "cm97", "CM88"]).unwrap().join(","),
            "CM87,CM88,CM97,CM98"
        );
        assert_eq!(corner(["CM87", "CM88", "CM97", "CM99"]), None); // not adjacent
        assert_eq!(corner(["CM87", "CM87", "CM97", "CM98"]), None); // duplicate
        assert_eq!(corner(["CM87", "CM88", "CM89", "CM97"]), None); // three in a column
        assert!(corner(["AB00", "AB01", "RB90", "RB91"]).is_some()); // antimeridian
        assert_eq!(normalize_corner_grids(&["CM87".to_string()]), None);
        assert_eq!(
            vucc_grids_field(&["CM87", "CM88", "CM97", "CM98"].map(String::from)).as_deref(),
            Some("CM87,CM88,CM97,CM98")
        );
    }

    #[test]
    fn gps_fix_near_a_corner_is_at_the_corner() {
        // 34°N 86°W is the EM63/EM64/EM73/EM74 corner (Gadsden area).
        let at = position_from_coordinate(34.002, -86.003).unwrap();
        assert_eq!(at.nearest_corner_grids.join(","), "EM63,EM64,EM73,EM74");
        assert!(at.corner_distance_m < 500.0, "{}", at.corner_distance_m);
        assert!(at.at_corner);
        assert_eq!(at.grid, "EM64XA"); // just west of 86°W

        // ~1.1 km north of it: same corner, out of range.
        let away = position_from_coordinate(34.01, -86.0).unwrap();
        assert_eq!(away.nearest_corner_grids.join(","), "EM63,EM64,EM73,EM74");
        assert!(away.corner_distance_m > 1_000.0);
        assert!(!away.at_corner);
    }

    #[test]
    fn gps_corner_matches_the_grid_corner_helper() {
        let fix = position_from_coordinate(37.4, -122.1).unwrap();
        assert_eq!(fix.grid, "CM87WJ");
        assert_eq!(fix.nearest_corner_grids, corner_grids_near(&fix.grid).unwrap());
    }

    #[test]
    fn gps_corner_wraps_and_stops_at_the_poles() {
        let fix = position_from_coordinate(10.0, 179.9).unwrap();
        assert_eq!(fix.nearest_corner_grids.join(","), "AJ09,AK00,RJ99,RK90");
        let polar = position_from_coordinate(89.9, 10.0).unwrap();
        assert!(polar.nearest_corner_grids.is_empty());
        assert!(!polar.at_corner);
        assert_eq!(position_from_coordinate(91.0, 0.0), None);
        assert_eq!(position_from_coordinate(f64::NAN, 0.0), None);
    }

    #[test]
    fn clean_qso_has_no_issues() {
        let qso = StoredQso {
            mode: Some("CW"),
            band: Some("2m"),
            my_grid: Some("CM87xk"),
            their_grid: Some("CM97AB"),
            exchange_sent: Some("CM87XK"),
            exchange_received: Some("cm97ab"),
        };
        assert!(check_qso(&qso).is_empty());
    }

    #[test]
    fn check_reports_every_broken_rule() {
        let qso = StoredQso {
            mode: Some("SSB"),
            band: Some("70cm"),
            my_grid: Some("CM87"),
            their_grid: None,
            exchange_sent: None,
            exchange_received: Some(" "),
        };
        assert_eq!(
            check_qso(&qso),
            vec![
                Issue::NotCw,
                Issue::NotTwoMeters,
                Issue::MyGridNotSixCharacters,
                Issue::TheirGridNotSixCharacters,
                Issue::MyGridNotSent,
                Issue::TheirGridNotReceived,
            ]
        );
    }

    #[test]
    fn check_flags_an_exchange_that_differs_from_the_grid() {
        let qso = StoredQso {
            mode: Some("CW"),
            band: Some("2m"),
            my_grid: Some("CM87xk"),
            their_grid: Some("CM97ab"),
            exchange_sent: Some("CM87XK"),
            exchange_received: Some("CM97AC"),
        };
        assert_eq!(check_qso(&qso), vec![Issue::ExchangeMismatch]);
    }

    #[test]
    fn band_edges() {
        assert!(is_in_band(144.0));
        assert!(is_in_band(145.9));
        assert!(!is_in_band(146.52 + 2.0));
        assert!(!is_in_band(432.1));
        assert!(is_in_band(DEFAULT_FREQUENCY_MHZ));
    }
}
