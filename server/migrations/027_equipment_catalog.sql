-- Equipment catalog for amateur radio gear (radios, antennas, keys, microphones, accessories)
CREATE EXTENSION IF NOT EXISTS pg_trgm;

CREATE TABLE equipment_catalog (
    id              TEXT PRIMARY KEY,  -- slug format: "elecraft-kx2"
    name            TEXT NOT NULL,
    manufacturer    TEXT NOT NULL,
    category        TEXT NOT NULL CHECK (category IN ('radio', 'antenna', 'key', 'microphone', 'accessory')),
    bands           TEXT[] NOT NULL DEFAULT '{}',
    modes           TEXT[] NOT NULL DEFAULT '{}',
    max_power_watts INT,
    portability     TEXT NOT NULL DEFAULT 'portable' CHECK (portability IN ('pocket', 'backpack', 'portable', 'mobile', 'base')),
    weight_grams    INT,
    description     TEXT,
    aliases         TEXT[] NOT NULL DEFAULT '{}',
    image_url       TEXT,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Immutable wrapper for array_to_string (needed for index expressions in PG 17+)
CREATE OR REPLACE FUNCTION immutable_array_to_string(arr TEXT[], sep TEXT)
RETURNS TEXT LANGUAGE sql IMMUTABLE PARALLEL SAFE AS $$
    SELECT array_to_string(arr, sep);
$$;

-- Trigram index for fuzzy search across name and aliases
CREATE INDEX idx_equipment_catalog_trgm
    ON equipment_catalog
    USING gin ((name || ' ' || immutable_array_to_string(aliases, ' ')) gin_trgm_ops);

CREATE INDEX idx_equipment_catalog_category ON equipment_catalog(category);
CREATE INDEX idx_equipment_catalog_updated_at ON equipment_catalog(updated_at);
