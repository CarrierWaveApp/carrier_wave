-- migrations/004_seed_friends.sql
-- Seed data for testing friend system features

-- Test users
INSERT INTO users (id, callsign, created_at) VALUES
    ('550e8400-e29b-41d4-a716-446655440001', 'W1TEST', '2024-01-15 10:30:00+00'),
    ('550e8400-e29b-41d4-a716-446655440002', 'W6JSV',  '2024-01-10 08:00:00+00'),
    ('550e8400-e29b-41d4-a716-446655440003', 'N3SEED', '2024-01-17 09:15:00+00'),
    ('550e8400-e29b-41d4-a716-446655440004', 'AA4DEV', '2024-01-18 16:45:00+00')
ON CONFLICT (callsign) DO NOTHING;

-- Friendship between W1TEST and W6JSV (bidirectional)
INSERT INTO friendships (id, user_id, friend_id, created_at) VALUES
    ('550e8400-e29b-41d4-a716-446655440101', '550e8400-e29b-41d4-a716-446655440001', '550e8400-e29b-41d4-a716-446655440002', '2024-01-20 12:00:00+00'),
    ('550e8400-e29b-41d4-a716-446655440102', '550e8400-e29b-41d4-a716-446655440002', '550e8400-e29b-41d4-a716-446655440001', '2024-01-20 12:00:00+00')
ON CONFLICT (user_id, friend_id) DO NOTHING;

-- Friend requests
INSERT INTO friend_requests (id, from_user_id, to_user_id, status, requested_at, responded_at) VALUES
    -- Accepted request that created the W1TEST <-> W6JSV friendship
    ('550e8400-e29b-41d4-a716-446655440201', '550e8400-e29b-41d4-a716-446655440001', '550e8400-e29b-41d4-a716-446655440002', 'accepted', '2024-01-19 14:00:00+00', '2024-01-20 12:00:00+00'),
    -- Pending request from N3SEED to W1TEST
    ('550e8400-e29b-41d4-a716-446655440202', '550e8400-e29b-41d4-a716-446655440003', '550e8400-e29b-41d4-a716-446655440001', 'pending', '2024-01-21 10:00:00+00', NULL)
ON CONFLICT (from_user_id, to_user_id) DO NOTHING;

-- Friend invites
INSERT INTO friend_invites (id, token, user_id, created_at, expires_at, used_at, used_by_user_id) VALUES
    -- Active invite from W1TEST
    ('550e8400-e29b-41d4-a716-446655440301', 'inv_w1testactiveinvite12345', '550e8400-e29b-41d4-a716-446655440001', '2024-01-22 10:00:00+00', '2025-02-22 10:00:00+00', NULL, NULL),
    -- Used invite (alternative flow for how friendship could have been created)
    ('550e8400-e29b-41d4-a716-446655440302', 'inv_usedinvitetoken1234567', '550e8400-e29b-41d4-a716-446655440001', '2024-01-18 10:00:00+00', '2024-02-18 10:00:00+00', '2024-01-20 12:00:00+00', '550e8400-e29b-41d4-a716-446655440002')
ON CONFLICT (token) DO NOTHING;
