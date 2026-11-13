-- Add consecutive_errors counter to skip permanently-failing trails
ALTER TABLE historic_trail_catalog ADD COLUMN consecutive_errors INTEGER NOT NULL DEFAULT 0;
