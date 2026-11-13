-- Reset park boundary cache to refetch all boundaries with multi-parcel merge.
-- Parks like US-0189 (Don Edwards SF Bay NWR) had incomplete polygons because
-- only one parcel was stored instead of merging all PAD-US features.
TRUNCATE TABLE park_boundaries;
