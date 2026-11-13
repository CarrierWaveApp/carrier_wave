# Contest Definitions Index

Self-contained module that loads, validates, and scores amateur radio
contest definitions in the v0.3 JSON format.

See [docs/features/contest-definitions.md](../features/contest-definitions.md)
for the format reference.

## Files

### `src/contest/mod.rs`
Module root with public re-exports and integration tests against the
example JSON files in `docs/examples/contests/`.

**Exports:**
- Re-exports all public items from `types` and `validation`

**Tests:**
- Parses and validates each example file (cwt, sst, mst, cqww-cw, cqwpx-cw,
  cqwpx-ssb, sample-bundle)
- WPX prefix extraction (`wpx_prefix`) and WPX prefix-multiplier scoring
- Round-trip serialize/deserialize
- Negative tests: unknown band, unknown mode, forward phase ref, unknown
  condition field, received-side serial with auto_increment
- Warning test: per_qso phase whose last rule has non-empty conditions

### `src/contest/types.rs`
Serde data types for the format.

**Exports:**
- `struct ContestDefinition` - Top-level file: `version` + `Vec<Contest>`
- `struct Contest` - Single contest definition with all sections
- `struct Sponsor` - `{ name, url }`
- `struct DataDependencies` - Map of well-known dependency keys to `DataDependency`
- `struct DataDependency` - `{ id, url, file, description, update_frequency, provides, options }`
- `enum UpdateFrequency` - static, monthly, weekly, before_each_contest
- `enum Schedule` - Tagged on `type`: RecurringWeekly, Annual, FixedDates
- `struct WeeklySession` - `{ day, start_utc, duration_minutes }`
- `enum SessionScoring` - independent, cumulative
- `struct FixedOccurrence` - `{ start, duration_hours }`
- `struct Exchange` - `{ sent: Vec<ExchangeField>, received: Vec<ExchangeField> }`
- `struct ExchangeField` - Single exchange field with type, label, autofill, etc.
- `struct DupeRules` - `{ scope, key, zero_point_qsos_count_for_mults }`
- `enum DupeScope` - session, contest
- `struct Scoring` - `{ phases: Vec<Phase> }`
- `enum Phase` - Tagged on `type`: PerQso, MultiplierCount, Aggregate
- `impl Phase::id()` - Returns the phase's id regardless of variant
- `enum MultiplierScope` - per_band, per_contest
- `struct Rule` - `{ description, conditions, value }` for per_qso rules
- `struct Condition` - `{ field, op, value, ref }` (value/ref mutually exclusive at validation time)
- `enum ConditionOp` - eq, ne, in, not_in, gt, gte, lt, lte
- `enum AggregateOp` - Tagged on `op`: Ref, Literal, Add, Multiply, Max
- `struct OperatingConstraints` - `{ off_time, band_changes }`
- `struct OffTimeRules` - `{ minimum_off_minutes, maximum_on_hours_by_category }`
- `struct BandChangeRules` - `{ applies_to, min_minutes_on_band, max_changes_per_clock_hour }`
- `struct Cabrillo` - `{ contest_name, version, qso_format }`
- `struct Category` - Entry category with id, label, band, power_classes, op_count
- `enum OpCount` - single, multi, multi_two, multi_multi
- `struct OverlayCategory` - Stacking overlay category with optional max_on_hours / max_license_years

### `src/contest/engine.rs`
Scoring engine: state, dupe checking, multiplier accumulation, per-QSO
rule evaluation, aggregate computation.

**Exports:**
- `trait CallsignResolver` - Consumer-supplied callsign-to-DXCC lookup. Single method `resolve(callsign) -> Option<ResolvedStation>`.
- `struct ResolvedStation` - DXCC info: country, continent, cq_zone, itu_zone, lat/lon, is_wae_entity
- `struct StationConfig` - Operator station: callsign, country, continent, zones, grid, state/province, section, name, power, class
- `struct QsoRecord` - Submitted QSO: callsign, band, mode, timestamp_ms, frequency_khz, received exchange map, optional pre-assigned sent_serial
- `struct ScoredQso` - Enriched QSO: normalized_callsign, resolved, points, matched_rule_index, is_dupe, new_multipliers, sent_serial
- `struct ScoreSummary` - Snapshot: qso_count, dupe_count, per-phase results, total
- `struct PhaseResult` - `{ id, kind, value, per_band }`
- `enum PhaseKind` - PerQso, MultiplierCount, Aggregate
- `struct ContestSession<R: CallsignResolver>` - Mutable scoring state
- `impl ContestSession::new()` - Build a session from a Contest + StationConfig + resolver
- `impl ContestSession::log_qso()` - Hot path: dupe check, callsign resolve, per-QSO scoring, multiplier accumulation, sent serial assignment
- `impl ContestSession::rescore()` - Full rebuild from a Vec<QsoRecord>
- `impl ContestSession::summary()` - Snapshot the current ScoreSummary
- `impl ContestSession::qsos()` / `contest()` / `station()` - Accessors
- `fn normalize_callsign()` - Strip portable suffixes (/QRP, /M, /P, etc.) and uppercase

### `src/contest/cabrillo.rs`
Cabrillo 3.0 export from a scored session.

**Exports:**
- `fn export(&ContestSession) -> String` - Generate a Cabrillo log with START-OF-LOG, CONTEST, CALLSIGN, LOCATION, GRID-LOCATOR headers and one QSO line per non-dupe scored QSO. Field layout derived from the contest's exchange definition.

### `src/contest/validation.rs`
Semantic validation pass that runs after structural deserialization.

**Exports:**
- `struct ValidationError` - `{ severity, contest_id, path, message }` with `Display`
- `enum Severity` - Error, Warning
- `impl ContestDefinition::validate()` - Returns `Vec<ValidationError>`
- `impl ContestDefinition::is_valid()` - True iff there are no Error-severity entries

**Validation rules:**
- Mode and band vocabulary
- Schedule sanity (HH:MM, lowercase day names, positive durations)
- Exchange field types, duplicate names, serial_number / auto_increment consistency
- Dupe rules: at least one key component, allowed key components only
- Phase id uniqueness, per_qso fallback rule warning
- Condition field vocabulary (derived fields + received.* fields from exchange)
- Condition value/ref mutual exclusion, in/not_in requires array literal
- Continent literal warning for `their_continent` / `my_continent` equality
- Multiplier source must be derived field or defined received.* field
- Aggregate phase forward-ref check (phase DAG ordering)
- Aggregate add/multiply/max requires non-empty inputs
- Data dependency satisfaction warning (their_country etc. used but no provider declared)
- Category id uniqueness across regular and overlay categories
- Single-band category band must be a known band
