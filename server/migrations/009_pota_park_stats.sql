-- POTA park statistics tables for caching park data, activations, and hunter QSOs.

-- Park catalog from CSV
CREATE TABLE pota_parks (
    reference           TEXT PRIMARY KEY,       -- "US-0189"
    name                TEXT NOT NULL,
    location_desc       TEXT,                   -- "US-CA"
    state               TEXT,                   -- "CA" (extracted)
    latitude            DOUBLE PRECISION,
    longitude           DOUBLE PRECISION,
    grid                TEXT,
    active              BOOLEAN NOT NULL DEFAULT true,
    total_attempts      INTEGER NOT NULL DEFAULT 0,
    total_activations   INTEGER NOT NULL DEFAULT 0,
    total_qsos          INTEGER NOT NULL DEFAULT 0,
    stats_fetched_at    TIMESTAMPTZ,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_pota_parks_state ON pota_parks(state);

-- Per-activation records
CREATE TABLE pota_activations (
    id               BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    park_reference   TEXT NOT NULL REFERENCES pota_parks(reference) ON DELETE CASCADE,
    callsign         TEXT NOT NULL,
    qso_date         DATE NOT NULL,
    total_qsos       INTEGER NOT NULL DEFAULT 0,
    qsos_cw          INTEGER NOT NULL DEFAULT 0,
    qsos_data        INTEGER NOT NULL DEFAULT 0,
    qsos_phone       INTEGER NOT NULL DEFAULT 0,
    state            TEXT,                     -- denormalized for fast queries
    UNIQUE(park_reference, callsign, qso_date)
);
CREATE INDEX idx_pota_activations_callsign ON pota_activations(callsign);
CREATE INDEX idx_pota_activations_state ON pota_activations(state);
CREATE INDEX idx_pota_activations_park ON pota_activations(park_reference);

-- Hunter totals from leaderboard
CREATE TABLE pota_hunter_qsos (
    id               BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    park_reference   TEXT NOT NULL REFERENCES pota_parks(reference) ON DELETE CASCADE,
    callsign         TEXT NOT NULL,
    qso_count        INTEGER NOT NULL DEFAULT 0,
    state            TEXT,                     -- denormalized
    UNIQUE(park_reference, callsign)
);
CREATE INDEX idx_pota_hunter_qsos_callsign ON pota_hunter_qsos(callsign);
CREATE INDEX idx_pota_hunter_qsos_state ON pota_hunter_qsos(state);

-- Per-park fetch tracking
CREATE TABLE pota_fetch_status (
    park_reference           TEXT PRIMARY KEY REFERENCES pota_parks(reference) ON DELETE CASCADE,
    activations_fetched_at   TIMESTAMPTZ,
    leaderboard_fetched_at   TIMESTAMPTZ,
    fetch_error              TEXT,
    updated_at               TIMESTAMPTZ NOT NULL DEFAULT now()
);
