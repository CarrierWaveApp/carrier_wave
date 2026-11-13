-- Audit log of callsign changes, keyed to the stable user UUID
CREATE TABLE callsign_history (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id         UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    old_callsign    TEXT NOT NULL,
    new_callsign    TEXT NOT NULL,
    changed_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_callsign_history_user_id ON callsign_history(user_id);
CREATE INDEX idx_callsign_history_old ON callsign_history(old_callsign);
