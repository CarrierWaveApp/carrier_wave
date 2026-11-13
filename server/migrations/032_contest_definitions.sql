-- Contest definitions: declarative JSON format for amateur radio contests.
-- See docs/features/contest-definitions.md for the format reference.
--
-- The `id` is the contest id from the definition itself (lowercase kebab-case)
-- and is the natural key. `definition` stores the full Contest object as
-- JSONB so admins can round-trip the format without lossy conversions.

CREATE TABLE IF NOT EXISTS contest_definitions (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    short_name TEXT,
    sponsor_name TEXT,
    sponsor_url TEXT,
    format_version TEXT NOT NULL,
    definition JSONB NOT NULL,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_contest_definitions_active
    ON contest_definitions(is_active, name);
