-- Club roster sync bookkeeping.
--
-- Clubs with a `notes_url` (Ham2K PoLo callsign-notes file) now have their
-- roster reconciled against that file on a schedule by the club_rosters
-- aggregator, instead of only when an admin triggers the import by hand.
-- These columns record the outcome of the last attempt so an out-of-date
-- roster can be diagnosed from the admin club list.

ALTER TABLE clubs ADD COLUMN roster_synced_at TIMESTAMPTZ;
ALTER TABLE clubs ADD COLUMN roster_sync_status TEXT;   -- 'ok' / 'error: …'
