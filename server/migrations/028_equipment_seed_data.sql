-- Seed data for equipment catalog: portable/POTA-popular amateur radio gear

-- ==================== RADIOS ====================

INSERT INTO equipment_catalog (id, name, manufacturer, category, bands, modes, max_power_watts, portability, weight_grams, description, aliases) VALUES
('elecraft-kx2', 'KX2', 'Elecraft', 'radio',
 ARRAY['80m','60m','40m','30m','20m','17m','15m','12m','10m'],
 ARRAY['CW','SSB','DIGITAL'], 10, 'backpack', 370,
 'All-band QRP transceiver with built-in ATU',
 ARRAY['kx-2','kx 2']),

('elecraft-kx3', 'KX3', 'Elecraft', 'radio',
 ARRAY['160m','80m','60m','40m','30m','20m','17m','15m','12m','10m','6m'],
 ARRAY['CW','SSB','AM','FM','DIGITAL'], 15, 'backpack', 500,
 'Full-featured all-band QRP transceiver',
 ARRAY['kx-3','kx 3']),

('elecraft-kh1', 'KH1', 'Elecraft', 'radio',
 ARRAY['40m','30m','20m','17m','15m'],
 ARRAY['CW'], 5, 'pocket', 400,
 'Ultra-portable CW transceiver with built-in paddle and ATU',
 ARRAY['kh-1','kh 1']),

('elecraft-k3', 'K3', 'Elecraft', 'radio',
 ARRAY['160m','80m','60m','40m','30m','20m','17m','15m','12m','10m','6m'],
 ARRAY['CW','SSB','AM','FM','DIGITAL'], 100, 'base', 4200,
 'High-performance HF/6m transceiver',
 ARRAY['k-3']),

('elecraft-k3s', 'K3S', 'Elecraft', 'radio',
 ARRAY['160m','80m','60m','40m','30m','20m','17m','15m','12m','10m','6m'],
 ARRAY['CW','SSB','AM','FM','DIGITAL'], 100, 'base', 4200,
 'Updated high-performance HF/6m transceiver',
 ARRAY['k-3s','k3 s']),

('elecraft-k4', 'K4', 'Elecraft', 'radio',
 ARRAY['160m','80m','60m','40m','30m','20m','17m','15m','12m','10m','6m'],
 ARRAY['CW','SSB','AM','FM','DIGITAL'], 100, 'base', 6800,
 'High-performance direct-sampling SDR transceiver',
 ARRAY['k-4']),

('icom-ic705', 'IC-705', 'Icom', 'radio',
 ARRAY['160m','80m','60m','40m','30m','20m','17m','15m','12m','10m','6m','2m','70cm'],
 ARRAY['CW','SSB','AM','FM','DIGITAL'], 10, 'backpack', 1000,
 'All-band all-mode portable transceiver with D-STAR',
 ARRAY['ic705','ic 705','705']),

('icom-ic7300', 'IC-7300', 'Icom', 'radio',
 ARRAY['160m','80m','60m','40m','30m','20m','17m','15m','12m','10m','6m'],
 ARRAY['CW','SSB','AM','FM','DIGITAL'], 100, 'base', 4200,
 'HF/50MHz direct-sampling SDR transceiver',
 ARRAY['ic7300','ic 7300','7300']),

('yaesu-ft891', 'FT-891', 'Yaesu', 'radio',
 ARRAY['160m','80m','60m','40m','30m','20m','17m','15m','12m','10m','6m'],
 ARRAY['CW','SSB','AM','FM','DIGITAL'], 100, 'mobile', 2800,
 'Compact HF/50MHz all-mode transceiver',
 ARRAY['ft891','ft 891']),

('yaesu-ft818', 'FT-818ND', 'Yaesu', 'radio',
 ARRAY['160m','80m','60m','40m','30m','20m','17m','15m','12m','10m','6m','2m','70cm'],
 ARRAY['CW','SSB','AM','FM','DIGITAL'], 6, 'backpack', 900,
 'All-band all-mode QRP portable transceiver',
 ARRAY['ft818','ft 818','ft-817','ft817','ft 817']),

('yaesu-ft991a', 'FT-991A', 'Yaesu', 'radio',
 ARRAY['160m','80m','60m','40m','30m','20m','17m','15m','12m','10m','6m','2m','70cm'],
 ARRAY['CW','SSB','AM','FM','DIGITAL'], 100, 'base', 4300,
 'All-band all-mode transceiver with C4FM',
 ARRAY['ft991a','ft991','ft 991a','ft 991']),

('lnr-mtr3b', 'Mountain Topper MTR-3B', 'LNR Precision', 'radio',
 ARRAY['40m','30m','20m'],
 ARRAY['CW'], 3, 'pocket', 340,
 '3-band QRP CW transceiver',
 ARRAY['mtr3b','mtr-3b','mountain topper 3b','mtr 3b']),

('lnr-mtr4b', 'Mountain Topper MTR-4B', 'LNR Precision', 'radio',
 ARRAY['40m','30m','20m','15m'],
 ARRAY['CW'], 3, 'pocket', 340,
 '4-band QRP CW transceiver',
 ARRAY['mtr4b','mtr-4b','mountain topper 4b','mtr 4bv2']),

('lnr-mtr5b', 'Mountain Topper MTR-5B', 'LNR Precision', 'radio',
 ARRAY['40m','30m','20m','17m','15m'],
 ARRAY['CW'], 3, 'pocket', 350,
 '5-band QRP CW transceiver',
 ARRAY['mtr5b','mtr-5b','mountain topper 5b']),

('qrplabs-qmx', 'QMX', 'QRP Labs', 'radio',
 ARRAY['80m','60m','40m','30m','20m','17m','15m'],
 ARRAY['CW','DIGITAL'], 5, 'pocket', 200,
 'Multi-band QRP CW and digital transceiver',
 ARRAY['qmx']),

('qrplabs-qdx', 'QDX', 'QRP Labs', 'radio',
 ARRAY['80m','40m','30m','20m','17m','15m'],
 ARRAY['DIGITAL'], 5, 'pocket', 100,
 'Digital-mode QRP transceiver for FT8/FT4/WSPR',
 ARRAY['qdx']),

('xiegu-g90', 'G90', 'Xiegu', 'radio',
 ARRAY['160m','80m','60m','40m','30m','20m','17m','15m','12m','10m'],
 ARRAY['CW','SSB','AM','DIGITAL'], 20, 'portable', 950,
 'Compact HF SDR transceiver with built-in ATU',
 ARRAY['g-90']),

('xiegu-x6100', 'X6100', 'Xiegu', 'radio',
 ARRAY['160m','80m','60m','40m','30m','20m','17m','15m','12m','10m','6m','2m','70cm'],
 ARRAY['CW','SSB','AM','FM','DIGITAL'], 10, 'backpack', 900,
 'Portable SDR all-band transceiver with touchscreen',
 ARRAY['x-6100','x 6100']),

('lab599-tx500', 'TX-500', 'Lab599', 'radio',
 ARRAY['160m','80m','60m','40m','30m','20m','17m','15m','12m','10m','6m'],
 ARRAY['CW','SSB','AM','DIGITAL'], 10, 'backpack', 800,
 'Ruggedized portable HF/50MHz transceiver',
 ARRAY['tx500','tx 500']);

-- ==================== ANTENNAS ====================

INSERT INTO equipment_catalog (id, name, manufacturer, category, bands, modes, portability, weight_grams, description, aliases) VALUES
('efhw-4010', 'EFHW 40-10', 'Various', 'antenna',
 ARRAY['40m','20m','15m','10m'],
 ARRAY[]::TEXT[], 'backpack', 200,
 'End-fed half-wave antenna for 40-10m',
 ARRAY['efhw','end fed half wave','end-fed','endfed']),

('spooltenna', 'Spooltenna', 'Spooltenna', 'antenna',
 ARRAY['40m','30m','20m','17m','15m','12m','10m'],
 ARRAY[]::TEXT[], 'pocket', 100,
 'Ultralight spooled wire EFHW antenna',
 ARRAY['spool antenna','spooled antenna']),

('chameleon-mpas2', 'MPAS 2.0', 'Chameleon Antenna', 'antenna',
 ARRAY['160m','80m','60m','40m','30m','20m','17m','15m','12m','10m','6m'],
 ARRAY[]::TEXT[], 'portable', 2300,
 'Modular portable antenna system',
 ARRAY['mpas','mpas2','chameleon mpas','mpas 2']),

('buddipole', 'Buddipole', 'Buddipole', 'antenna',
 ARRAY['40m','30m','20m','17m','15m','12m','10m','6m','2m'],
 ARRAY[]::TEXT[], 'portable', 1600,
 'Portable dipole antenna system',
 ARRAY['buddi pole','buddy pole']),

('sotabeams-band-hopper', 'Band Hopper', 'SOTAbeams', 'antenna',
 ARRAY['40m','30m','20m'],
 ARRAY[]::TEXT[], 'backpack', 150,
 'Lightweight linked dipole for SOTA/POTA',
 ARRAY['band hopper','bandhopper','sota beams band hopper']),

('packtenna-efhw', 'EFHW Mini', 'PackTenna', 'antenna',
 ARRAY['40m','20m','15m','10m'],
 ARRAY[]::TEXT[], 'pocket', 120,
 'Ultralight end-fed half-wave for portable ops',
 ARRAY['packtenna','pack tenna']),

('wolf-river-slt', 'Silver Bullet TIA', 'Wolf River Coils', 'antenna',
 ARRAY['80m','60m','40m','30m','20m','17m','15m','12m','10m','6m'],
 ARRAY[]::TEXT[], 'portable', 1400,
 'Portable HF vertical with loading coil',
 ARRAY['wolf river','silver bullet','slt','wrc']),

('superantenna-mp1', 'MP-1', 'Super Antenna', 'antenna',
 ARRAY['80m','40m','20m','15m','10m','6m','2m'],
 ARRAY[]::TEXT[], 'portable', 700,
 'Portable all-band HF/VHF vertical antenna',
 ARRAY['mp1','mp 1','super antenna mp1']),

('linked-dipole', 'Linked Dipole', 'Various', 'antenna',
 ARRAY['40m','20m','15m','10m'],
 ARRAY[]::TEXT[], 'backpack', 300,
 'Multi-band linked dipole antenna',
 ARRAY['linked dipole antenna']);

-- ==================== KEYS / PADDLES ====================

INSERT INTO equipment_catalog (id, name, manufacturer, category, portability, weight_grams, description, aliases) VALUES
('cwmorse-tpiii', 'Pocket Morse TP-III', 'CW Morse', 'key',
 'pocket', 85,
 'Ultra-compact single-lever paddle',
 ARRAY['tp-iii','tp3','tpiii','tp-3','cw morse tp3']),

('cwmorse-tpi', 'Pocket Morse TP-I', 'CW Morse', 'key',
 'pocket', 50,
 'Micro single-lever paddle',
 ARRAY['tp-i','tp1','tpi','tp-1','cw morse tp1']),

('begali-traveler', 'Traveler', 'Begali', 'key',
 'pocket', 180,
 'Premium portable iambic paddle',
 ARRAY['begali traveller','begali travel']),

('vibroplex-code-mite', 'Code Mite', 'Vibroplex', 'key',
 'pocket', 130,
 'Compact portable paddle',
 ARRAY['code mite','codemite']),

('n0sa-pocket-paddle', 'Pocket Paddle', 'N0SA', 'key',
 'pocket', 40,
 'Ultralight pocket paddle for portable CW',
 ARRAY['n0sa','n0sa paddle']),

('palm-pico', 'Pico Paddle', 'Palm Radio', 'key',
 'pocket', 30,
 'Miniature iambic paddle',
 ARRAY['palm paddle','pico','palm pico']),

('ame-porta-paddle', 'Porta-Paddle', 'American Morse Equipment', 'key',
 'pocket', 55,
 'Folding portable paddle',
 ARRAY['porta paddle','portapaddle','ame paddle','american morse']);

-- ==================== MICROPHONES ====================

INSERT INTO equipment_catalog (id, name, manufacturer, category, portability, weight_grams, description, aliases) VALUES
('heil-proset-elite', 'Pro Set Elite', 'Heil Sound', 'microphone',
 'base', 400,
 'Professional broadcast-quality headset',
 ARRAY['proset elite','pro set','heil proset']),

('heil-hm12', 'HM-12', 'Heil Sound', 'microphone',
 'base', 280,
 'Desk microphone with HC-6 element',
 ARRAY['hm12','hm 12','heil hm12']),

('heil-traveler', 'Traveler', 'Heil Sound', 'microphone',
 'portable', 100,
 'Lightweight dual-element headset for portable ops',
 ARRAY['heil traveler','heil traveller']);

-- ==================== ACCESSORIES ====================

INSERT INTO equipment_catalog (id, name, manufacturer, category, portability, weight_grams, description, aliases) VALUES
('bioenno-12v-3ah', 'BLF-1203AS', 'Bioenno Power', 'accessory',
 'backpack', 360,
 '12V 3Ah LiFePO4 battery',
 ARRAY['bioenno 3ah','bioenno battery','blf-1203']),

('bioenno-12v-6ah', 'BLF-1206AS', 'Bioenno Power', 'accessory',
 'backpack', 680,
 '12V 6Ah LiFePO4 battery',
 ARRAY['bioenno 6ah','blf-1206']),

('elecraft-kxpd3', 'KXPD3', 'Elecraft', 'accessory',
 'pocket', 70,
 'Precision iambic paddle for KX2/KX3',
 ARRAY['kxpd-3','kxpd 3']),

('sotabeams-mast-10m', 'Tactical 10m Mast', 'SOTAbeams', 'accessory',
 'backpack', 700,
 '10-meter telescoping fiberglass mast',
 ARRAY['sota mast','sotabeams mast','tactical mast']);
