# Contest engine → Rust port (2026-07-04)

Port the entire Swift contest engine to `cw-domain::contest`, move the definitions
pipeline (fetch + cache) to Rust, expose via `cw-ffi::ContestApi`, swap both apps
onto thin facades, delete the Swift logic, and unify contest QSO persistence onto
the Rust `SessionApi` path.

Decisions (user-approved 2026-07-04):
- **Facade swap** — keep the `CarrierWaveData` public API (`ContestEngine`,
  `ContestExchangeParser`, `CabrilloExportService`, …) as thin FFI delegates;
  iOS + Sweep swap together; existing 8 Swift tests pass unchanged as parity gate.
- **Definitions move fully to Rust** — `cw-net::contests` client (ETag) +
  `contest_definition` cw-store cache table replace `ContestDefinitionsStore` /
  `ActivitiesClient+ContestDefinitions` / `Models/Contest*.swift`. UI consumes an
  FFI display DTO (summary projection — the recursive scoring tree never crosses FFI).
- **Engine constructed by definition ID** (`uniffi::Object`), loads parsed
  definition from the cache internally. Time injectable (fixes `rate()`'s `Date()`).
- **Persistence unification** — `SessionApi.log_qso` gains the 5 contest QSO
  fields; remove the `!session.isContest` guard in
  `LoggingSessionManager+RustDelegation`. Flip verification device-gated.

## Phases

1. **cw-domain core** — `contest/` module: serde models (v0.3 wire-compat incl.
   `.unknown` fallbacks + recursive aggregate ops), engine (dupes/serials/
   multipliers/score/rescore/rate), condition evaluator, exchange parser,
   WPX/normalize, Cabrillo 3.0, schedule + annual resolver, off-time,
   band-change, enrichment prefill (membership passed as values). Rust tests
   ported from `ContestDefinitionTests.swift` + expanded. **Cabrillo golden
   fixtures captured from Swift BEFORE deletion.** Live server definitions
   committed as serde round-trip fixtures.
2. **Net + store + FFI** — `cw-net::contests`, `contest_definition` table
   (schema bump), `ContestApi` (refresh/summaries/definition) + `ContestEngine`
   object + stateless fns; `SessionApi` contest fields; xcframework + Kotlin regen.
3. **Swift package facade swap** — gut `Services/Contest/*` internals to FFI
   delegates, delete `Models/Contest*.swift` + `ContestDefinitionsStore`,
   re-point `ContestDefinitionsRefresher`; iOS consumer views onto FFI DTO;
   iOS build green + package tests green.
4. **Sweep re-point** — same swap for `swift/macos/CWSweep`; Sweep build green.
5. **Persistence unification** — SessionApi delegation for contest sessions;
   two-device / on-device verification gate before any authority flip.

Gates every phase: `cargo test --workspace` + clippy `-D warnings` (no cargo fmt
— cw-core is hand-formatted), package `swift test`, iOS compile-check
(`generic/platform=iOS`), Sweep build, swiftformat + swiftlint on touched Swift.

Status: **Phase 1 DONE** — `cw-domain/src/contest/` (model/engine/condition/
exchange_parser/callsign/cabrillo/schedule/off_time/band_change/enrichment),
51 Rust tests incl. the 8 mirrored Swift tests; all 12 live production
definitions captured as fixtures (`cw-domain/tests/fixtures/contests/`) with
parse + key-coverage + round-trip tests; cross-language Cabrillo golden
(`CabrilloGoldenTests.swift` ↔ `cabrillo.rs::generates_full_log` assert the
identical byte string). Workspace tests + clippy green.

**Phase 2 DONE** — `cw-net::contests` (`ContestsClient`, public endpoints, raw
v0.3 body kept opaque); `contest_definition` cache table (schema **v9**,
upsert/fetch/retain); `cw-ffi::contest_api` (`ContestApi` refresh+offline
reads, `ContestEngineApi` scorer by id or raw JSON, stateless `contest_*`
helpers incl. Cabrillo/schedule/off-time/band-change/prefill);
`FfiSessionLogInput` gained the 5 contest QSO fields (default `None`) and
`build_session_qso` stamps them (guard removal is Phase 5). xcframework +
`CwFfi+Generated.swift` regenerated (additive); CarrierWaveData builds.
Kotlin bindings are gitignored build output (regen on next Android build).

**Phase 3 DONE (package + iOS)** — Swift contest logic deleted, facades over
FFI: `Models/Contest*.swift` (6 files) + `ContestDefinitionsStore` +
`ContestEngine+Phases`/`ContestConditionContext`/`ContestAnnualResolver` +
`ActivitiesClient+ContestDefinitions` removed. `ContestDefinition` is now a
typealias of `FfiContestDefinition` with extensions restoring the property
surface (`.exchange`, `.scoring` incl. the full recursive tree via new FFI
scoring-phase DTOs, `.dupeRules`, `.operatingConstraints`, opaque
`.schedule`); engine/parser/Cabrillo/schedule/off-time/band-change/callsign/
enrichment facades delegate to `contest_*` FFI. iOS gets `ContestDefinitions`
(shared `ContestApi` over `CwStoreProvider`) + rewritten refresher.
Gates: 18 contest package tests green (incl. cross-language Cabrillo golden
through the facade), iOS `generic/platform=iOS` build green. Two pre-existing
package-test failures (WhatsNew version expectation, audio-converter signal
11) reproduce on clean HEAD — unrelated.

**Phase 4 DONE** — Sweep's `ContestClient` deleted, refresher rewritten over
the shared `ContestApi`; all Sweep contest views/manager ride the package
facades unchanged. Sweep build green.

**Phase 5 DONE (code)** — `!session.isContest` guard removed from
`LoggingSessionManager+RustDelegation`; contest exchange/serial params flow
through `logQSOViaRustIfEnabled` into `SessionApi.log_qso` (contestName from
`session.contestId`, fields nil for non-contest). `FfiReflector` +
`QSOFields↔FfiQso` already map the 5 contest columns (verified). iOS build
green. **Remaining gate (device):** log a contest QSO on `theseus` under
`.on` and confirm the reflected QSO carries contest fields + uploads route;
per-entity authority flips stay device-gated as before.
