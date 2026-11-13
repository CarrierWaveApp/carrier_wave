-- migrations/005_activities.sql
-- Activities table for storing reported user activities (feed items)

CREATE TABLE activities (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id         UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    callsign        TEXT NOT NULL,
    activity_type   TEXT NOT NULL,
    timestamp       TIMESTAMPTZ NOT NULL,
    details         JSONB NOT NULL DEFAULT '{}',
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Per-user queries (e.g. "my recent activities")
CREATE INDEX idx_activities_user_timestamp ON activities(user_id, timestamp DESC);

-- Cursor-based pagination for feed queries
CREATE INDEX idx_activities_created_at ON activities(created_at DESC);

-- Feed query: activities from friends via friendships join
-- Covers: SELECT ... FROM activities a JOIN friendships f ON f.friend_id = a.user_id WHERE f.user_id = $1
CREATE INDEX idx_activities_user_id ON activities(user_id);
