//! Test-only fault-injection facilities (behind the `testing` feature).

pub mod crash_vfs;
pub use crash_vfs::CrashController;

use crate::Qso;

/// Minimal sample QSO builder shared by the durability crasher binary and
/// integration tests. Only the three non-optional, non-bool fields are filled;
/// everything else is left `None` / `false`. Callers may override fields after
/// construction (e.g. set `qso_date`).
pub fn sample_qso_min(id: &str) -> Qso {
    Qso {
        id: id.to_string(),
        callsign: "W1AW".to_string(),
        band: None,
        mode: None,
        freq_khz: None,
        qso_date: 0,
        my_grid: None,
        their_grid: None,
        rst_sent: None,
        rst_rcvd: None,
        my_callsign: None,
        park: None,
        their_park: None,
        notes: None,
        notes_user_authored: false,
        spot_comments_data: None,
        callsign_change_note: None,
        original_callsign: None,
        import_source_raw_value: "logger".to_string(),
        imported_at: 0,
        modified_at: None,
        raw_adif: None,
        name: None,
        qth: None,
        state: None,
        country: None,
        power: None,
        my_rig: None,
        station_profile_name: None,
        sota_ref: None,
        wwff_ref: None,
        aoa_code: None,
        qrz_log_id: None,
        qrz_confirmed: false,
        lotw_confirmed_date: None,
        lotw_confirmed: false,
        dxcc: None,
        their_license_class: None,
        contest_name: None,
        contest_serial_sent: None,
        contest_serial_received: None,
        contest_exchange_sent: None,
        contest_exchange_received: None,
        is_hidden: false,
        is_activity_log_qso: false,
        station_callsign: None,
        logging_session_id: None,
        dirty: true,
    }
}
