-- Profile achievement system (user-facing label: "Badges").
-- Distinct from the existing `badges` table, which stores image artifacts
-- attached to a single challenge. Achievements are ecosystem-wide milestones
-- and identity markers that users collect on their profile.

CREATE TABLE achievements (
    id              TEXT PRIMARY KEY,
    name            TEXT NOT NULL,
    description     TEXT NOT NULL,
    category        TEXT NOT NULL,
    tier            TEXT,
    icon_name       TEXT NOT NULL,
    accent_hex      TEXT,
    award_method    TEXT NOT NULL,
    secret          BOOLEAN NOT NULL DEFAULT FALSE,
    sort_order      INTEGER NOT NULL DEFAULT 0,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE user_achievements (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    callsign        TEXT NOT NULL,
    achievement_id  TEXT NOT NULL REFERENCES achievements(id) ON DELETE CASCADE,
    awarded_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    awarded_by      TEXT,
    evidence        JSONB,
    UNIQUE(callsign, achievement_id)
);

CREATE INDEX idx_user_achievements_callsign ON user_achievements(callsign);
CREATE INDEX idx_user_achievements_achievement ON user_achievements(achievement_id);

-- Seed catalog. award_method is one of:
--   'manual' — granted by an admin via /v1/admin/achievements/:id/award
--   'auto'   — server-side evaluator (implemented separately; placeholder for now)
--   'signal' — client emits a signal event the server validates (e.g. ecosystem usage)
INSERT INTO achievements (id, name, description, category, tier, icon_name, accent_hex, award_method, secret, sort_order) VALUES
    -- Creator / community (manual)
    ('creator',           'Creator',          'Built Carrier Wave',                                     'creator',   NULL, 'hammer.fill',          '#FFB74D', 'manual', FALSE,   0),
    ('beta-tester',       'Beta Tester',      'Helped shape Carrier Wave during beta',                  'community', NULL, 'flask.fill',           '#7E57C2', 'manual', FALSE,  10),
    ('founding-supporter','Founding Supporter','Joined in the first wave',                              'community', NULL, 'star.circle.fill',     '#FFD54F', 'manual', FALSE,  20),
    ('contributor',       'Contributor',      'Contributed code, translations, or content',             'community', NULL, 'chevron.left.forwardslash.chevron.right', '#4FC3F7', 'manual', FALSE, 30),
    ('bug-hunter',        'Bug Hunter',       'Reported a bug we shipped a fix for',                    'community', NULL, 'ant.fill',             '#A1887F', 'manual', FALSE,  40),

    -- Logbook milestones (auto)
    ('first-qso',         'First QSO',        'Logged your first contact',                              'activity',  NULL,       'antenna.radiowaves.left.and.right', '#4CAF50', 'auto', FALSE, 100),
    ('qso-100',           'Centurion',        'Logged 100 contacts',                                    'activity',  'bronze',   'antenna.radiowaves.left.and.right', '#CD7F32', 'auto', FALSE, 110),
    ('qso-1000',          'Kilo Op',          'Logged 1,000 contacts',                                  'activity',  'silver',   'antenna.radiowaves.left.and.right', '#C0C0C0', 'auto', FALSE, 120),
    ('qso-10000',         'Iron Fist',        'Logged 10,000 contacts',                                 'activity',  'gold',     'antenna.radiowaves.left.and.right', '#FFD700', 'auto', FALSE, 130),
    ('dxcc-10',           'DX Curious',       'Worked 10 DXCC entities',                                'activity',  'bronze',   'globe',                             '#CD7F32', 'auto', FALSE, 140),
    ('dxcc-100',          'DXCC',             'Worked 100 DXCC entities',                               'activity',  'gold',     'globe',                             '#FFD700', 'auto', FALSE, 150),
    ('was',               'Worked All States','Confirmed contacts in all 50 US states',                 'activity',  NULL,       'flag.fill',                         '#1976D2', 'auto', FALSE, 160),
    ('wac',               'Worked All Continents','Worked all six continents',                          'activity',  NULL,       'globe.americas.fill',               '#1976D2', 'auto', FALSE, 170),
    ('grid-50',           'Gridhopper',       'Worked 50 different Maidenhead grids',                   'activity',  NULL,       'square.grid.3x3.fill',              '#26A69A', 'auto', FALSE, 180),

    -- Mode / band specific (auto)
    ('first-cw',          'CW Op',            'First contact in CW',                                    'activity',  NULL,       'dot.radiowaves.right',              '#8D6E63', 'auto', FALSE, 200),
    ('first-ft8',         'FT8 Op',           'First contact in FT8',                                   'activity',  NULL,       'waveform',                          '#5E35B1', 'auto', FALSE, 210),
    ('first-ssb',         'SSB Op',           'First voice contact',                                    'activity',  NULL,       'mic.fill',                          '#EF5350', 'auto', FALSE, 220),
    ('mode-polyglot',     'Polyglot',         'Worked five or more modes',                              'activity',  NULL,       'rectangle.stack.fill',              '#7B1FA2', 'auto', FALSE, 230),
    ('all-hf',            'All HF Bands',     'Worked every HF band from 160m to 10m',                  'activity',  NULL,       'chart.bar.fill',                    '#0288D1', 'auto', FALSE, 240),
    ('qrp-dx',            'QRP DX',           'Worked DX over 5,000 km at 5W or less',                  'activity',  NULL,       'leaf.fill',                         '#43A047', 'auto', FALSE, 250),

    -- Ecosystem usage (signal)
    ('sweep-user',        'Sweep User',       'Paired Field with the macOS companion',                  'ecosystem', NULL,       'desktopcomputer',                   '#90CAF9', 'signal', FALSE, 300),
    ('watch-operator',    'Watch Operator',   'Logged a contact from Apple Watch',                      'ecosystem', NULL,       'applewatch',                        '#90CAF9', 'signal', FALSE, 310),
    ('home-screen',       'Home Screen',      'Added a Carrier Wave widget to your Home Screen',        'ecosystem', NULL,       'square.grid.2x2.fill',              '#90CAF9', 'signal', FALSE, 320),
    ('pebble-pioneer',    'Pebble Pioneer',   'Used the Pebble Time companion',                         'ecosystem', NULL,       'applewatch.watchface',              '#FF9800', 'signal', FALSE, 330),
    ('swl',               'SWL',              'Recorded a band with CW SWL',                            'ecosystem', NULL,       'waveform.badge.magnifyingglass',    '#90CAF9', 'signal', FALSE, 340),
    ('rbn-spotter',       'RBN Spotter',      'Submitted spots through the RBN proxy',                  'ecosystem', NULL,       'dot.scope',                         '#90CAF9', 'signal', FALSE, 350),
    ('cross-platform',    'Cross-Platform',   'Logged from iOS and macOS in the same week',             'ecosystem', NULL,       'arrow.triangle.2.circlepath',       '#90CAF9', 'auto',   FALSE, 360),

    -- Cadence / streaks (auto)
    ('streak-7',          'Weekly Op',        '7-day logging streak',                                   'streak',    'bronze',   'flame.fill',                        '#FF7043', 'auto', FALSE, 400),
    ('streak-30',         'Monthly Op',       '30-day logging streak',                                  'streak',    'silver',   'flame.fill',                        '#FF5722', 'auto', FALSE, 410),
    ('streak-365',        'Year of Radio',    '365-day logging streak',                                 'streak',    'gold',     'flame.fill',                        '#E64A19', 'auto', FALSE, 420),
    ('field-day',         'Field Day',        'Operated during ARRL Field Day',                         'streak',    NULL,       'tent.fill',                         '#558B2F', 'auto', FALSE, 430),
    ('anniversary',       'One Year On',      'A year as a Carrier Wave user',                          'streak',    NULL,       'birthday.cake.fill',                '#EC407A', 'auto', FALSE, 440),

    -- Quirky / community (auto, secret)
    ('night-owl',         'Night Owl',        'Logged a contact between 0200 and 0400 local',           'quirky',    NULL,       'moon.stars.fill',                   '#5C6BC0', 'auto', TRUE,  500),
    ('eyeball',           'Eyeball QSO',      'Worked another Carrier Wave user',                       'quirky',    NULL,       'eye.fill',                          '#26A69A', 'auto', TRUE,  510),
    ('solar-storm',       'Solar Storm Op',   'Logged a contact during a Kp ≥ 7 geomagnetic storm',     'quirky',    NULL,       'bolt.fill',                         '#F57F17', 'auto', TRUE,  520);

-- Pre-seed the creator awards.
INSERT INTO user_achievements (callsign, achievement_id, awarded_by) VALUES
    ('W6JY', 'creator', 'system'),
    ('N9HO', 'creator', 'system');
