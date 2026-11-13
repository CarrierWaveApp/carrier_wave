# QSO Rust-Store Cutover — Sub-project B Handoff (→ C)

**Date:** 2026-06-16
**Branch:** `main`
**Companion docs:** [cutover design/spec](2026-06-14-qso-rust-store-cutover-design.md) · [B design](2026-06-15-qso-cutover-B-query-compiler-design.md) · [B plan](2026-06-15-qso-cutover-B-query-compiler-plan.md) · [A handoff](2026-06-14-qso-cutover-handoff.md) · [rust-core handoff](2026-06-13-rust-core-handoff.md)

The "pick it up from here" doc for sub-project C (refactor `LogsListView` to render
from Rust snapshots). B explains *what the query path now does*; this explains
*what shipped, what's next, and what to watch*.

---

## TL;DR

**Sub-project B is DONE and fully verified (Rust + Swift suites green).** The full
`.cwquery` query now compiles to SQL in `cw-store/query` at **behavioral parity** with
the Swift `QueryCompiler`, proven by a **68-query Swift↔Rust corpus acceptance test**
(`QueryParityTests`). `service_presence` is now **live-mirrored** so `synced:`/`pending:`
stay fresh. The Rust read seam `RustQSOReadSource.page(query:)`/`count(query:)` returns
`QSORowSnapshot` — that seam is what C consumes. SwiftData remains the system of record;
the Rust store is still a read mirror only, gated behind the same hidden, off-by-default
`cwStoreQSOMode` experiment from A.

The cutover's three sub-projects: **A** ✅ (infra + count), **B** ✅ (this handoff —
query compiler + ServicePresence mirror), **C** ✅ DONE 2026-06-16 (commit `3b8d2fa0`;
the Logbook list now renders from snapshots — see
[C handoff](2026-06-16-qso-cutover-C-handoff.md)).

## What shipped in B (commits on `main`)

| Commit | What |
|---|---|
| `3e977f4b` | B design doc |
| `846ce16d` | B implementation plan + design correction |
| `e65fc2d8` | `cw-store` `delete_service_presence(id)` (idempotent) |
| `3f928d40` | `cw-ffi` `delete_service_presence` fires `notify(.Delete)` |
| `1eefa377` | regenerate `CwFfi.xcframework` + bindings (delete_service_presence) |
| `18ce952b` | `CwStoreMirrorActor` — ServicePresence upsert/delete apply |
| `ff35a95f` | `CwStoreMirror` — dual-write ServicePresence saves (live sync/pending) |
| `342b85f7` | `cw-store/query` scaffold — `cw_lower` UDF + `LIKE` escaping |
| `fc5bb637` | `cw-store/query` — AST→WHERE lowering (all fields/conditions, EXISTS) |
| `1aeb7f72` | `lower_presence` made a pure formatter |
| `004b49dc` | **fix query lexer infinite-loop on unrecognized chars (cw-domain + CarrierWaveCore)** |
| `64110712` | `cw-store` `fetch_qsos_query` + `count_query` (full-DSL, `is_hidden` base) |
| `f195f57e` | shared query corpus + fixture + Rust golden |
| `d9278e18` | `cw-ffi` `fetch_qsos_query` + `qso_count_query`; regenerate bindings |
| `401c2bb5` | `RustQSOReadSource.page(query:)`/`count(query:)` + snapshot type |
| `2a6bd049` | **Swift↔Rust parity test (acceptance gate)** + the frequency-units fix |
| `053ca59c` | rename `CarrierWaveData.QSOSnapshot` → `QSORowSnapshot` (avoid collision) |
| `99cb502a` | `QSOParityProbe` saved-query sweep + batch-window classification |
| `e611e4c6` | Data Migration — saved-query parity sweep action |
| `47213da9` | mark B done in the A handoff |

**Files of note:**
- `rust/cw-core/cw-store/src/query/` — `mod.rs`, `sql.rs` (`SqlValue`, `cw_lower` UDF, `escape_like`), `compiler.rs` (`compile_where`: the AST→SQL lowering).
- `rust/cw-core/cw-store/src/qso.rs` — `fetch_qsos_query` / `count_query`.
- `rust/cw-core/cw-store/src/service_presence.rs` — `delete_service_presence`.
- `rust/cw-core/cw-ffi/src/lib.rs` + `entities/service_presence.rs` — FFI query fns + SP delete.
- `rust/cw-core/cw-domain/src/query/lexer.rs` + `swift/packages/CarrierWaveCore/.../QueryLexer.swift` — the lockstep lexer fix.
- `rust/cw-core/cw-store/tests/query_corpus.rs` + `tests/fixtures/{query_corpus.json,query_fixture.json,query_corpus_expected.json}` — the shared corpus.
- `swift/packages/CarrierWaveData/Sources/CarrierWaveData/RustStore/` — `QSORowSnapshot`, `QSOReadSource` (`QSOQueryReadSource` protocol + `RustQSOReadSource`), `QSOParityProbe` (sweep).
- `swift/ios/CarrierWave/Services/RustStore/` — `CwStoreMirror`, `CwStoreMirrorActor`, `SavedQueryParitySweepAction`.
- `swift/ios/CarrierWaveTests/RustStore/QueryParityTests.swift` — **the acceptance gate (68 queries).**

## How to exercise it

Enable the hidden **"QSO Rust Store"** experiment (Settings → Experiments). In Data
Migration, set the mode and use the two actions:
- **Run QSO Parity Check** (from A) — raw count parity.
- **Run Saved-Query Parity Sweep** (new) — runs each saved `.cwquery` through both paths,
  classifying each as `match` / `rustSupersetLikelyBatchWindow` / `mismatch`.

`shadow` dual-writes + compares; `on` serves the Rust query path; `off` is instant
rollback. The authoritative parity proof is the `QueryParityTests` unit test (runs on the
simulator — it reads the shared fixtures from `rust/cw-core/...` via `#filePath`).

## Bugs caught (don't reintroduce)

1. **Frequency units.** Swift compares `QSO.frequency` in **MHz**; the cw-store column
   `freq_khz` is **kHz** (`freq_khz = frequency * 1000` in the importer). The compiler now
   compares `(freq_khz / 1000.0)`. The acceptance gate caught this — keep `freq:` in MHz.
2. **Lexer infinite-loop (pre-existing P1).** Any char that starts no token (`%`,`@`,`#`,…)
   made the word scanner spin forever, hanging the app on Logbook search input. Fixed
   **identically in both** `cw-domain` and `CarrierWaveCore`: skip the char. Keep the two
   lexers in lockstep.
3. **NULL/negation parity.** Swift optionals are `?? false`, so `-park:foo` on a NULL park
   row is *included* (`!false`). Naive SQL `NOT(... = ...)` over NULL *excludes* it. Every
   nullable-column leaf predicate is wrapped in `COALESCE(..., 0)` so negation matches Swift.
   Don't strip the COALESCE.
4. **`QSOSnapshot` name collision.** `CarrierWaveCore.QSOSnapshot` already existed; the new
   Rust-read snapshot is `QSORowSnapshot`. Don't reintroduce a second `QSOSnapshot`.

## Watch list / known seams (resolve as C grows)

- **`CwFfi.xcframework` is gitignored.** The new FFI (`fetch_qsos_query`, `qso_count_query`,
  `delete_service_presence`) + the freq fix only reach Swift after
  `rust/cw-core/scripts/build-xcframework.sh` runs. Xcode Cloud / other machines must rebuild it.
- **Batch-window semantic difference (important for C).** Today's Swift Logbook search
  fetches a bounded batch (`searchBatchSize`) then filters in memory, so on a large log it
  returns *fewer* rows than the true match set. The Rust path filters the **whole** table.
  This is the intended improvement, but it IS a visible behavior change — the probe
  classifies it as `rustSupersetLikelyBatchWindow`, not a mismatch. C must decide how the
  list paginates against the Rust path and validate via the probe on a real large log.
- **ServicePresence soft-delete invariant.** Swift `synced:`/`pending:` read the live
  `servicePresence` relationship; cw-store physically deletes presence rows via the mirror.
  Parity depends on the mirror keeping cw-store SP rows in lockstep with SwiftData. The
  count/sweep probes are the guardrail.
- **Two `FieldStore` writer handles** (carried from A): `CwStoreProvider.shared` (mirror +
  reads) and the importer both open `cw-store.db`. Works today; consolidate when convenient.
- **Logbook base predicate is `is_hidden = 0` only** — no separate `isMetadata` filter
  (metadata pseudo-mode QSOs are excluded because they carry `isHidden = true`). The Rust
  path replicates exactly `WHERE is_hidden = 0` + `ORDER BY qso_date DESC`. Keep them aligned.
- **`%` in LIKE values** only reaches `escape_like` via *quoted* `contains/prefix/suffix`
  (`escape_like` is unit-tested directly); corpus coverage of a literal `%` inside a LIKE is thin.

## Next steps, in order (sub-project C)

1. **Brainstorm C** — the `LogsListView` refactor. Key decisions: (a) widen `QSORowSnapshot`
   to every field the row cell / grouping / edit needs (it's minimal today); (b) **id-bridge**
   delete / multi-select / group from `persistentModelID` to the `QSORowSnapshot.id` string;
   (c) how an edit/delete round-trips to SwiftData (still system of record) then refreshes the
   snapshot list; (d) how the list source routes by `cwStoreQSOMode` (off→SwiftData,
   shadow→SwiftData + probe, on→`RustQSOReadSource.page(query:)`), including pagination against
   the Rust path and the read-after-write `mirror.drain()` barrier in `on`.
2. **Plan + build C** from that brainstorm (its own spec → plan → implementation, like B).
3. **Then** (still out of scope): the write-cutover (retire SwiftData as system of record),
   non-QSO/ServicePresence entities, stats/map/aggregation reads, deleting SwiftData, macOS Sweep.

## Out of scope (unchanged this slice)

Cutting SwiftData writes; entities beyond QSO + ServicePresence; stats/map/aggregation
reads; deleting SwiftData; macOS Sweep wiring.
