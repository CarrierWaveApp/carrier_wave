-- Add Hamstick mono-band loaded whips and Hustler resonator modules (RMs)
-- to the equipment catalog. Each band is a separate SKU since both products
-- are sold per-band and users log them that way.

-- ==================== HAMSTICKS ====================
-- Originally a brand, "Hamstick" is now used generically for single-band
-- loaded whip antennas. MFJ Enterprises owns the trademark; aliases cover
-- common variations.

INSERT INTO equipment_catalog (id, name, manufacturer, category, bands, modes, portability, weight_grams, description, aliases) VALUES
('hamstick-80m', 'Hamstick 80m', 'MFJ Enterprises', 'antenna',
 ARRAY['80m'],
 ARRAY[]::TEXT[], 'mobile', 400,
 'Single-band 80m loaded whip antenna for mobile/portable HF',
 ARRAY['hamstick 80','hamstick-80','mfj-1680t','ham stick 80m','80m hamstick']),

('hamstick-60m', 'Hamstick 60m', 'MFJ Enterprises', 'antenna',
 ARRAY['60m'],
 ARRAY[]::TEXT[], 'mobile', 380,
 'Single-band 60m loaded whip antenna for mobile/portable HF',
 ARRAY['hamstick 60','hamstick-60','mfj-1660t','ham stick 60m','60m hamstick']),

('hamstick-40m', 'Hamstick 40m', 'MFJ Enterprises', 'antenna',
 ARRAY['40m'],
 ARRAY[]::TEXT[], 'mobile', 360,
 'Single-band 40m loaded whip antenna for mobile/portable HF',
 ARRAY['hamstick 40','hamstick-40','mfj-1640t','ham stick 40m','40m hamstick']),

('hamstick-30m', 'Hamstick 30m', 'MFJ Enterprises', 'antenna',
 ARRAY['30m'],
 ARRAY[]::TEXT[], 'mobile', 340,
 'Single-band 30m loaded whip antenna for mobile/portable HF',
 ARRAY['hamstick 30','hamstick-30','mfj-1630t','ham stick 30m','30m hamstick']),

('hamstick-20m', 'Hamstick 20m', 'MFJ Enterprises', 'antenna',
 ARRAY['20m'],
 ARRAY[]::TEXT[], 'mobile', 320,
 'Single-band 20m loaded whip antenna for mobile/portable HF',
 ARRAY['hamstick 20','hamstick-20','mfj-1620t','ham stick 20m','20m hamstick']),

('hamstick-17m', 'Hamstick 17m', 'MFJ Enterprises', 'antenna',
 ARRAY['17m'],
 ARRAY[]::TEXT[], 'mobile', 310,
 'Single-band 17m loaded whip antenna for mobile/portable HF',
 ARRAY['hamstick 17','hamstick-17','mfj-1617t','ham stick 17m','17m hamstick']),

('hamstick-15m', 'Hamstick 15m', 'MFJ Enterprises', 'antenna',
 ARRAY['15m'],
 ARRAY[]::TEXT[], 'mobile', 300,
 'Single-band 15m loaded whip antenna for mobile/portable HF',
 ARRAY['hamstick 15','hamstick-15','mfj-1615t','ham stick 15m','15m hamstick']),

('hamstick-12m', 'Hamstick 12m', 'MFJ Enterprises', 'antenna',
 ARRAY['12m'],
 ARRAY[]::TEXT[], 'mobile', 290,
 'Single-band 12m loaded whip antenna for mobile/portable HF',
 ARRAY['hamstick 12','hamstick-12','mfj-1612t','ham stick 12m','12m hamstick']),

('hamstick-10m', 'Hamstick 10m', 'MFJ Enterprises', 'antenna',
 ARRAY['10m'],
 ARRAY[]::TEXT[], 'mobile', 280,
 'Single-band 10m loaded whip antenna for mobile/portable HF',
 ARRAY['hamstick 10','hamstick-10','mfj-1610t','ham stick 10m','10m hamstick']),

('hamstick-6m', 'Hamstick 6m', 'MFJ Enterprises', 'antenna',
 ARRAY['6m'],
 ARRAY[]::TEXT[], 'mobile', 260,
 'Single-band 6m loaded whip antenna for mobile/portable VHF',
 ARRAY['hamstick 6','hamstick-6','mfj-1606t','ham stick 6m','6m hamstick','hamstick 6m']),

('hamstick-2m', 'Hamstick 2m', 'MFJ Enterprises', 'antenna',
 ARRAY['2m'],
 ARRAY[]::TEXT[], 'mobile', 230,
 'Single-band 2m loaded whip antenna for mobile/portable VHF',
 ARRAY['hamstick 2','hamstick-2','mfj-1602t','ham stick 2m','2m hamstick']);

-- ==================== HUSTLER RESONATOR MODULES ====================
-- Hustler RMs are mono-band loading coils that thread onto a Hustler MO-X
-- mast to form a mobile antenna. Sold individually per band.

INSERT INTO equipment_catalog (id, name, manufacturer, category, bands, modes, portability, weight_grams, description, aliases) VALUES
('hustler-rm-80', 'RM-80', 'Hustler', 'antenna',
 ARRAY['80m'],
 ARRAY[]::TEXT[], 'mobile', 540,
 '80m resonator module for Hustler mobile antenna system',
 ARRAY['rm-80','rm80','hustler 80','hustler resonator 80','rm 80']),

('hustler-rm-75', 'RM-75', 'Hustler', 'antenna',
 ARRAY['75m'],
 ARRAY[]::TEXT[], 'mobile', 540,
 '75m resonator module for Hustler mobile antenna system',
 ARRAY['rm-75','rm75','hustler 75','hustler resonator 75','rm 75']),

('hustler-rm-40', 'RM-40', 'Hustler', 'antenna',
 ARRAY['40m'],
 ARRAY[]::TEXT[], 'mobile', 480,
 '40m resonator module for Hustler mobile antenna system',
 ARRAY['rm-40','rm40','hustler 40','hustler resonator 40','rm 40']),

('hustler-rm-30', 'RM-30', 'Hustler', 'antenna',
 ARRAY['30m'],
 ARRAY[]::TEXT[], 'mobile', 420,
 '30m resonator module for Hustler mobile antenna system',
 ARRAY['rm-30','rm30','hustler 30','hustler resonator 30','rm 30']),

('hustler-rm-20', 'RM-20', 'Hustler', 'antenna',
 ARRAY['20m'],
 ARRAY[]::TEXT[], 'mobile', 360,
 '20m resonator module for Hustler mobile antenna system',
 ARRAY['rm-20','rm20','hustler 20','hustler resonator 20','rm 20']),

('hustler-rm-17', 'RM-17', 'Hustler', 'antenna',
 ARRAY['17m'],
 ARRAY[]::TEXT[], 'mobile', 320,
 '17m resonator module for Hustler mobile antenna system',
 ARRAY['rm-17','rm17','hustler 17','hustler resonator 17','rm 17']),

('hustler-rm-15', 'RM-15', 'Hustler', 'antenna',
 ARRAY['15m'],
 ARRAY[]::TEXT[], 'mobile', 280,
 '15m resonator module for Hustler mobile antenna system',
 ARRAY['rm-15','rm15','hustler 15','hustler resonator 15','rm 15']),

('hustler-rm-12', 'RM-12', 'Hustler', 'antenna',
 ARRAY['12m'],
 ARRAY[]::TEXT[], 'mobile', 260,
 '12m resonator module for Hustler mobile antenna system',
 ARRAY['rm-12','rm12','hustler 12','hustler resonator 12','rm 12']),

('hustler-rm-10', 'RM-10', 'Hustler', 'antenna',
 ARRAY['10m'],
 ARRAY[]::TEXT[], 'mobile', 240,
 '10m resonator module for Hustler mobile antenna system',
 ARRAY['rm-10','rm10','hustler 10','hustler resonator 10','rm 10']),

('hustler-rm-6', 'RM-6', 'Hustler', 'antenna',
 ARRAY['6m'],
 ARRAY[]::TEXT[], 'mobile', 200,
 '6m resonator module for Hustler mobile antenna system',
 ARRAY['rm-6','rm6','hustler 6','hustler resonator 6','rm 6']),

('hustler-mo-x', 'MO-X', 'Hustler', 'antenna',
 ARRAY[]::TEXT[],
 ARRAY[]::TEXT[], 'mobile', 450,
 'Hustler mobile antenna mast — accepts RM resonator modules',
 ARRAY['mo-x','mox','mo x','hustler mast','hustler mo','hustler mo-x mast']);
