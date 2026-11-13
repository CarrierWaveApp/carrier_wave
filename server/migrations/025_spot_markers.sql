-- Spot markers: short codes that link a callsign to SMS-based spotting via Twilio
CREATE TABLE spot_markers (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    marker      TEXT NOT NULL UNIQUE,
    callsign    TEXT NOT NULL,
    participant_id UUID NOT NULL REFERENCES participants(id) ON DELETE CASCADE,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_spot_markers_callsign ON spot_markers (callsign);
CREATE INDEX idx_spot_markers_participant ON spot_markers (participant_id);
