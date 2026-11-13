-- Add the Brass Knuckle Gang (BKG) as a callsign enrichment source.
-- Membership list is published in Ham2K PoLo notes format (one callsign per
-- line), e.g. `AA6XV 🤜 Dave W BKG #29`, so the existing 'polo' parser handles
-- it directly once we strip the trailing "BKG" tag (handled in code).

INSERT INTO callsign_enrichment_sources (slug, name, url, format, emoji)
VALUES (
    'bkg',
    'Brass Knuckle Gang',
    'https://www.bkg.club/members.txt',
    'polo',
    '🤜'
)
ON CONFLICT (slug) DO NOTHING;
