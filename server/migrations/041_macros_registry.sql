-- Radio Macros registry (CAR-271, Phase 1).
--
-- Source of truth for community-curated `.cwmacro` documents. Public read endpoints
-- filter on `status='approved'`; admin endpoints can mutate any row. Withdrawn slugs
-- are NEVER reused — they stay in `macros` with `status='withdrawn'` and propagate to
-- clients via the `macro_tombstones` table.
--
-- See docs/superpowers/specs/2026-05-23-radio-macros-design.md ("Server registry")
-- for the field-level rationale.

CREATE TABLE macros (
    id UUID PRIMARY KEY,
    slug TEXT UNIQUE NOT NULL,
    author_user_id UUID REFERENCES users(id) ON DELETE SET NULL,
    author_callsign TEXT,
    name TEXT NOT NULL,
    icon TEXT,
    description TEXT,
    tags TEXT[] NOT NULL DEFAULT '{}',
    applies_to TEXT[] NOT NULL DEFAULT '{}',
    capabilities JSONB NOT NULL,
    args JSONB NOT NULL DEFAULT '[]'::jsonb,
    steps JSONB NOT NULL,
    format INT NOT NULL,
    status TEXT NOT NULL,
    version INT NOT NULL DEFAULT 1,
    moderator_notes TEXT,
    published_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_macros_status ON macros (status);
CREATE INDEX idx_macros_applies_to ON macros USING GIN (applies_to);
CREATE INDEX idx_macros_tags ON macros USING GIN (tags);

CREATE TABLE macro_versions (
    macro_id UUID NOT NULL REFERENCES macros(id) ON DELETE CASCADE,
    version INT NOT NULL,
    spec JSONB NOT NULL,
    published_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (macro_id, version)
);

CREATE TABLE macro_reports (
    id BIGSERIAL PRIMARY KEY,
    macro_id UUID NOT NULL REFERENCES macros(id) ON DELETE CASCADE,
    reporter_user_id UUID REFERENCES users(id) ON DELETE SET NULL,
    reason TEXT NOT NULL,
    notes TEXT,
    status TEXT NOT NULL DEFAULT 'open',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Slug → tombstone propagation list, polled by clients on each registry sync.
CREATE TABLE macro_tombstones (
    slug TEXT PRIMARY KEY REFERENCES macros(slug) ON DELETE CASCADE,
    reason TEXT NOT NULL,
    tombstoned_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE macro_run_events (
    id BIGSERIAL PRIMARY KEY,
    macro_id UUID NOT NULL REFERENCES macros(id) ON DELETE CASCADE,
    device_hash TEXT NOT NULL,
    success BOOLEAN NOT NULL,
    failed_step_index INT,
    error_code TEXT,
    occurred_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_macro_run_events_macro ON macro_run_events (macro_id, occurred_at DESC);

-- Daily roll-up populated by the 90-day retention job (Task 9). Run events older
-- than 90 days are deleted after their day's aggregate row is written.
CREATE TABLE macro_run_aggregates (
    macro_id UUID NOT NULL REFERENCES macros(id) ON DELETE CASCADE,
    day DATE NOT NULL,
    success_count BIGINT NOT NULL DEFAULT 0,
    failure_count BIGINT NOT NULL DEFAULT 0,
    failures_by_step JSONB NOT NULL DEFAULT '{}'::jsonb,
    PRIMARY KEY (macro_id, day)
);
