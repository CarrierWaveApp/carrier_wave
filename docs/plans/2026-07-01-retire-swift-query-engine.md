# Retire the Swift query engine — one implementation across iOS + macOS + web

Date: 2026-07-01
Status: In progress

## Why

The `.cwquery` language had **four** implementations: the Swift parser+analyzer
(`CarrierWaveCore/QueryLanguage`), the iOS `QueryCompiler` (AST→predicate/closure),
the macOS Sweep `QSOTableRowMatcher` (in-memory), and the Rust `cw-domain::query`
(parser) + `cw-store` SQL compiler. The Rust engine is already the **runtime
default** on iOS (`rustStoreQSO` default-on, `CwStoreQSOMode.on`) and the web
viewer uses it via WASM. This retires the Swift engine so there is exactly one of
each surface.

## End state (one of each)

- **Parser:** `cw-domain::query` — used by iOS (FFI), macOS (FFI), web (WASM).
- **In-memory evaluator:** `cw-domain::query::eval` — used by macOS Sweep (FFI)
  and web (WASM). Parity-tested vs the SQL compiler.
- **Store evaluator:** `cw-store` SQL (`fetch_qsos_query`) — used by the iOS
  logbook (FFI).

## Phases

### 1. FFI: in-memory filter export (`cw-ffi`)
- `FfiQueryQso` record (all `QueryRow` fields, optionals) + `impl QueryRow`.
- `query_filter(query, qsos) -> Vec<u32>` (parse once, `matches` each; matching
  indices). `analyze_query`/`validate_query` already exist; `isImplicitCallsignSearch`
  is a pure text heuristic (needs nothing).
- Build cw-ffi + clippy + a unit test.

### 2. Regenerate bindings
- `build-xcframework.sh` → `CwFfi.xcframework`; regenerate Kotlin bindings.

### 3. iOS reroute + delete fallback
- `LogsListDataLoading`: parse/analyze via `analyzeViaRust`/`validateViaRust`
  (drop `QueryParser.parse` + `QueryAnalyzer.analyze`). Keep the result DTOs.
- `currentSource()`: always `RustLogbookSource` (require the cw-store; drop the
  `SwiftDataLogbookSource` fallback). Remove now-dead `parsedQuery` state.
- Delete `SwiftDataLogbookSource`, iOS `QueryCompiler*.swift`.

### 4. macOS Sweep reroute
- `QSOLogTableView`: parse+filter via `query_filter` FFI over the in-memory rows
  (map `QSOTableRow` → `FfiQueryQso`). Delete `QSOTableRowMatcher`.
- NOTE: Sweep's bare-term semantics change to the canonical set
  (callsign/park/sota/notes) — an intentional consistency fix.

### 5. Delete the shared Swift engine + parity tooling
- Delete `CarrierWaveCore/QueryLanguage/{QueryParser,QueryLexer,QueryAST,
  QueryToken,QueryParser+*}.swift`. Keep the small result DTOs
  (`QueryAnalysis`/`QueryWarning`/`Severity`/`QueryError`) the views consume, now
  sourced only from the Rust bridge (`QueryAnalyzer+Rust.swift`).
- Rework `CarrierWaveData/RustStore/QSOReadSource.swift` (drop Swift-query use).
- Delete `SavedQueryParitySweepAction`; drop/rewrite the Swift-parser unit tests
  and `QueryParityTests`/`QSOTableRowMatcher` tests.

### 6. Build both apps
- iOS app build (device scheme) + macOS Sweep build. Fix compile errors. Hand
  off on-device (iOS) + on-desktop (macOS) runtime verification to the user.

## Risk

- Two shipping apps' core logbook screens. Rust is already the iOS default, so the
  iOS runtime change is small; macOS Sweep genuinely swaps its filter engine.
- Removing the iOS SwiftData fallback means the cw-store must open — already true
  for the rest of the app in `.on` mode.
- Verification is device/desktop-gated (user's step); I verify compilation.
</content>
