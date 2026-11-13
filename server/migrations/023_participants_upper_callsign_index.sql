-- Add functional index on UPPER(callsign) for participants table.
-- The club sync queries join on UPPER(p.callsign) = cm.callsign,
-- which can't use the existing idx_participants_callsign index.
CREATE INDEX IF NOT EXISTS idx_participants_upper_callsign ON participants(UPPER(callsign));
