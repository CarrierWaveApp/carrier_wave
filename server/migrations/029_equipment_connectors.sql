-- Add connector columns to equipment_catalog for adapter compatibility tracking
ALTER TABLE equipment_catalog ADD COLUMN antenna_connector TEXT;
ALTER TABLE equipment_catalog ADD COLUMN power_connector TEXT;
ALTER TABLE equipment_catalog ADD COLUMN key_jack TEXT;
ALTER TABLE equipment_catalog ADD COLUMN mic_jack TEXT;
