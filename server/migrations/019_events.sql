-- User-submitted events with admin moderation and proximity-based discovery

CREATE TABLE events (
    id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name              TEXT NOT NULL CHECK (char_length(name) <= 200),
    description       TEXT CHECK (char_length(description) <= 2000),
    event_type        TEXT NOT NULL CHECK (event_type IN (
        'club_meeting', 'swap_meet', 'field_day',
        'special_event', 'hamfest', 'net', 'other'
    )),
    start_date        TIMESTAMPTZ NOT NULL,
    end_date          TIMESTAMPTZ,
    timezone          TEXT NOT NULL,
    venue_name        TEXT CHECK (char_length(venue_name) <= 200),
    address           TEXT NOT NULL,
    city              TEXT NOT NULL,
    state             TEXT,
    country           TEXT NOT NULL,
    latitude          DOUBLE PRECISION NOT NULL,
    longitude         DOUBLE PRECISION NOT NULL,
    location          geography(Point, 4326) NOT NULL,
    cost              TEXT CHECK (char_length(cost) <= 100),
    url               TEXT,
    submitted_by      TEXT NOT NULL,
    status            TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected')),
    reviewed_by       TEXT,
    reviewed_at       TIMESTAMPTZ,
    rejection_reason  TEXT,
    created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at        TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Spatial index for proximity queries
CREATE INDEX idx_events_location ON events USING GIST (location);

-- Status + date for listing queries
CREATE INDEX idx_events_status_start ON events (status, start_date);

-- Submitter lookup for "my events"
CREATE INDEX idx_events_submitted_by ON events (submitted_by);

-- Trigger to auto-populate location from lat/lon
CREATE OR REPLACE FUNCTION events_set_location()
RETURNS TRIGGER AS $$
BEGIN
    NEW.location := ST_SetSRID(ST_MakePoint(NEW.longitude, NEW.latitude), 4326)::geography;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_events_set_location
    BEFORE INSERT OR UPDATE ON events
    FOR EACH ROW
    EXECUTE FUNCTION events_set_location();
