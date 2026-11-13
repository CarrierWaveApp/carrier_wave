-- Per-day scheduling for multi-day events

CREATE TABLE event_days (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    event_id    UUID NOT NULL REFERENCES events(id) ON DELETE CASCADE,
    date        DATE NOT NULL,
    start_time  TIMESTAMPTZ NOT NULL,
    end_time    TIMESTAMPTZ,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Look up days by event
CREATE INDEX idx_event_days_event_id ON event_days (event_id, date);
