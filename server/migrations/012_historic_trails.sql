-- National historic trails geometry cache (LineString, not Polygon)
-- Source: NPS National Trails System ArcGIS FeatureServer

CREATE TABLE historic_trails (
    trail_reference     TEXT PRIMARY KEY,
    trail_name          TEXT NOT NULL,
    designation         TEXT,
    managing_agency     TEXT,
    length_miles        DOUBLE PRECISION,
    state               TEXT,
    match_quality       TEXT NOT NULL,
    geometry            GEOMETRY(MultiLineString, 4326),
    geometry_simplified GEOMETRY(MultiLineString, 4326),
    source              TEXT NOT NULL DEFAULT 'nps_trails',
    fetched_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    matched_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_historic_trails_geom ON historic_trails USING GIST (geometry);
CREATE INDEX idx_historic_trails_geom_simple ON historic_trails USING GIST (geometry_simplified);

-- Seed catalog of the 19 congressionally-designated National Historic Trails
-- managed by NPS, BLM, and USFS. These serve as the reference list the
-- aggregator fetches geometry for.
CREATE TABLE historic_trail_catalog (
    trail_reference TEXT PRIMARY KEY,
    trail_name      TEXT NOT NULL,
    designation     TEXT NOT NULL DEFAULT 'National Historic Trail',
    managing_agency TEXT,
    states          TEXT,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

INSERT INTO historic_trail_catalog (trail_reference, trail_name, managing_agency, states) VALUES
('NHT-ALOM', 'Ala Kahakai National Historic Trail', 'NPS', 'HI'),
('NHT-CALI', 'California National Historic Trail', 'NPS', 'MO,KS,NE,CO,WY,ID,UT,NV,CA,OR'),
('NHT-CAPT', 'Captain John Smith Chesapeake National Historic Trail', 'NPS', 'VA,MD,DE,DC,PA,NY'),
('NHT-ELCA', 'El Camino Real de los Tejas National Historic Trail', 'NPS', 'TX,LA'),
('NHT-ELTI', 'El Camino Real de Tierra Adentro National Historic Trail', 'BLM', 'TX,NM'),
('NHT-IIMM', 'Iditarod National Historic Trail', 'BLM', 'AK'),
('NHT-LECL', 'Lewis and Clark National Historic Trail', 'NPS', 'IL,MO,KS,NE,IA,SD,ND,MT,ID,OR,WA'),
('NHT-MORM', 'Mormon Pioneer National Historic Trail', 'NPS', 'IL,IA,NE,WY,UT'),
('NHT-NEZE', 'Nez Perce National Historic Trail', 'USFS', 'OR,ID,WY,MT'),
('NHT-OREG', 'Oregon National Historic Trail', 'NPS', 'MO,KS,NE,WY,ID,OR'),
('NHT-OVLA', 'Overmountain Victory National Historic Trail', 'NPS', 'VA,TN,NC,SC'),
('NHT-PONY', 'Pony Express National Historic Trail', 'NPS', 'MO,KS,NE,CO,WY,UT,NV,CA'),
('NHT-SANT', 'Santa Fe National Historic Trail', 'NPS', 'MO,KS,OK,CO,NM'),
('NHT-SELM', 'Selma to Montgomery National Historic Trail', 'NPS', 'AL'),
('NHT-STAR', 'Star-Spangled Banner National Historic Trail', 'NPS', 'MD,VA,DC'),
('NHT-TOFT', 'Trail of Tears National Historic Trail', 'NPS', 'TN,GA,NC,AL,KY,IL,MO,AR,OK'),
('NHT-WASH', 'Washington-Rochambeau Revolutionary Route National Historic Trail', 'NPS', 'MA,RI,CT,NY,NJ,PA,DE,MD,VA,DC'),
('NHT-IOHR', 'Old Spanish National Historic Trail', 'NPS,BLM', 'NM,CO,UT,AZ,NV,CA'),
('NHT-SFPP', 'Santa Cruz Valley National Heritage Area Trail', 'NPS', 'AZ');
