-- Activity program registry
CREATE TABLE programs (
    slug                TEXT PRIMARY KEY,
    name                TEXT NOT NULL,
    short_name          TEXT NOT NULL,
    icon                TEXT NOT NULL,
    icon_url            TEXT,
    website             TEXT,
    server_base_url     TEXT,
    reference_label     TEXT NOT NULL,
    reference_format    TEXT,
    reference_example   TEXT,
    multi_ref_allowed   BOOLEAN NOT NULL DEFAULT false,
    activation_threshold INT,
    supports_rove       BOOLEAN NOT NULL DEFAULT false,
    capabilities        TEXT[] NOT NULL DEFAULT '{}',
    -- ADIF field mapping
    adif_my_sig         TEXT,
    adif_my_sig_info    TEXT,
    adif_sig_field      TEXT,
    adif_sig_info_field TEXT,
    -- Data entry metadata (for dataEntry capability)
    data_entry_label    TEXT,
    data_entry_placeholder TEXT,
    data_entry_format   TEXT,
    -- Metadata
    sort_order          INT NOT NULL DEFAULT 0,
    is_active           BOOLEAN NOT NULL DEFAULT true,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Seed data
INSERT INTO programs (slug, name, short_name, icon, website, reference_label, capabilities, sort_order)
VALUES ('casual', 'Casual', 'Casual', 'radio', NULL, 'Reference', '{}', 0);

INSERT INTO programs (slug, name, short_name, icon, website, reference_label, reference_format, reference_example, multi_ref_allowed, activation_threshold, supports_rove, capabilities, adif_my_sig, adif_my_sig_info, adif_sig_field, adif_sig_info_field, sort_order)
VALUES ('pota', 'Parks on the Air', 'POTA', 'tree', 'https://pota.app', 'Park Reference', '^[A-Z]+-[0-9]{4,5}$', 'K-0001', true, 10, true, '{referenceField,adifUpload,browseSpots,selfSpot,hunter,locationLookup,progressTracking}', 'POTA', 'MY_POTA_REF', 'SIG', 'SIG_INFO', 1);

INSERT INTO programs (slug, name, short_name, icon, website, reference_label, reference_format, reference_example, capabilities, adif_my_sig, adif_my_sig_info, adif_sig_field, adif_sig_info_field, sort_order)
VALUES ('sota', 'Summits on the Air', 'SOTA', 'mountain.2', 'https://www.sota.org.uk', 'Summit Reference', '^[A-Z0-9]+/[A-Z]{2}-[0-9]{3}$', 'W7W/LC-001', '{referenceField,adifUpload}', 'SOTA', 'MY_SOTA_REF', 'SOTA_REF', 'SOTA_REF', 2);

INSERT INTO programs (slug, name, short_name, icon, website, reference_label, reference_format, reference_example, capabilities, adif_my_sig, adif_my_sig_info, adif_sig_field, adif_sig_info_field, sort_order)
VALUES ('wwff', 'World Wide Flora & Fauna', 'WWFF', 'leaf', 'https://wwff.co', 'WWFF Reference', '^[A-Z0-9]+FF-[0-9]{4}$', 'KFF-0001', '{referenceField,adifUpload}', 'WWFF', 'MY_WWFF_REF', 'WWFF_REF', 'WWFF_REF', 3);

INSERT INTO programs (slug, name, short_name, icon, website, reference_label, reference_format, reference_example, capabilities, sort_order)
VALUES ('iota', 'Islands on the Air', 'IOTA', 'water.waves', 'https://www.iota-world.org', 'IOTA Reference', '^[A-Z]{2}-[0-9]{3}$', 'NA-001', '{referenceField}', 4);

INSERT INTO programs (slug, name, short_name, icon, website, reference_label, capabilities, sort_order)
VALUES ('lota', 'Lighthouses on the Air', 'LOTA', 'light.beacon.max', 'https://illw.net', 'Lighthouse Reference', '{referenceField}', 5);

INSERT INTO programs (slug, name, short_name, icon, website, reference_label, reference_format, reference_example, capabilities, data_entry_label, data_entry_placeholder, sort_order)
VALUES ('aoa', 'Agents on Air', 'AoA', 'antenna.radiowaves.left.and.right', NULL, 'Mission Reference', '^M-[a-z0-9]{4}$', 'M-a01f', '{referenceField,hunter,dataEntry,dataVerification}', 'Passkey', 'Enter code from other station', 6);
