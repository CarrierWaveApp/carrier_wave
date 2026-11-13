-- Award the beta-tester achievement to the initial group of testers who
-- helped shape Carrier Wave during the closed beta. Idempotent via the
-- UNIQUE(callsign, achievement_id) constraint on user_achievements.

INSERT INTO user_achievements (callsign, achievement_id, awarded_by) VALUES
    ('KI5GTR', 'beta-tester', 'system'),
    ('VA4ADM', 'beta-tester', 'system'),
    ('NW6U',   'beta-tester', 'system'),
    ('SP2HF',  'beta-tester', 'system'),
    ('WD4DHW', 'beta-tester', 'system'),
    ('KF8BNW', 'beta-tester', 'system'),
    ('WA0OTO', 'beta-tester', 'system'),
    ('AC4NK',  'beta-tester', 'system'),
    ('AC9M',   'beta-tester', 'system'),
    ('W1WC',   'beta-tester', 'system'),
    ('W6PUG',  'beta-tester', 'system'),
    ('KG5VNQ', 'beta-tester', 'system'),
    ('WI7M',   'beta-tester', 'system')
ON CONFLICT (callsign, achievement_id) DO NOTHING;
