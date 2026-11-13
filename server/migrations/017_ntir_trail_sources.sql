-- Add NTIR (NPS National Trails Intermountain Region) Feature Service names
-- as a secondary data source for trails not in the USGS National Map.
ALTER TABLE historic_trail_catalog ADD COLUMN ntir_service TEXT;

-- Map existing catalog trails to their NTIR Feature Service names
UPDATE historic_trail_catalog SET ntir_service = 'Ala_Kahakai_National_Historic_Trail_Official_Corridor' WHERE trail_reference = 'NHT-ALOM';
UPDATE historic_trail_catalog SET ntir_service = 'CALI_NHT' WHERE trail_reference = 'NHT-CALI';
UPDATE historic_trail_catalog SET ntir_service = 'CAJO_Captain_John_Smith_Chesapeake_NHT_Centerline_ln' WHERE trail_reference = 'NHT-CAPT';
UPDATE historic_trail_catalog SET ntir_service = 'ELCA_NHT' WHERE trail_reference = 'NHT-ELCA';
UPDATE historic_trail_catalog SET ntir_service = 'ELTE_NHT' WHERE trail_reference = 'NHT-ELTI';
UPDATE historic_trail_catalog SET ntir_service = 'Iditarod_National_Historic_Trail_BLM_Official_Temp' WHERE trail_reference = 'NHT-IIMM';
UPDATE historic_trail_catalog SET ntir_service = 'Lewis_and_Clark_National_Historic_Trail_Congressionally_Designated_Route' WHERE trail_reference = 'NHT-LECL';
UPDATE historic_trail_catalog SET ntir_service = 'MOPI_NHT' WHERE trail_reference = 'NHT-MORM';
UPDATE historic_trail_catalog SET ntir_service = 'OLSP_NHT' WHERE trail_reference = 'NHT-IOHR';
UPDATE historic_trail_catalog SET ntir_service = 'OREG_NHT' WHERE trail_reference = 'NHT-OREG';
UPDATE historic_trail_catalog SET ntir_service = 'Overmountain_Victory_National_Historic_Trail_Official_Temp' WHERE trail_reference = 'NHT-OVLA';
UPDATE historic_trail_catalog SET ntir_service = 'POEX_NHT' WHERE trail_reference = 'NHT-PONY';
UPDATE historic_trail_catalog SET ntir_service = 'SAFE_NHT' WHERE trail_reference = 'NHT-SANT';
UPDATE historic_trail_catalog SET ntir_service = 'Selma_to_Montgomery_National_Historic_Trail_Official' WHERE trail_reference = 'NHT-SELM';
UPDATE historic_trail_catalog SET ntir_service = 'Sta_Spangled_Banner_National_Historic_Trail_Official_Centerline' WHERE trail_reference = 'NHT-STAR';
UPDATE historic_trail_catalog SET ntir_service = 'TRTE_NHT' WHERE trail_reference = 'NHT-TOFT';
UPDATE historic_trail_catalog SET ntir_service = '20200622_2016_URI_WARO_NST_trail_centerline_states_combined_web_mercator' WHERE trail_reference = 'NHT-WASH';
UPDATE historic_trail_catalog SET ntir_service = 'JUBA_NHT_' WHERE trail_reference = 'NHT-ANZA';

-- Add Butterfield Overland Trail (only available from NTIR, not USGS)
INSERT INTO historic_trail_catalog (trail_reference, trail_name, managing_agency, states, ntir_service)
VALUES ('NHT-BTFD', 'Butterfield Overland National Historic Trail', 'NPS', 'MO,AR,OK,TX,NM,AZ,CA', 'NTIR_OTHER_ButterfieldOverlandTrailSRS_ln')
ON CONFLICT (trail_reference) DO NOTHING;
