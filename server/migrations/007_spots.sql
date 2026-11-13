-- Generic spots system: aggregated external spots + self-spotting

CREATE TYPE spot_source AS ENUM ('pota', 'rbn', 'sota', 'self', 'other');

CREATE TABLE spots (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    callsign        TEXT NOT NULL,
    program_slug    TEXT REFERENCES programs(slug) ON DELETE SET NULL,
    source          spot_source NOT NULL,
    external_id     TEXT,

    frequency_khz   DOUBLE PRECISION NOT NULL,
    mode            TEXT NOT NULL,
    reference       TEXT,
    reference_name  TEXT,

    spotter         TEXT,
    spotter_grid    TEXT,
    location_desc   TEXT,
    country_code    TEXT,
    state_abbr      TEXT,
    comments        TEXT,
    snr             SMALLINT,
    wpm             SMALLINT,

    submitted_by    UUID REFERENCES participants(id) ON DELETE SET NULL,
    spotted_at      TIMESTAMPTZ NOT NULL,
    expires_at      TIMESTAMPTZ NOT NULL,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Dedup index for aggregated spots (only where external_id is set)
CREATE UNIQUE INDEX idx_spots_external_id ON spots(source, external_id)
    WHERE external_id IS NOT NULL;

-- Fast lookup by program + expiry (queries filter expires_at at runtime)
CREATE INDEX idx_spots_program_expires ON spots(program_slug, expires_at DESC);

-- Fast lookup by callsign
CREATE INDEX idx_spots_callsign_expires ON spots(callsign, expires_at DESC);

-- TTL cleanup
CREATE INDEX idx_spots_expires_at ON spots(expires_at);
