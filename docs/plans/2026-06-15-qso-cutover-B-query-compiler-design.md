# QSO Rust-Store Cutover — Sub-project B: `.cwquery` → SQL compiler + ServicePresence mirror — Design

**Date:** 2026-06-15
**Status:** Design — pending user review
**Phase:** 4 (consumer cutover — sub-project B)
**Companion docs:** [cutover design/spec](2026-06-14-qso-rust-store-cutover-design.md) · [Plan A (infrastructure)](2026-06-14-qso-cutover-plan-A-infrastructure.md) · [handoff](2026-06-14-qso-cutover-handoff.md) · [rust-core handoff](2026-06-13-rust-core-handoff.md)

---

## Goal

Serve the **full** Logbook query — every `.cwquery` field and condition the Swift
`QueryCompiler` supports — from the Rust `cw-store` (SQLite), at full behavioral
parity with the existing Swift in-memory compiler. This is the long pole of the QSO
cutover: it unblocks sub-project C (the `LogsListView` refactor), which consumes the
read-source methods B delivers.

**Parity is the acceptance bar.** A Rust path that silently drops a field, condition,
or edge case is a regression. Verification is a shared query corpus run against an
identical fixture on both paths, asserting identical ordered result-id sets.

Success = on a fixture dataset, every query in the corpus returns byte-identical
ordered id lists from Swift and Rust; and on a real device in `shadow` mode, a sweep
over the user's saved queries reports zero true mismatches.

## Why this is smaller than the handoff implied

The handoff listed B as "port the `.cwquery` → Rust/SQLite query compiler," treating
the parser as unbuilt. It is already built: `cw-domain/query/` (committed 2026-06-13)
is a faithful port of `CarrierWaveCore/QueryLanguage/*` — lexer, parser, AST,
analyzer, error, token — pure, no I/O, with its own tests. **The remaining gap is the
AST → SQL emission step plus the data it needs.** Two pieces:

1. **AST → SQL compiler** (new `cw-store/query` module) — lower `QueryExpression` to a
   parameterized `WHERE` clause + params and execute it.
2. **ServicePresence write-path mirror** — the `synced:` / `pending:` query fields
   resolve against the `ServicePresence` relationship. The cw-store **table, struct,
   upsert, filtered fetch, count, FFI surface, and importer seeding for
   ServicePresence already exist** (built during the rust-core migration; the importer
   seeds `service_presence` today). The only gaps are a `delete_service_presence` FFI
   and extending the live save-time **`CwStoreMirror`** — which currently iterates
   `QSO` only — to also capture ServicePresence inserts/updates/deletes. Without the
   live mirror, `synced:`/`pending:` go stale between reseeds, breaking parity.

Per user direction (2026-06-15) these ship as **one combined spec**, the ServicePresence
mirror is solved by **mirroring the entity** (not denormalizing or carving out a
fallback), and the **`LogsListView` UI refactor stays out of scope as sub-project C**.

## Locked decisions

- **Coverage:** full DSL, no SwiftData fallback. Every `QueryField` + `TermCondition`
  the Swift compiler handles compiles to SQL.
- **`synced:` / `pending:`:** the `service_presence` table is already mirrored; compile
  these fields as `EXISTS` subqueries. Close the live-mirror gap so it stays fresh.
- **Structure:** one spec, one plan (internal phasing kept clear).
- **Compiler placement:** in `cw-store` (approach A below). `cw-domain` stays pure.
- **On-device parity:** extend `QSOParityProbe` to sweep the user's real saved queries.
- **Out of scope:** the `LogsListView` refactor (C); entities beyond QSO +
  ServicePresence; cutting SwiftData writes; macOS Sweep.

## Approach (compiler placement) — chosen: A

- **A. Compiler in `cw-store`, AST in → parameterized SQL out (chosen).** `cw-domain`
  stays pure (AST + analyzer untouched). `cw-store` gains a `query` submodule owning the
  `QueryField → column` map and the lowering. FFI takes the raw query **string** and
  does parse → compile → execute entirely in Rust. Schema-coupled SQL lives next to the
  schema it targets; parity tests run against real in-memory SQLite. No new IR.
- **B. `cw-domain` emits a neutral `QueryPlan`; `cw-store` binds it.** Rejected — adds an
  IR to maintain for a second backend that does not exist (YAGNI).
- **C. `cw-domain` emits SQL text directly.** Rejected — couples the pure, no-I/O crate
  to physical column names and SQLite dialect.

## Architecture — what changes where

```
cw-domain/query/        UNCHANGED. Pure lexer→parser→AST + analyzer. Read path parses here.
        │  ParsedQuery
        ▼
cw-store/query/  (NEW)   field→column map; lower(QueryExpression) → (where_sql, params);
        │                EXISTS subqueries for synced/pending; cw_lower UDF for case parity.
        ▼
cw-store                 NEW fetch_qsos_query(parsed, limit, offset) + count_query(parsed);
        │                NEW delete_service_presence(id). (service_presence table + upsert +
        │                filtered fetch + count ALREADY EXIST.)
        ▼
cw-ffi                   NEW fetch_qsos_query(query, limit, offset) → [FfiQso];
        │                NEW qso_count_query(query) → i64; NEW delete_service_presence + notify(.Delete).
        │                (FfiServicePresence upsert/fetch/count ALREADY EXIST.)
        ▼
Swift                    RustQSOReadSource gains page(query:)/count(query:) via the seam;
                         CwStoreMirror + CwStoreMirrorActor extended to ServicePresence saves/deletes;
                         QSOParityProbe gains a saved-query sweep. (Reuses A's flag + serial actor;
                         the importer ALREADY seeds service_presence.)
```

## ServicePresence mirror (faithful to the `@Model`)

**Already built (rust-core migration):** the `service_presence` table + DDL/indexes,
the `ServicePresence` struct, `upsert_service_presence`, `service_presence_count`,
`fetch_service_presence(id)` / `fetch_service_presences(filter)`, the `FfiServicePresence`
FFI surface, and importer seeding (`SwiftDataStoreImporter` projects `ServicePresence`
and the reconcile pass seeds `service_presence`). The schema below documents that mapping.
**B adds only:** a `delete_service_presence(id)` path (cw-store + FFI + `notify(.Delete)`)
and the live save-time mirror (extend `CwStoreMirror`/`CwStoreMirrorActor`).

`ServicePresence` persisted fields (from `Models/ServicePresence.swift`), mirrored 1:1
(this is the existing `service_presence` schema):

| `@Model` property | cw-store column | Notes |
|---|---|---|
| `id: UUID` | `id TEXT PRIMARY KEY` | string form, like QSO |
| `serviceTypeRawValue` (orig. `serviceType`) | `service_type TEXT NOT NULL` | `ServiceType.rawValue` |
| `isPresent: Bool` | `is_present INTEGER NOT NULL DEFAULT 0` | drives `synced:` |
| `needsUpload: Bool` | `needs_upload INTEGER NOT NULL DEFAULT 0` | drives `pending:` |
| `uploadRejected: Bool` | `upload_rejected INTEGER NOT NULL DEFAULT 0` | |
| `rejectedAtBuild: String?` | `rejected_at_build TEXT` | |
| `isSubmitted: Bool` | `is_submitted INTEGER NOT NULL DEFAULT 0` | |
| `lastConfirmedAt: Date?` | `last_confirmed_at INTEGER` | unix seconds |
| `parkReference: String?` | `park_reference TEXT` | |
| `cloudDirtyFlag: Bool` | `dirty INTEGER NOT NULL DEFAULT 1` | matches QSO's `dirty` mapping |
| `qso: QSO?` (relationship) | `qso_id TEXT` + `INDEX(qso_id)` | FK to `qso.id`; the join key |

Every field is mirrored even though only `service_type` / `is_present` / `needs_upload`
/ `qso_id` are needed for queries — fidelity keeps the importer lossless and lets later
slices read presence without a schema change.

**Mirror hook.** `CwStoreMirror` already observes `ModelContext.didSave` with
`object: nil` (all contexts, off-main via the serial `CwStoreMirrorActor`). We extend
its entity filter to also capture `ServicePresence` inserts/updates/deletes, projecting
to an `FfiServicePresence` value and calling upsert / `delete_service_presence(id)`.
Deletes reuse the QSO pattern: capture `PersistentIdentifier → id` in `willSave`,
consume in `didSave`. The background-context regression test from A applies here too.

**Seed on enable.** The reconcile importer seeds `service_presence` in the same
idempotent pass that seeds QSOs, before parity reads begin.

## AST → SQL compiler (`cw-store/query`)

A recursive lowering `QueryExpression → (where_sql: String, params: Vec<Value>)`:

- `.empty` → `1=1`
- `.and([..])` → `(a AND b AND …)`
- `.or([..])` → `(a OR b OR …)`
- `.not(x)` → `NOT (x)`
- `.term(QueryTerm)` → field/condition lowering below

**Field → column map (all 24 `QueryField`s):**

| Field(s) | Lowering |
|---|---|
| `callsign`, `band`, `mode`, `myCallsign` | string match on `callsign`/`band`/`mode`/`my_callsign` |
| `park`,`sota`,`grid`,`state`,`country`,`name`,`qth`,`notes`,`myGrid` | string match on `park`/`sota_ref`/`their_grid`/`state`/`country`/`name`/`qth`/`notes`/`my_grid` |
| `frequency` | numeric match on `freq_khz` |
| `dxcc`, `power` | numeric match on `dxcc`/`power` |
| `date`,`after`,`before` | date match on `qso_date` (see below) |
| `confirmed` | `boolean`→`(qrz_confirmed=1 OR lotw_confirmed=1)`; `service(.lotw)`→`lotw_confirmed=1`; `service(.qrz)`→`qrz_confirmed=1`; other service → `0` |
| `synced` | `EXISTS (SELECT 1 FROM service_presence sp WHERE sp.qso_id=qso.id AND sp.is_present=1 [AND sp.service_type=?])` |
| `pending` | `EXISTS (… AND sp.needs_upload=1 [AND sp.service_type=?])` |
| `source` | `service(x)`→`import_source_raw_value=?` (map ServiceType→ImportSource rawValue); `equals("manual"|"logger")`→`import_source_raw_value='logger'`; else `0` |
| bare term (no field) | OR across `callsign`/`park`/`sota_ref`/`notes` (matches `compileBareSearchTerm`; note: `equals`/`prefix`/`suffix` use callsign/park/sota only, `contains` adds notes) |

**Condition lowering (string fields — exact Swift case semantics):** Swift lowercases
both operands and uses literal substring/prefix/suffix. We register a Rust scalar UDF
`cw_lower(x)` (Unicode-aware, matching `String.lowercased()`) and:

- `equals(v)` → `cw_lower(col) = cw_lower(?)`
- `contains(v)` → `cw_lower(col) LIKE '%'||?||'%' ESCAPE '\'` with `?` = `cw_lower(v)` and
  `%`/`_`/`\` in `v` escaped
- `prefix(v)` → `cw_lower(col) LIKE ?||'%' ESCAPE '\'`
- `suffix(v)` → `cw_lower(col) LIKE '%'||? ESCAPE '\'`
- `range(a,b)` → `cw_lower(col) >= cw_lower(?) AND cw_lower(col) <= cw_lower(?)`
- optional (nullable) columns: a NULL column must yield `false` (matches `?? false`),
  which `LIKE`/`=` against NULL already does.

**Numeric lowering:** `greaterThan`/`lessThan`/`…OrEqual` → `col > ?` etc.;
`numericRange(a,b)` → `col >= ? AND col <= ?`. `dxcc`/`power` are integer columns;
NULL yields false.

**Date lowering:** resolve `DateMatch` to a `(start,end)` unix-second range via
`cw-domain`'s `DateMatch::resolve()` (must match Swift `resolve()` exactly — this is a
parity unit-test target). `dateEquals`/`dateRange` → `qso_date >= ? AND qso_date < ?`;
`dateAfter` → `qso_date >= ?`; `dateBefore` → `qso_date < ?`. **Caveat:** Swift
`resolve()` uses `Calendar.current` (device timezone); the Rust resolver must use the
same timezone the FFI is handed, or relative/`today` dates diverge. Resolve dates in
Swift and pass the timezone offset, OR resolve in Rust with an explicit tz param —
decided in the plan; flagged as a parity risk.

**Base predicate + ordering.** The Logbook list fetch uses `#Predicate { !$0.isHidden }`
and `SortDescriptor(\.timestamp, order: .reverse)` only — empirically **no separate
`isMetadata` filter** (metadata pseudo-mode QSOs are excluded because they carry
`isHidden = true`). The Rust query therefore ANDs `is_hidden = 0` as the baseline and
orders `qso_date DESC`. `qso_count_query` applies the same `WHERE` minus limit/offset.

**Public API:**
```rust
// cw-store
pub fn fetch_qsos_query(&self, query: &ParsedQuery, limit: i64, offset: i64) -> Result<Vec<Qso>>;
pub fn count_query(&self, query: &ParsedQuery) -> Result<i64>;
```
`limit` keeps the `MAX_FETCH_LIMIT` guard. The existing bounded `QsoFilter`/`fetch_qsos`
stays (used by the count path in A); the query variants are additive.

## Read path (Swift seam)

`QSOQueryFilter` in the `QSOReadSource` seam gains the raw query string. `RustQSOReadSource`
passes it to the new FFI; `SwiftDataQSOReadSource` keeps compiling via `QueryCompiler`.
`RoutingQSOReadSource` is unchanged in shape: `off`→SwiftData, `shadow`→SwiftData
authoritative + Rust compared via probe, `on`→Rust. The read-after-write `drain()`
barrier from A applies before Rust reads in `on`.

## Parity testing (the acceptance bar)

**Shared corpus.** One list of query strings covering: each field × each applicable
condition; AND/OR/NOT nesting and grouping; bare terms (equals/contains/prefix/suffix);
`synced:`/`pending:` with and without a service; `confirmed:`/`source:`; wildcards;
case-fold edges (mixed-case + one accented value); empty query; negation-only. The
corpus is the single source of truth, checked into both the Rust and Swift test targets.

**Fixture.** One dataset of QSOs + ServicePresence rows, **kept below the Swift
`searchBatchSize`** (see divergence note) so Swift's batch window never truncates and
the two paths are compared on identical complete inputs.

**Assertion.** For each query: Swift `QueryCompiler` (authoritative) over the in-memory
SwiftData fixture vs. Rust `fetch_qsos_query` over the same fixture loaded into in-memory
SQLite → assert **identical ordered id lists** and identical `count`.

**Rust-side divergence to document (not a regression).** The current Swift search
fetches a bounded batch (`searchBatchSize`, timestamp-desc) and filters it in memory, so
on a large log Swift only matches rows inside that window. The Rust SQL path filters the
**whole** table. For matches beyond the window the Rust result is a *superset* — the
intended improvement, the reason for the cutover. The fixture stays under the window so
unit parity is exact; the on-device probe must **classify "Rust-only id present because
its match lies beyond the Swift batch window" separately from a true field mismatch**, so
the sweep doesn't flag the improvement as an error.

**On-device sweep.** Extend `QSOParityProbe` with a saved-query sweep: for each of the
user's saved `.cwquery` queries, run both paths in `shadow`, compare id sets + count,
and log the first-N divergences (classified per above) to the in-app diagnostics surface.

## Testing summary

- **Rust unit (`cw-store`):** AST→SQL lowering per field/condition; `EXISTS` for
  synced/pending; `cw_lower` UDF + LIKE escaping; date-range lowering; corpus parity vs
  golden id-sets; ServicePresence upsert/delete; importer seed idempotency.
- **Rust unit (`cw-domain`):** `DateMatch::resolve()` matches the Swift fixtures (tz-pinned).
- **Swift unit (in-memory):** mirror captures ServicePresence insert/update/delete →
  matching cw-store rows; `RustQSOReadSource` page/count over the fixture equals
  `QueryCompiler`; corpus parity; metadata/`isHidden` exclusion parity; background-context
  save test (ServicePresence).
- **Device:** `shadow` saved-query sweep → zero true mismatches; flip `on`, Logbook list
  + filtered count served from Rust identically; flip `off` → rollback.

## Risks

- **Timezone-dependent dates** — relative/`today`/`yesterday` resolution must use the
  same tz on both paths (plan decision).
- **Unicode case folding** — `cw_lower` vs Swift `.lowercased()` may differ on exotic
  scripts; corpus characterizes it; amateur-log fields are near-all ASCII.
- **Two `FieldStore` writer handles** (carried from A's watch-list) — mirror + importer
  on one SQLCipher file; consolidate onto `CwStoreProvider.shared` when convenient.
- **Saved-query corpus drift** — new DSL features must be added to the shared corpus or
  parity silently under-tests; call this out in the query module's doc comment.

## Out of scope

`LogsListView` UI refactor (sub-project C); entities beyond QSO + ServicePresence;
stats / map / aggregation reads; cutting SwiftData writes (Rust stays a read mirror);
macOS Sweep.
