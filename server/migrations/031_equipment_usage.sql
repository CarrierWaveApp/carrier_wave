-- Anonymous equipment usage telemetry.
-- Records which catalog equipment was used in sessions,
-- along with mode/band/program context and paired equipment.
-- No user FK, no callsign, no device ID.

CREATE TABLE IF NOT EXISTS equipment_usage (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    catalog_id TEXT NOT NULL,
    category TEXT NOT NULL,
    is_custom BOOLEAN NOT NULL DEFAULT false,
    custom_name TEXT,
    custom_manufacturer TEXT,
    custom_bands TEXT[] NOT NULL DEFAULT '{}',
    custom_modes TEXT[] NOT NULL DEFAULT '{}',
    custom_max_power_watts INT,
    custom_portability TEXT,
    session_mode TEXT,
    session_band TEXT,
    session_program TEXT,
    paired_catalog_ids TEXT[] NOT NULL DEFAULT '{}',
    app_version TEXT,
    recorded_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_equipment_usage_catalog ON equipment_usage(catalog_id);
CREATE INDEX idx_equipment_usage_recorded ON equipment_usage(recorded_at DESC);
CREATE INDEX idx_equipment_usage_category ON equipment_usage(category);
