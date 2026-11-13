-- Callsign enrichment: per-callsign organisation membership info pulled from
-- third-party sources. Powers the "info box" enrichment in iOS Field and
-- macOS Sweep so users don't have to type member numbers (CWops, SKCC, …)
-- by hand during contests like CWT.
--
-- Two tables:
--   callsign_enrichment_sources — admin-curated list of sources (URL + format).
--   callsign_enrichment        — one row per (callsign, source) pair.
--
-- The aggregator polls each enabled source every ~24 h, parses it, and
-- upserts here. Stale rows for a given source are deleted on each refresh
-- so callsigns that drop out of a list disappear cleanly.

CREATE TABLE callsign_enrichment_sources (
    slug TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    url TEXT NOT NULL,
    format TEXT NOT NULL,                      -- 'polo' for Ham2K PoLo notes; future: 'skcc-csv', etc.
    emoji TEXT,                                -- optional display icon for chips (e.g. '🎹' for CWops)
    enabled BOOLEAN NOT NULL DEFAULT TRUE,
    last_fetched_at TIMESTAMPTZ,
    last_etag TEXT,
    last_status TEXT,                          -- 'ok' / 'http-304' / 'error: …'
    last_error TEXT,
    consecutive_errors INT NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE callsign_enrichment (
    callsign TEXT NOT NULL,                    -- always uppercased
    source_slug TEXT NOT NULL REFERENCES callsign_enrichment_sources(slug) ON DELETE CASCADE,
    name TEXT,
    member_number TEXT,                        -- digits only, no '#' prefix (e.g. '1532')
    emoji TEXT,                                -- per-row override of the source emoji (rare)
    note TEXT,                                 -- raw note text after stripping name/number
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (callsign, source_slug)
);

CREATE INDEX idx_callsign_enrichment_source ON callsign_enrichment (source_slug);

-- Seed the CWops source. Other sources can be added by INSERTing rows.
INSERT INTO callsign_enrichment_sources (slug, name, url, format, emoji)
VALUES (
    'cwops',
    'CWops',
    'https://www.ditdit.club/data/cwops_members.txt',
    'polo',
    '🎹'
);
