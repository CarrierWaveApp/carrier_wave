-- Add the Straight Key Century Club (SKCC) as a callsign enrichment source.
-- Roster is published in Ham2K PoLo notes format at the canonical mirror
-- on ditdit.club, generated upstream by qrqcrew-notes-daemon (which now
-- normalises retired callsigns to their canonical form via QRZ).

INSERT INTO callsign_enrichment_sources (slug, name, url, format, emoji)
VALUES (
    'skcc',
    'Straight Key Century Club',
    'https://www.ditdit.club/data/skcc_members.txt',
    'polo',
    '🔑'
)
ON CONFLICT (slug) DO NOTHING;
