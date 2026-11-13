-- migrations/003_friend_system.sql
-- Friend system: users, friend requests, and friend invite links

-- Users table (canonical user identity by callsign)
CREATE TABLE users (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    callsign        TEXT NOT NULL UNIQUE,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_users_callsign ON users(callsign);

-- Populate users from existing participants
INSERT INTO users (callsign, created_at)
SELECT DISTINCT callsign, MIN(created_at)
FROM participants
GROUP BY callsign
ON CONFLICT (callsign) DO NOTHING;

-- Friend requests between users
CREATE TABLE friend_requests (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    from_user_id    UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    to_user_id      UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    status          TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'accepted', 'declined')),
    requested_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    responded_at    TIMESTAMPTZ,
    UNIQUE(from_user_id, to_user_id)
);

CREATE INDEX idx_friend_requests_from ON friend_requests(from_user_id);
CREATE INDEX idx_friend_requests_to ON friend_requests(to_user_id);
CREATE INDEX idx_friend_requests_status ON friend_requests(status) WHERE status = 'pending';

-- Friendships (accepted friend requests create entries here for efficient queries)
CREATE TABLE friendships (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id         UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    friend_id       UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE(user_id, friend_id)
);

CREATE INDEX idx_friendships_user ON friendships(user_id);
CREATE INDEX idx_friendships_friend ON friendships(friend_id);

-- Friend invite links
CREATE TABLE friend_invites (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    token           VARCHAR(64) NOT NULL UNIQUE,
    user_id         UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    expires_at      TIMESTAMPTZ NOT NULL,
    used_at         TIMESTAMPTZ,
    used_by_user_id UUID REFERENCES users(id),

    CONSTRAINT friend_invite_token_format CHECK (token ~ '^inv_[a-zA-Z0-9]{20,}$')
);

CREATE INDEX idx_friend_invites_token ON friend_invites(token);
CREATE INDEX idx_friend_invites_user ON friend_invites(user_id);
CREATE INDEX idx_friend_invites_expires ON friend_invites(expires_at);
