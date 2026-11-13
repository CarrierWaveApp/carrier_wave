-- Award the founding-supporter achievement to the same group that received
-- beta-tester in migration 035 — they were the first wave of operators on
-- Carrier Wave. Idempotent via the UNIQUE(callsign, achievement_id)
-- constraint on user_achievements.

INSERT INTO user_achievements (callsign, achievement_id, awarded_by) VALUES
    ('KI5GTR', 'founding-supporter', 'system'),
    ('VA4ADM', 'founding-supporter', 'system'),
    ('NW6U',   'founding-supporter', 'system'),
    ('SP2HF',  'founding-supporter', 'system'),
    ('WD4DHW', 'founding-supporter', 'system'),
    ('KF8BNW', 'founding-supporter', 'system'),
    ('WA0OTO', 'founding-supporter', 'system'),
    ('AC4NK',  'founding-supporter', 'system'),
    ('AC9M',   'founding-supporter', 'system'),
    ('W1WC',   'founding-supporter', 'system'),
    ('W6PUG',  'founding-supporter', 'system'),
    ('KG5VNQ', 'founding-supporter', 'system'),
    ('WI7M',   'founding-supporter', 'system')
ON CONFLICT (callsign, achievement_id) DO NOTHING;

-- AC4NK additionally receives the contributor achievement for code/content
-- contributions to Carrier Wave.
INSERT INTO user_achievements (callsign, achievement_id, awarded_by) VALUES
    ('AC4NK', 'contributor', 'system')
ON CONFLICT (callsign, achievement_id) DO NOTHING;
