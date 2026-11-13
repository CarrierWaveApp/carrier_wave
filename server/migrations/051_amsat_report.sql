-- Raw AMSAT community reports, accumulated across aggregator cycles.
--
-- The `amsat_status` summary throws away the per-report history, and AMSAT's
-- `sat_info.php` API caps every query at 100 rows — for busy FM birds (SO-50,
-- ISS) that is only two or three days, so a 7-day summary built from one
-- response is silently truncated. Keeping each report here (deduplicated on
-- its natural key) lets the aggregator summarize the full window and lets
-- `/satellites/amsat-status/activity` serve the hour-by-hour grid AMSAT's own
-- status page draws. Rows older than the window are pruned every cycle.
CREATE TABLE IF NOT EXISTS amsat_report (
    name          TEXT NOT NULL,          -- AMSAT internal name, e.g. 'SO-50_[FM]'
    reported_at   TIMESTAMPTZ NOT NULL,   -- AMSAT quantizes to the hour (hh:30Z)
    callsign      TEXT NOT NULL,
    report        TEXT NOT NULL,          -- 'Heard' | 'Not Heard' | 'Telemetry Only' | 'Crew Active'
    grid          TEXT,
    first_seen_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (name, reported_at, callsign, report)
);

CREATE INDEX IF NOT EXISTS idx_amsat_report_reported_at ON amsat_report (reported_at);
