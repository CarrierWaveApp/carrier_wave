-- Equipment submissions from users for admin review.
-- Anonymous submissions (no user FK) for custom hardware
-- that might belong in the catalog.

CREATE TABLE IF NOT EXISTS equipment_submissions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL,
    manufacturer TEXT NOT NULL DEFAULT '',
    category TEXT NOT NULL,
    bands TEXT[] NOT NULL DEFAULT '{}',
    modes TEXT[] NOT NULL DEFAULT '{}',
    max_power_watts INT,
    portability TEXT NOT NULL DEFAULT 'portable',
    weight_grams INT,
    status TEXT NOT NULL DEFAULT 'pending',
    catalog_id TEXT REFERENCES equipment_catalog(id),
    ip_address INET,
    app_version TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    reviewed_at TIMESTAMPTZ
);

CREATE INDEX idx_equipment_submissions_status ON equipment_submissions(status);
CREATE INDEX idx_equipment_submissions_created ON equipment_submissions(created_at DESC);
