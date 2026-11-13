# Contest Definitions

> **Status:** Format spec (v0.3). Engine implementation pending. A visual editor is planned but not yet built.

A declarative JSON format for defining amateur radio contests. The format describes a contest's schedule, exchange, scoring rules, and category structure with enough fidelity to drive a contest logger end-to-end (dupe checking, multiplier accumulation, score calculation, Cabrillo export) without per-contest code.

This document is the canonical reference for the format. Implementations should validate definitions against the rules described here, and authors of contest definitions should treat this document as the source of truth for what fields exist and what they mean.

- **Schema version:** `0.3.0`
- **Schema id:** `https://example.com/contest-definition/v0.3`
- **Examples:** [docs/examples/contests/](../examples/contests/)
- **JSON Schema:** [docs/examples/contests/schema.json](../examples/contests/schema.json)

---

## Goals and non-goals

**Goals**

- Express common HF contests (CWT, SST, MST, NAQP, CQWW, ARRL DX, Sweepstakes, IARU, WPX, etc.) declaratively, with no per-contest code in the scoring engine.
- Be diffable, reviewable, and authorable by hand or with a future visual editor.
- Validate at load time, not at scoring time. A definition that loads cleanly should never produce a runtime scoring error.
- Be portable across consumers (logger apps, contest robots, leaderboard servers).

**Non-goals**

- Owning UI, radio control, or log persistence — those belong to the consumer.
- Modeling every conceivable scoring quirk in the initial release. WAE QTCs, Stew Perry distance scoring, Field Day bonus points, and asymmetric contests like ARRL DX are explicitly deferred to future revisions (see [Future considerations](#future-considerations)).
- Replacing Cabrillo. Cabrillo remains the export format; this spec describes how to *generate* Cabrillo, not how to parse it.

---

## Top-level structure

A contest definition file is a JSON object with these top-level fields:

| Field | Type | Required | Description |
|---|---|---|---|
| `$schema` | string | optional | JSON Schema URL. Should be `https://json-schema.org/draft/2020-12/schema`. |
| `$id` | string | optional | Schema id. For v0.3: `https://example.com/contest-definition/v0.3`. |
| `title` | string | optional | Human-readable file title. |
| `version` | string | required | Format version (semver). Current: `0.3.0`. |
| `contests` | array&lt;Contest&gt; | required | One or more contest definitions. A single file may bundle related contests (e.g. CW + SSB variants). |

A file may declare a single contest or many. The `contests` array is the unit of distribution.

---

## Contest object

```json
{
  "id": "cwops-cwt",
  "name": "CWops Mini-CWT Test",
  "short_name": "CWT",
  "sponsor": { ... },
  "modes": ["CW"],
  "bands": ["160m", "80m", "40m", "20m", "15m", "10m"],
  "data_dependencies": { ... },
  "schedule": { ... },
  "exchange": { ... },
  "dupe_rules": { ... },
  "scoring": { ... },
  "operating_constraints": { ... },
  "cabrillo": { ... },
  "categories": [ ... ],
  "overlay_categories": [ ... ]
}
```

| Field | Type | Required | Description |
|---|---|---|---|
| `id` | string | required | Stable, machine-readable id. Lowercase, kebab-case. Must be unique within a file. |
| `name` | string | required | Full human name. |
| `short_name` | string | optional | Abbreviated name (CWT, SST, CQWW CW). Used in UI chrome and Cabrillo headers. |
| `sponsor` | object | optional | `{ name, url }`. Sponsoring organization. |
| `modes` | array&lt;Mode&gt; | required | Allowed modes. See [Modes](#modes). |
| `bands` | array&lt;Band&gt; | required | Allowed bands. See [Bands](#bands). |
| `data_dependencies` | object | optional | External data files the engine needs. See [Data dependencies](#data-dependencies). |
| `schedule` | object | required | When the contest runs. See [Schedules](#schedules). |
| `exchange` | object | required | Sent and received exchange field definitions. See [Exchange](#exchange). |
| `dupe_rules` | object | required | What constitutes a duplicate QSO. See [Dupe rules](#dupe-rules). |
| `scoring` | object | required | Scoring phases. See [Scoring](#scoring). |
| `operating_constraints` | object | optional | Off-time and band-change rules. See [Operating constraints](#operating-constraints). |
| `cabrillo` | object | optional | Cabrillo export configuration. See [Cabrillo](#cabrillo). |
| `categories` | array&lt;Category&gt; | required | Entry categories. See [Categories](#categories). |
| `overlay_categories` | array&lt;Overlay&gt; | optional | Overlay categories that stack on top of a primary category. |

---

## Modes

A `modes` entry must be one of:

| Value | Meaning |
|---|---|
| `CW` | Morse code |
| `SSB` | Single sideband phone |
| `DIGITAL` | All digital modes (FT8, RTTY, PSK, etc.) |
| `RTTY` | RTTY only (use when distinct from other digital modes) |
| `BOTH` | Mixed CW + SSB (used by some contests as a single category mode) |

A contest may declare multiple modes when it accepts more than one. Mixed-mode contests typically declare `["CW", "SSB"]`.

For scoring purposes, the engine may collapse modes into a `mode_group` (CW, PHONE, DIGITAL). The mapping is built into the engine and is not currently configurable per contest.

---

## Bands

A `bands` entry is a string identifying an amateur band. The recognized values are:

`2200m`, `630m`, `160m`, `80m`, `60m`, `40m`, `30m`, `20m`, `17m`, `15m`, `12m`, `10m`, `6m`, `4m`, `2m`, `1.25m`, `70cm`, `33cm`, `23cm`, `13cm`, `9cm`, `6cm`, `3cm`, `1.25cm`, `6mm`, `4mm`, `2.5mm`, `2mm`, `1mm`.

Most HF contests use the six classic bands: `160m, 80m, 40m, 20m, 15m, 10m`.

---

## Data dependencies

External data files that the engine needs to score a contest. The library declares what it needs; **the consumer is responsible for downloading, caching, and parsing the files** and injecting them into the engine via the appropriate trait. The library never touches the filesystem or network.

```json
"data_dependencies": {
  "country_file": {
    "id": "wl_cty_dat",
    "url": "https://www.country-files.com/contest/",
    "file": "wl_cty.dat",
    "description": "Extended country file with CQ zone macros",
    "update_frequency": "before_each_contest",
    "provides": ["their_country", "their_continent", "their_cq_zone", "their_itu_zone"],
    "options": { "wae_entities": true }
  },
  "prefix_map": {
    "id": "cqwwpre3",
    "url": "https://www.country-files.com/contest/",
    "file": "cqwwpre3.txt",
    "description": "Pre-expanded prefix-to-entity map",
    "provides": ["callsign_to_entity_lookup"]
  }
}
```

The keys in `data_dependencies` are well-known dependency types. Each value is a descriptor object.

### Dependency descriptor fields

| Field | Type | Required | Description |
|---|---|---|---|
| `id` | string | required | Stable id used to key the consumer's cache. |
| `url` | string | optional | Where to fetch. Either a direct file URL or a parent page URL the consumer must scrape. |
| `file` | string | optional | Filename within an archive or page. |
| `description` | string | optional | Free-form description for human readers. |
| `update_frequency` | string | optional | One of `static`, `monthly`, `weekly`, `before_each_contest`. Hint to the cache layer. |
| `provides` | array&lt;string&gt; | optional | Which derived fields this dependency populates (e.g. `their_country`, `their_cq_zone`). The validator uses this to check that conditions referencing those fields have a backing data source. Required for `country_file` and `prefix_map`; optional for `section_list` (which validates exchange field values rather than producing derived fields). |
| `options` | object | optional | Type-specific options (e.g. `wae_entities: true` for the WAE-aware variant of `wl_cty.dat`). |

### Known dependency types

| Type key | Purpose |
|---|---|
| `country_file` | DXCC entity lookup. Resolves callsign → country, continent, CQ zone, ITU zone, lat/lon. |
| `prefix_map` | Pre-expanded prefix-to-entity table. An alternative or supplement to `country_file` that avoids the macro parser. |
| `section_list` | List of valid section/state/province values for a multiplier exchange field. |
| `zone_map` | Standalone zone map (rare; usually folded into `country_file`). |

The full catalog of available country files and their characteristics is documented in [Country file resolution](#country-file-resolution) below.

---

## Schedules

A schedule object describes when the contest runs. The shape depends on the `type`.

### `recurring_weekly`

Weekly mini-contests like CWT, SST, MST.

```json
"schedule": {
  "type": "recurring_weekly",
  "sessions": [
    { "day": "wednesday", "start_utc": "13:00", "duration_minutes": 60 },
    { "day": "wednesday", "start_utc": "19:00", "duration_minutes": 60 },
    { "day": "thursday", "start_utc": "03:00", "duration_minutes": 60 }
  ],
  "session_scoring": "independent"
}
```

| Field | Type | Required | Description |
|---|---|---|---|
| `type` | `"recurring_weekly"` | required | Discriminator. |
| `sessions` | array | required | One entry per weekly session window. |
| `sessions[].day` | string | required | Day of week (lowercase): `monday`, `tuesday`, `wednesday`, `thursday`, `friday`, `saturday`, `sunday`. |
| `sessions[].start_utc` | string | required | Start time in `HH:MM` (24-hour UTC). |
| `sessions[].duration_minutes` | integer | required | Duration in minutes. Must be positive. |
| `session_scoring` | string | required | `independent` (each session is its own contest) or `cumulative` (sessions roll up). |

### `annual`

Major contests like CQWW, ARRL DX, IARU.

```json
"schedule": {
  "type": "annual",
  "rule": "last_full_weekend_november",
  "start_utc": "00:00",
  "start_day": "saturday",
  "duration_hours": 48
}
```

| Field | Type | Required | Description |
|---|---|---|---|
| `type` | `"annual"` | required | Discriminator. |
| `rule` | string | required | Recurrence rule. See below. |
| `start_utc` | string | required | Start time in `HH:MM` UTC. |
| `start_day` | string | required | Day of week the rule resolves to. |
| `duration_hours` | number | required | Total contest duration in hours. |

Recognized `rule` values:

- `last_full_weekend_november`
- `last_full_weekend_october`
- `fourth_weekend_october`
- `fourth_weekend_february`
- `second_full_weekend_september`
- `third_full_weekend_july`
- `first_full_weekend_august`
- `first_full_weekend_december`
- `arrl_dx_first_weekend` (third weekend of February)

Add new rules as needed. The validator should reject unknown rule strings rather than silently accepting them.

### `fixed_dates`

Contests on specific calendar dates (rare; mostly special events).

```json
"schedule": {
  "type": "fixed_dates",
  "occurrences": [
    { "start": "2026-07-01T13:00:00Z", "duration_hours": 168 }
  ]
}
```

---

## Exchange

The exchange object defines what fields the operator sends and receives.

```json
"exchange": {
  "sent": [
    { "name": "rst", "type": "signal_report", "label": "RST", "required": true },
    { "name": "cq_zone", "type": "cq_zone", "label": "CQ Zone", "required": true, "autofill": "station_cq_zone" }
  ],
  "received": [
    { "name": "rst", "type": "signal_report", "label": "RST", "required": true },
    { "name": "cq_zone", "type": "cq_zone", "label": "CQ Zone", "required": true }
  ]
}
```

`sent` and `received` are independent arrays. They are usually mirror images but need not be (some contests send a constant while receiving a varying field).

### Exchange field

| Field | Type | Required | Description |
|---|---|---|---|
| `name` | string | required | Stable id used in scoring conditions as `received.<name>`. snake_case. |
| `type` | string | required | Field type. See below. |
| `label` | string | required | Human label for UI. |
| `required` | boolean | optional | Default `true`. If `false`, the field may be empty. |
| `autofill` | string | optional | Source for auto-population (sent only). E.g. `station_cq_zone`, `station_section`, `station_grid`. |
| `auto_increment` | boolean | optional | Sent serial numbers only. The engine assigns and increments. |
| `list` | string | optional | For `section_list` type: which section list to validate against. |
| `default` | any | optional | Default value if not provided. |
| `pattern` | string | optional | Regex pattern for `text` types. |
| `min` / `max` | number | optional | Range constraints for numeric types. |

### Field types

| Type | Validation | Notes |
|---|---|---|
| `text` | Free text. Optional `pattern` regex. | Names, generic identifiers. |
| `signal_report` | RST format (`599`, `5NN`, `59`). | Almost always autofilled to `599`/`59`. |
| `serial_number` | Positive integer. | Use `auto_increment: true` on the sent side. |
| `cq_zone` | Integer 1–40. | |
| `itu_zone` | Integer 1–90. | |
| `grid_square` | Maidenhead 4 or 6 char. | |
| `state_province` | US state, Canadian province, or Mexican state code. | |
| `arrl_section` | ARRL section code. | Validated against `arrl_sections` list. |
| `section_list` | Membership in a named list (`list` field is required). | E.g. `us_states_ve_provinces_dx`. |
| `power` | One of `HIGH`, `LOW`, `QRP` or numeric watts. | |
| `name` | Free text, typically operator first name. | |
| `age` | Positive integer. | YOTA contests. |
| `class` | Free text class designator. | ARRL Field Day style. |

The validator should reject unknown types.

### Auto-fill sources

When `autofill` is set on a sent field, the value is populated from the operator's `StationConfig` at session start. Recognized sources:

- `station_cq_zone`, `station_itu_zone`
- `station_country`, `station_continent`
- `station_section`, `station_state`, `station_province`
- `station_grid`
- `station_name`
- `station_power`, `station_class`

---

## Dupe rules

```json
"dupe_rules": {
  "scope": "contest",
  "key": ["callsign", "band"],
  "zero_point_qsos_count_for_mults": true
}
```

| Field | Type | Required | Description |
|---|---|---|---|
| `scope` | string | required | `session` (per session window, e.g. CWT) or `contest` (whole contest, e.g. CQWW). |
| `key` | array&lt;string&gt; | required | Composite key components. Common values: `callsign`, `band`, `mode`, `mode_group`. |
| `zero_point_qsos_count_for_mults` | boolean | optional | Default `false`. If `true`, a non-dupe QSO that scores 0 points (typical for same-country contacts in CQWW) still contributes to multiplier sets. |

### Behavior

- Dupes are **flagged**, not rejected. The consumer decides whether to suppress logging.
- Dupes contribute neither QSO points nor multipliers.
- Callsigns are normalized (uppercased, portable suffixes like `/QRP`, `/M`, `/P` stripped) before composing the dupe key. The consumer is responsible for normalization, or the engine should expose a documented normalization helper.

---

## Scoring

The scoring section is an ordered list of named **phases**. Each phase produces a number, and later phases may reference the results of earlier phases. The final phase (typically named `total`) is the contest score.

```json
"scoring": {
  "phases": [
    { "id": "qso_points", "type": "per_qso", "rules": [ ... ] },
    { "id": "mult_countries", "type": "multiplier_count", ... },
    { "id": "mult_zones", "type": "multiplier_count", ... },
    { "id": "total", "type": "aggregate", "operation": { ... } }
  ]
}
```

Phase ordering is significant: an `aggregate` phase may only reference phases that appear **earlier** in the array. This makes the scoring graph a DAG with no need for topological sorting at runtime — the validator simply walks the array and checks every `ref` points backward.

### Phase types

| Type | Output | Description |
|---|---|---|
| `per_qso` | Sum of point values across all QSOs. | Evaluates an ordered rule list per QSO; the first matching rule wins. |
| `multiplier_count` | Count of unique values seen. | Accumulates a set, scoped per band or per contest. |
| `aggregate` | Result of an arithmetic tree. | Combines earlier phase results. |

### `per_qso` phase

```json
{
  "id": "qso_points",
  "type": "per_qso",
  "description": "Ordered rules, first match wins",
  "rules": [
    {
      "description": "Same country: 0 points",
      "conditions": [
        { "field": "their_country", "op": "eq", "ref": "my_country" }
      ],
      "value": 0
    },
    {
      "description": "Same continent, both in NA: 2 points",
      "conditions": [
        { "field": "their_continent", "op": "eq", "ref": "my_continent" },
        { "field": "my_continent", "op": "eq", "value": "NA" }
      ],
      "value": 2
    },
    {
      "description": "Different continent: 3 points (default fallback)",
      "conditions": [],
      "value": 3
    }
  ]
}
```

For each QSO, the engine iterates `rules` in order. For each rule, all conditions are evaluated as a conjunction (AND). The first rule whose conditions all pass wins, and its `value` becomes the QSO's point value.

**Fallback rule:** the last rule in the array should have `conditions: []` (empty list, always matches). The validator should warn if it does not — without a fallback, some QSOs may match no rule and silently score 0.

If a rule's `value` is `0`, the QSO is "zero-point" and contributes no points. It still counts for multipliers if `zero_point_qsos_count_for_mults` is true on the dupe rules and `include_zero_point_qsos` is true on the multiplier phase.

### Conditions

A condition compares a field on the QSO to either a literal or another field.

```json
{ "field": "their_continent", "op": "eq", "ref": "my_continent" }
{ "field": "my_continent", "op": "eq", "value": "NA" }
{ "field": "band", "op": "in", "value": ["20m", "15m", "10m"] }
```

| Field | Type | Description |
|---|---|---|
| `field` | string | The field on the QSO context being read. |
| `op` | string | Comparison operator. |
| `value` | literal or array | A literal value or list to compare against. Mutually exclusive with `ref`. |
| `ref` | string | A reference to another field on the QSO context. Mutually exclusive with `value`. |

### Condition fields

These are the fields available in conditions, derived by the engine from the QSO record + station config + data dependencies:

| Field | Source | Description |
|---|---|---|
| `their_callsign` | QSO | Normalized callsign (uppercase, portable suffixes stripped). |
| `their_country` | country_file | DXCC entity of worked station. |
| `their_continent` | country_file | Continent of worked station. |
| `their_cq_zone` | country_file | CQ zone of worked station. |
| `their_itu_zone` | country_file | ITU zone of worked station. |
| `my_country` | StationConfig | Operator's DXCC entity. |
| `my_continent` | StationConfig | Operator's continent. |
| `my_cq_zone` | StationConfig | Operator's CQ zone. |
| `my_itu_zone` | StationConfig | Operator's ITU zone. |
| `band` | QSO | Band of the QSO. |
| `mode` | QSO | Mode of the QSO. |
| `mode_group` | engine | Collapsed mode group (`CW`, `PHONE`, `DIGITAL`). |
| `received.<name>` | QSO | Any field from the received exchange. E.g. `received.cq_zone`. |
| `distance_km` | engine | Great circle distance between stations. Requires both stations to have grid or lat/lon. |

The validator must reject any condition that references a field not in this vocabulary.

### Condition operators

| Op | Meaning |
|---|---|
| `eq` | Equals (compare to `ref` field or literal `value`). |
| `ne` | Not equals. |
| `in` | Value is in the list provided as `value`. |
| `not_in` | Value is not in the list. |
| `gt` | Greater than (numeric). |
| `gte` | Greater than or equal (numeric). |
| `lt` | Less than (numeric). |
| `lte` | Less than or equal (numeric). |

String comparisons are **case-insensitive**.

### `multiplier_count` phase

```json
{
  "id": "mult_countries",
  "type": "multiplier_count",
  "description": "Unique WAE entities per band",
  "source": "their_country",
  "scope": "per_band",
  "include_zero_point_qsos": true
}
```

| Field | Type | Required | Description |
|---|---|---|---|
| `id` | string | required | Phase id. |
| `type` | `"multiplier_count"` | required | Discriminator. |
| `source` | string | required | The field that produces multiplier values. May be a derived field (`their_country`, `their_callsign`, `their_cq_zone`) or `received.<name>`. |
| `scope` | string | required | `per_band` (separate set per band, count summed) or `per_contest` (single set across all bands). |
| `include_zero_point_qsos` | boolean | optional | Default `false`. If `true`, zero-point QSOs still contribute to the multiplier set. |
| `description` | string | optional | Free-form description. |

The engine maintains the accumulator as a `HashSet<Value>` (per_contest) or `HashMap<Band, HashSet<Value>>` (per_band). The phase's output is the count: `set.len()` for per_contest, or the sum of `set.len()` across all bands for per_band.

### `aggregate` phase

```json
{
  "id": "total",
  "type": "aggregate",
  "operation": {
    "op": "multiply",
    "inputs": [
      { "op": "ref", "phase": "qso_points" },
      {
        "op": "add",
        "inputs": [
          { "op": "ref", "phase": "mult_countries" },
          { "op": "ref", "phase": "mult_zones" }
        ]
      }
    ]
  }
}
```

`operation` is an arithmetic tree. Each node has an `op` and (depending on op) `inputs`, `phase`, or `value`.

### Aggregate operations

| Op | Shape | Meaning |
|---|---|---|
| `ref` | `{ op: "ref", phase: "<id>" }` | Resolves to the result of an earlier phase. For `per_qso` phases, the sum of point values; for `multiplier_count` phases, the count. |
| `add` | `{ op: "add", inputs: [...] }` | Sum of inputs. |
| `multiply` | `{ op: "multiply", inputs: [...] }` | Product of inputs. |
| `max` | `{ op: "max", inputs: [...] }` | Maximum of inputs. |
| `literal` | `{ op: "literal", value: 5 }` | Constant integer. |

All values in the tree are integers. Floating-point operations are not supported in this version. (Distance-based scoring will require introducing `floor`/`ceil`/`divide` ops in a future release.)

---

## Operating constraints

Off-time and band-change rules. Optional but required for any contest with category-dependent operating limits.

```json
"operating_constraints": {
  "off_time": {
    "minimum_off_minutes": 30,
    "maximum_on_hours_by_category": {
      "SOAB": 36,
      "MS": 48
    }
  },
  "band_changes": {
    "applies_to": ["MS"],
    "min_minutes_on_band": 10,
    "max_changes_per_clock_hour": 10
  }
}
```

| Field | Description |
|---|---|
| `off_time.minimum_off_minutes` | A break only counts as an off-time period if it is at least this many minutes long. |
| `off_time.maximum_on_hours_by_category` | Map of category id → max on-air hours. |
| `band_changes.applies_to` | List of category ids the band-change limits apply to. |
| `band_changes.min_minutes_on_band` | After changing bands, the operator must remain on the new band at least this many minutes. |
| `band_changes.max_changes_per_clock_hour` | Maximum band changes within any clock hour. |

The engine should track on-air windows from QSO timestamps and surface violations to the consumer. Whether to block logging or just warn is the consumer's choice.

---

## Cabrillo

```json
"cabrillo": {
  "contest_name": "CQ-WW-CW",
  "version": "3.0"
}
```

| Field | Type | Required | Description |
|---|---|---|---|
| `contest_name` | string | required | Value used in the `CONTEST:` Cabrillo header line. |
| `version` | string | required | Cabrillo version. Currently always `"3.0"`. |
| `qso_format` | object | optional | Override for the QSO line layout. Only needed if the contest uses a non-standard format. |

By default, the engine derives the QSO line layout from the `exchange` definition. The standard layout is:

```
QSO: <freq> <mode> <date> <time> <my_call> <sent_fields...> <their_call> <recv_fields...>
```

For contests with non-standard layouts, `qso_format` may declare an explicit ordered list of tokens. This is reserved for v0.4.

---

## Categories

Entry categories define the divisions a participant can compete in.

```json
"categories": [
  { "id": "SOAB", "label": "Single Op All Band", "power_classes": ["HIGH", "LOW", "QRP"] },
  { "id": "SOSB-20", "label": "Single Op 20m", "band": "20m", "power_classes": ["HIGH", "LOW", "QRP"] },
  { "id": "MS", "label": "Multi-Single" },
  { "id": "M2", "label": "Multi-Two" },
  { "id": "MM", "label": "Multi-Multi" }
]
```

| Field | Type | Required | Description |
|---|---|---|---|
| `id` | string | required | Stable category id. Unique across `categories` and `overlay_categories`. |
| `label` | string | required | Human label. |
| `band` | Band | optional | If set, the category is single-band on this band. |
| `power_classes` | array&lt;string&gt; | optional | Permitted power classes. Common: `HIGH`, `HP`, `LOW`, `LP`, `QRP`. |
| `assisted` | boolean | optional | Default `false`. |
| `op_count` | string | optional | `single`, `multi`, `multi_two`, `multi_multi`. |

### Overlay categories

Overlays stack on top of a primary category. An entrant in `SOAB` may also enter the `CLASSIC` overlay.

```json
"overlay_categories": [
  { "id": "CLASSIC", "label": "Classic Overlay", "max_on_hours": 24 },
  { "id": "ROOKIE", "label": "Rookie Overlay", "max_license_years": 3 },
  { "id": "TB-WIRES", "label": "Tribander/Wires Overlay" }
]
```

| Field | Type | Description |
|---|---|---|
| `id` | string | Stable id. Must not collide with any `categories` id. |
| `label` | string | Human label. |
| `max_on_hours` | integer | Optional cap on on-air hours. |
| `max_license_years` | integer | Optional cap on years since first license (rookie overlays). |

---

## Validation

Definitions are validated in two passes: **structural** (during deserialization) and **semantic** (an explicit `validate()` call after deserialization).

### Structural validation

Enforced by the type system / serde:

- Required fields are present.
- Field types match.
- Enum-like fields use only known values (modes, bands, phase types, ops, etc.).

### Semantic validation

`ContestDefinition::validate()` returns a list of errors and warnings. It does **not** stop on the first error so that authors can fix everything in one pass.

| Rule | Severity | Description |
|---|---|---|
| `phase_dag_ordering` | error | Every `ref` in an aggregate must reference a phase id that appears earlier in the phases array. No forward references, no cycles. |
| `fallback_rule` | warning | The last rule in a `per_qso` phase should have empty `conditions` (a catch-all). Missing fallbacks mean some QSOs may silently score 0. |
| `condition_fields` | error | Every field referenced in a condition must be in the known field vocabulary. |
| `condition_refs` | error | If a condition uses `ref`, the ref must also be in the known vocabulary. If it uses `value`, the literal must be valid for that field type. |
| `multiplier_source` | error | The `source` of a `multiplier_count` phase must be a known derived field or a `received.<name>` field that exists in the exchange definition. |
| `exchange_completeness` | error | Every `received.<name>` referenced in conditions or multiplier sources must correspond to a field in `exchange.received`. |
| `data_dependency_satisfaction` | warning | If conditions reference fields like `their_country` or `their_cq_zone`, the corresponding `data_dependencies` entry must be declared and its `provides` array must include the field. |
| `serial_number_consistency` | error | If an exchange field has type `serial_number` with `auto_increment: true`, it must be on the `sent` side only. |
| `session_schedule` | error | For `recurring_weekly`, each session must have a valid day and a `start_utc` in `HH:MM` format. Duration must be positive. For `annual`, `duration_hours` must be positive. |
| `category_ids_unique` | error | All category ids must be unique within a contest. Overlay category ids must not collide with regular category ids. |
| `aggregate_ops` | error | Every `op` in an aggregate operation must be one of `ref`, `add`, `multiply`, `max`, `literal`. `ref` requires `phase`; `add`/`multiply`/`max` require `inputs`; `literal` requires `value`. |
| `phase_id_unique` | error | All phase ids in `scoring.phases` must be unique. |

**Philosophy:** fail at load time, not at scoring time. A definition that loads cleanly should never produce a runtime scoring error apart from callsign resolution failures (which are handled as `Option<ResolvedStation>`).

---

## Implementation guidance

This section is for people writing the scoring engine that consumes the format. Authors of contest definitions can skip it.

### Core types

| Type | Description |
|---|---|
| `ContestDefinition` | Deserialized from JSON. Immutable after load. Contains all phases, exchange, dupe rules, dependencies. |
| `StationConfig` | Provided by the consumer at session start. Operator callsign, grid, CQ zone, ITU zone, DXCC entity, continent — everything needed to populate `my_*` condition fields. |
| `QsoRecord` | Submitted by the consumer per QSO. Callsign, band, mode, timestamp, received exchange fields. |
| `ScoredQso` | `QsoRecord` enriched with resolved fields, point value, and which multipliers it contributed. |
| `ContestSession` | Mutable state for a contest in progress. Holds the log, multiplier accumulators, dupe index, and current score. The primary handle the consumer interacts with. |
| `ScoreSummary` | Snapshot of current score: total QSO points, each multiplier count (overall and per-band), aggregate score, per-band breakdowns. |

### Lifecycle

**1. Load.** Parse JSON into `ContestDefinition`. Validate phase references, condition fields, ops. Fail loudly on unknowns — don't silently ignore.

**2. Resolve dependencies.** Before a session starts, the consumer provides resolved data for each entry in `data_dependencies` via trait-based dependency injection. Define a `CallsignResolver` trait:

```rust
trait CallsignResolver {
    fn resolve(&self, callsign: &str) -> Option<ResolvedStation>;
}

struct ResolvedStation {
    country: String,        // primary prefix, e.g. "PA"
    continent: String,      // NA, SA, EU, AF, OC, AS, AN
    cq_zone: u8,            // 1-40
    itu_zone: u8,           // 1-90
    latitude: Option<f64>,
    longitude: Option<f64>,
    is_wae_entity: bool,
}
```

The consumer implements this trait using whatever country file parser they have. The library never touches the filesystem or network. Different consumers may cache files differently, use different parsers, or substitute test fixtures.

**3. Start session.** Create a `ContestSession` from a `ContestDefinition` + `StationConfig` + resolved dependencies. Initializes empty dupe index, empty multiplier accumulators, validates that `StationConfig` provides all fields the contest's conditions need.

For recurring contests like CWT with `session_scoring: independent`, each 1-hour window is a separate `ContestSession`. The consumer creates a new session per window.

**4. Log QSO.** The hot path. Consumer submits a `QsoRecord`. Library performs:

1. Callsign resolution via the injected resolver.
2. Dupe check.
3. Per-QSO phase evaluation.
4. Multiplier accumulation.
5. Returns a `ScoredQso` with point value, `is_dupe` flag, `new_mult` flags, and an updated `ScoreSummary`.

**Dupes are flagged, not rejected.** The consumer decides whether to block. Some operators log dupes intentionally. Dupes contribute neither points nor multipliers, except: when `zero_point_qsos_count_for_mults` is true, a 0-point non-dupe QSO can still contribute to multipliers.

**Ordering matters.** QSOs must be processed in chronological order for off-time and band-change tracking to work. The library should assert or warn on out-of-order timestamps.

**5. Rescore.** Full rescore from the raw QSO list. Needed after edits (delete QSO, change exchange). Rebuilds dupe index and multiplier accumulators from scratch. Must produce identical results to incremental scoring of the same QSO sequence.

Performance target: **rescore 10k QSOs in under 100ms.** Per-QSO phase evaluation is simple pattern matching; the expensive part is callsign resolution, which should be cached.

**6. Export.** Generate Cabrillo from the session. The contest definition's `cabrillo` block provides the contest name and version. The QSO line layout is derived from the exchange definition (subject to `qso_format` override in v0.4).

### Scoring engine

**Phase evaluation order.** Phases are evaluated in definition order. An aggregate phase can only reference earlier phases. This is a DAG constraint enforced at load time — no runtime topological sort needed.

**Per-QSO evaluation.** Iterate `rules` in order. For each rule, evaluate all conditions as a conjunction (AND). First rule where all conditions pass wins — its `value` becomes the QSO's point value. If no rule matches, the QSO scores 0 (and validation should have warned at load time).

**Condition evaluation.** Each condition reads a field from the enriched QSO context. `my_*` fields come from `StationConfig`. `their_*` fields come from callsign resolution. `received.*` fields come from the QSO's received exchange. The `op` is applied between the field value and either `ref` (another field) or `value` (a literal). String comparisons are case-insensitive.

**Multiplier accumulation.** Each `multiplier_count` phase maintains a set of seen values, scoped as declared. For `per_band`, it's a `HashMap<Band, HashSet<Value>>`. For `per_contest`, it's a single `HashSet<Value>`. The count is the sum of set sizes (per_band) or the single set size (per_contest).

If `include_zero_point_qsos` is true, a QSO that scored 0 points still contributes to this multiplier's seen set. (This is the CQWW same-country case.)

**Aggregate evaluation.** Walk the operation tree. `ref` nodes resolve to the accumulated result of the named phase — sum of point values for `per_qso`, count for `multiplier_count`. `add` and `multiply` operate on their inputs recursively. `literal` returns a constant. The tree is small (typically 3–5 nodes) so recursion is fine.

All values are integers. No floating point.

### Dupe engine

The dupe index is a `HashSet` of composite keys built from the `dupe_rules.key` array. For CQWW with `key=[callsign, band]`, the composite is `(normalized_callsign, band)`. For Field Day with `key=[callsign, band, mode_group]`, it includes the collapsed mode group.

**Normalization.** Callsigns are uppercased and stripped of `/QRP`, `/M`, `/MM`, `/AM`, `/P` suffixes that don't affect DXCC entity. The library should provide a documented normalization helper so all consumers behave consistently.

**Session scope.** For `scope: session` (CWT), the dupe index is per-`ContestSession`. For `scope: contest` (CQWW), it spans the full contest. The consumer manages session boundaries.

### Serial numbers

Contests with `serial_number` exchange fields require the engine to own an auto-incrementing counter as part of `ContestSession` state. The counter starts at 1 and increments on each logged QSO (not on dupes).

**On QSO deletion + rescore, serial numbers are NOT reassigned.** Gaps are preserved, matching real-world behavior where the sent serial is already over the air. The sent serial is assigned at `log_qso()` time and stored on the `ScoredQso`. The `auto_increment: true` flag on the exchange field signals the engine to populate this field automatically rather than expecting the consumer to provide it.

### Error philosophy

Fail at load time, not at scoring time. Every phase ref, condition field, operator, and data dependency should be validated when the `ContestDefinition` is parsed. If a contest definition is valid, scoring a QSO should be infallible (modulo callsign resolution failures, which return `None`).

### Testing strategy

- **Golden files.** Maintain known-good logs with expected scores for each supported contest. CWT is trivial (count QSOs). CQWW exercises continent logic, zero-point mults, and the aggregate formula.
- **Property tests.** Rescore of any QSO sequence must equal incremental scoring of the same sequence. Removing a QSO and rescoring must never increase the score.
- **Fuzz the conditions.** Generate random `QsoRecord`s with random countries/continents and verify exactly one `per_qso` rule matches every input. The last rule should always be a fallback with empty conditions.

---

## Country file resolution

Most contests need to map a callsign to a DXCC entity, continent, and zone. The library does not do this itself — it expects the consumer to inject a `CallsignResolver`. This section documents how to acquire and process the data files most consumers will use.

### Source

AD1C (Jim Reisert) maintains the canonical country files at <https://www.country-files.com/>. The contest-oriented page is <https://www.country-files.com/contest/>.

### Available files

| File | Description |
|---|---|
| `cty.dat` | Basic DXCC prefix-to-entity. Used by CT, NA, TR, WriteLog, and others. |
| `wl_cty.dat` | Extended version with CQ-zone macros for multi-zone countries (VE, VK, UA, etc.). Used by N1MM+. **Preferred for contests using CQ zones.** |
| `cty_wt.dat` | Win-Test extended with per-prefix CQ/ITU zones for VE, VK, and Russian call areas. |
| `cty_wt_mod.dat` | Win-Test detailed version with coordinates and time offsets for many entity exceptions. |
| `cty_cmw.dat` | Commonwealth countries subset (RSGB Commonwealth contest). |
| `cty_cqm.dat` | R-100 countries (CQ-M contest). |
| `cty_eec.dat` | European Economic Community countries (UBA contest). |
| `arrlpre3.txt` | ARRL-context prefix-to-entity mappings (~26k entries). |
| `cqwwpre3.txt` | CQWW-context prefix-to-entity mappings (~26k entries). Includes WAE entity distinctions. |

### Download strategy

AD1C publishes the files as zip archives. Each release is versioned with a `CTY-nnnn` identifier and a date-stamped version string (e.g. `VER20250905`).

1. Fetch the contest country files page at `https://www.country-files.com/contest/`.
2. Download the latest zip for your target format. The page lists per-software downloads (N1MM, WriteLog, etc.) but the underlying files are the same.
3. The zip contains: `cty.dat`, `wl_cty.dat`, `cty_wt.dat`, `cty_wt_mod.dat`, and the XML export.
4. Additionally download the prefix mapping files: `arrlpre3.txt` and `cqwwpre3.txt`.

The page does not have a stable direct-download URL for the latest release. Options:

- Scrape the page for the latest `CTY-nnnn` link.
- Subscribe to the RSS feed at `https://www.country-files.com/feed/` and extract the download URL from new posts.
- Reuse N1MM's update mechanism, which fetches `wl_cty.dat` from a known URL.

**Cache strategy.** Store the downloaded files keyed by the version string (the `VER` date). Before each contest, check if a newer version exists. Country files update weekly or more frequently before major contests.

### Parsing `cty.dat`

Each entity is a multi-line record. The first line is the entity header; subsequent lines are comma-separated prefix/callsign lists terminated by a semicolon.

Header format:

```
Entity Name:                  CQ_Zone:  ITU_Zone:  Continent:  Latitude:  Longitude:  UTC_Offset:  Primary_Prefix:
```

Example:

```
Netherlands:                  14:  27:  EU:   52.40:    -4.90:    -1.0:  PA:
    PA,PB,PC,PD,PE,PF,PG,PH,PI;
```

Prefix conventions:

- `=` prefix on a callsign means **exact match only** (e.g. `=AD1C` means only `AD1C`, not `AD1C/P`).
- `*` prefix on a primary prefix means **WAE-only entity** (e.g. `*IG9` for African Italy — only counts in CQ-sponsored contests).
- `#` prefix begins a **zone-determination macro** (`wl_cty.dat` only).

### The macro problem

`wl_cty.dat` contains macro blocks (prefixed with `#`) that encode rules like "for China, determine CQ zone from call area digit and first suffix letter." These macros are NOT simple prefix lookups. Implementing a full macro parser is non-trivial.

**Workaround:** Use `cqwwpre3.txt` or `arrlpre3.txt`, which contain pre-expanded prefix-to-entity mappings. These are the result of applying the macros and can be used as a flat lookup table. Macro expansion is deferred to a future release.

### Recommended use

- Use a **prefix file** (`cqwwpre3.txt` or `arrlpre3.txt`) for callsign-to-entity resolution.
- Use **`cty.dat` header records** for entity metadata (continent, lat/lon, timezone).
- This avoids implementing the macro parser entirely for most use cases.

---

## Section lists

Contests like SST, Sweepstakes, and Field Day use section/state/province multipliers. These require a list of valid section abbreviations.

### Known lists

| Name | Contents | Used by |
|---|---|---|
| `us_states_ve_provinces_dx` | 50 US states + DC + Canadian provinces + `DX` catch-all. | SST, many QSO parties. |
| `arrl_sections` | ~83 ARRL/RAC sections. Changes occasionally. | Sweepstakes, Field Day. |
| `us_states` | 50 US states only. | State QSO parties. |
| `ve_provinces` | Canadian provinces and territories. | RAC contests. |

### Distribution

Section lists are typically distributed as `.sec` files with N1MM UDC definitions or documented in contest rules. The library should ship a bundled copy of common section lists and allow the consumer to provide custom ones.

The format is a simple newline-delimited list of valid abbreviations. The consumer provides the resolved list as a `HashSet<String>` to the `ContestSession`.

---

## Worked examples

### CWops Mini-CWT Test (CWT)

A weekly 1-hour CW sprint. Three sessions per week, each scored independently. 1 point per QSO; multiplier is unique callsigns worked across all bands; final score is QSOs × mults.

See [docs/examples/contests/cwt.json](../examples/contests/cwt.json) for the full definition.

Key characteristics:

- `schedule.type = recurring_weekly` with three sessions per week.
- `dupe_rules.scope = session` — dupes reset each session.
- Single per-QSO rule with `value: 1` and no conditions.
- Multiplier `scope: per_contest` (which here means per session).

### K1USN Slow Speed Test (SST)

Same shape as CWT but the multiplier is the received `section` field instead of unique callsigns. Demonstrates the `section_list` exchange field type and the `received.<name>` reference in a multiplier source.

See [docs/examples/contests/sst.json](../examples/contests/sst.json).

### ICWC Medium Speed Test (MST)

Same shape as CWT, plus serial number exchange. Demonstrates `serial_number` with `auto_increment: true` on the sent side.

See [docs/examples/contests/mst.json](../examples/contests/mst.json).

### CQ World Wide DX Contest – CW (CQWW)

The complex case. Demonstrates:

- Multi-rule per-QSO scoring with continent/country conditions.
- Same-country zero-point QSOs that still contribute to multipliers (`include_zero_point_qsos: true` + `zero_point_qsos_count_for_mults: true`).
- Two multiplier phases (countries + zones) summed inside the aggregate.
- Per-band multiplier scope.
- WAE entity handling via the `wl_cty.dat` `options.wae_entities` flag.
- Operating constraints: off-time and band-change limits.
- Multiple categories with single-band variants and overlay categories.

See [docs/examples/contests/cqww-cw.json](../examples/contests/cqww-cw.json).

A combined sample with all four contests in a single file is at [docs/examples/contests/sample-bundle.json](../examples/contests/sample-bundle.json).

---

## Future considerations

These are known gaps in v0.3 that will be addressed in later versions.

| Feature | Notes |
|---|---|
| **Stew Perry distance scoring** | Add a per-QSO rule type `distance_formula` with an aggregate-style operation tree, e.g. `{ op: "floor", input: { op: "divide", inputs: ["distance_km", 500] } }`. Requires introducing `divide`, `floor`, `ceil` ops. |
| **ARRL Field Day** | Needs a `bonus_points` phase type and a `power_multiplier` whole-score phase. |
| **Asymmetric contests (ARRL DX)** | The exchange and scoring differ depending on whether the operator is in W/VE or DX. Probably needs a `perspective` field at contest level that selects between two scoring/exchange variants. |
| **WAE QTCs** | Genuinely unique mechanic. Probably needs a dedicated phase type or a plugin escape hatch. |
| **Section list integration** | `data_dependencies.section_list` should support a known enum of list names with bundled defaults. |
| **Cabrillo `qso_format` overrides** | For contests with non-standard Cabrillo QSO line layouts. |
| **Macro parsing for `wl_cty.dat`** | Currently worked around by using `cqwwpre3.txt`. A native parser would simplify country file handling. |

---

## Versioning

The format follows semver. The current version is **0.3.0**.

- **Major bump:** breaking changes (renamed fields, removed types, restructured objects).
- **Minor bump:** additive changes (new optional fields, new operators, new phase types) that older parsers can ignore.
- **Patch bump:** documentation fixes only.

Definitions should declare the version they target via the top-level `version` field. Loaders should reject definitions whose declared major version is greater than the loader's supported major version.

---

## Relationship to existing challenges

This format is **distinct** from the [challenges](challenges.md) feature. Challenges are long-running progress trackers (DXCC, WAS, POTA milestones) evaluated against a user's QSO log. Contest definitions describe time-bounded competitive events with their own scoring rules and Cabrillo output.

A future integration may use contest definitions to drive challenge creation (e.g. "achieve a CQWW score of 1M points" as a challenge), but the two systems remain logically separate.






