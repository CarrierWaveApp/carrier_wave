-- Add consecutive_errors counter to skip permanently-failing parks
ALTER TABLE pota_fetch_status ADD COLUMN consecutive_errors INTEGER NOT NULL DEFAULT 0;
