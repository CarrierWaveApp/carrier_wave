-- Add logo storage columns to clubs table
ALTER TABLE clubs ADD COLUMN logo_data BYTEA;
ALTER TABLE clubs ADD COLUMN logo_content_type TEXT;
