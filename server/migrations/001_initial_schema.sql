-- migrations/001_initial_schema.sql

-- Challenge definitions
CREATE TABLE challenges (
    id              UUID PRIMARY KEY,
    version         INT NOT NULL DEFAULT 1,
    name            TEXT NOT NULL,
    description     TEXT NOT NULL,
    author          TEXT,
    category        TEXT NOT NULL CHECK (category IN ('award', 'event', 'club', 'personal', 'other')),
    challenge_type  TEXT NOT NULL CHECK (challenge_type IN ('collection', 'cumulative', 'timeBounded')),
    configuration   JSONB NOT NULL,
    invite_config   JSONB,
    hamalert_config JSONB,
    is_active       BOOLEAN NOT NULL DEFAULT true,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Participants and their device tokens
CREATE TABLE participants (
    id              UUID PRIMARY KEY,
    callsign        TEXT NOT NULL,
    device_token    TEXT NOT NULL UNIQUE,
    device_name     TEXT,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    last_seen_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_participants_callsign ON participants(callsign);
CREATE INDEX idx_participants_device_token ON participants(device_token);

-- Challenge participation
CREATE TABLE challenge_participants (
    id              UUID PRIMARY KEY,
    challenge_id    UUID NOT NULL REFERENCES challenges(id) ON DELETE CASCADE,
    callsign        TEXT NOT NULL,
    invite_token    TEXT,
    joined_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    status          TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'left', 'completed')),
    UNIQUE(challenge_id, callsign)
);
CREATE INDEX idx_challenge_participants_challenge ON challenge_participants(challenge_id);
CREATE INDEX idx_challenge_participants_callsign ON challenge_participants(callsign);

-- Progress tracking
CREATE TABLE progress (
    id              UUID PRIMARY KEY,
    challenge_id    UUID NOT NULL REFERENCES challenges(id) ON DELETE CASCADE,
    callsign        TEXT NOT NULL,
    completed_goals JSONB NOT NULL DEFAULT '[]',
    current_value   INT NOT NULL DEFAULT 0,
    score           INT NOT NULL DEFAULT 0,
    current_tier    TEXT,
    last_qso_date   TIMESTAMPTZ,
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE(challenge_id, callsign)
);
CREATE INDEX idx_progress_leaderboard ON progress(challenge_id, score DESC, updated_at ASC);

-- Badges
CREATE TABLE badges (
    id              UUID PRIMARY KEY,
    challenge_id    UUID NOT NULL REFERENCES challenges(id) ON DELETE CASCADE,
    name            TEXT NOT NULL,
    tier_id         TEXT,
    image_data      BYTEA NOT NULL,
    content_type    TEXT NOT NULL,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_badges_challenge ON badges(challenge_id);

-- Earned badges
CREATE TABLE earned_badges (
    id              UUID PRIMARY KEY,
    badge_id        UUID NOT NULL REFERENCES badges(id) ON DELETE CASCADE,
    callsign        TEXT NOT NULL,
    earned_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE(badge_id, callsign)
);
CREATE INDEX idx_earned_badges_callsign ON earned_badges(callsign);

-- Challenge snapshots (frozen leaderboards)
CREATE TABLE challenge_snapshots (
    id              UUID PRIMARY KEY,
    challenge_id    UUID NOT NULL REFERENCES challenges(id) ON DELETE CASCADE,
    ended_at        TIMESTAMPTZ NOT NULL,
    final_standings JSONB NOT NULL,
    statistics      JSONB,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_challenge_snapshots_challenge ON challenge_snapshots(challenge_id);

-- Invite tokens
CREATE TABLE invite_tokens (
    token           TEXT PRIMARY KEY,
    challenge_id    UUID NOT NULL REFERENCES challenges(id) ON DELETE CASCADE,
    max_uses        INT,
    use_count       INT NOT NULL DEFAULT 0,
    expires_at      TIMESTAMPTZ,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_invite_tokens_challenge ON invite_tokens(challenge_id);
