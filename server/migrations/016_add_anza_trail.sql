-- Add Juan Bautista de Anza National Historic Trail to the catalog.
-- This trail has geometry in the NPS dataset but was missing from the seed data.
INSERT INTO historic_trail_catalog (trail_reference, trail_name, managing_agency, states)
VALUES ('NHT-ANZA', 'Juan Bautista de Anza National Historic Trail', 'NPS', 'AZ,CA')
ON CONFLICT (trail_reference) DO NOTHING;
