-- AMSAT's 15-minute report period (0–3 within the hour), exposed by the
-- rebuilt status API (status.amsat.org, 2026-11). AMSAT replaces a report
-- when the same callsign files again for the same satellite, hour and
-- period, so the aggregator uses it to drop the superseded verdict instead
-- of keeping both. Rows written before this migration stay NULL and age out
-- with the 8-day retention.
ALTER TABLE amsat_report ADD COLUMN IF NOT EXISTS period SMALLINT;
