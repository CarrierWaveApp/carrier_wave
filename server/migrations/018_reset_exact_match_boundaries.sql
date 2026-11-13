-- Force re-fetch of all US park boundaries that were matched by name.
-- The old name-matching query used LIKE '%normalized_name%' which could
-- merge unrelated parcels (e.g. "Huron" matching golf courses and metroparks).
-- Setting fetched_at to epoch causes the stale-boundary refresh to re-fetch them
-- with the new exact-match-first query logic.
UPDATE park_boundaries
SET fetched_at = '1970-01-01T00:00:00Z'
WHERE match_quality = 'exact'
  AND source = 'pad_us_4';
