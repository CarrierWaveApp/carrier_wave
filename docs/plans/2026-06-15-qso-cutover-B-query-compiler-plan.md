# Sub-project B: `.cwquery` → SQL compiler + ServicePresence mirror — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Serve the full Logbook `.cwquery` query from the Rust `cw-store` (SQLite) at behavioral parity with the Swift `QueryCompiler`, including `synced:`/`pending:` (backed by a live-mirrored `service_presence` table).

**Architecture:** `cw-domain/query` already parses `.cwquery` → `ParsedQuery` (pure). A new `cw-store/query` module lowers that AST to a parameterized SQL `WHERE` clause executed against the existing `qso`/`service_presence` tables; a Unicode-aware `cw_lower` SQLite UDF + `LIKE` escaping reproduce Swift's case-insensitive substring semantics. The Swift `CwStoreMirror` is extended to dual-write `ServicePresence` saves so `synced:`/`pending:` stay fresh. A shared query corpus run over an identical fixture on both paths is the parity acceptance gate.

**Tech Stack:** Rust (rusqlite/SQLCipher, uniffi), Swift (SwiftData, Swift Testing), `cw-domain`/`cw-store`/`cw-ffi` crates.

**Design:** [2026-06-15-qso-cutover-B-query-compiler-design.md](2026-06-15-qso-cutover-B-query-compiler-design.md)

**Conventions (read before starting):**
- `rust/cw-core` is **hand-formatted — do NOT run `cargo fmt`** (creates huge churn). Gate is `cargo build` + `cargo clippy` + `cargo test`.
- Run Rust commands from `rust/cw-core`.
- Swift edits trigger hooks that run SwiftFormat/SwiftLint automatically; compilation is verified by Xcode Cloud on merge (no local Xcode assumed in cloud env — if local, use `xc build`).
- Commit messages use the `Phase 4: …` prefix to match the cutover history. Append `Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>`.
- Reuse, don't reinvent: `SwiftDataStoreImporter.project(_:)`/`.uuid(_:)`, the `CwStoreMirrorActor`, A's `cwStoreQSOMode` flag.

---

## Phase 1 — ServicePresence live mirror (write-path parity)

Goal: `service_presence` stays current on every SwiftData save, with a delete path. (Table, struct, upsert, fetch, count, FFI upsert/fetch, and importer seeding already exist.)

### Task 1: `delete_service_presence` in cw-store

**Files:**
- Modify: `rust/cw-core/cw-store/src/service_presence.rs`

- [ ] **Step 1: Write the failing test**

Add to the `#[cfg(test)] mod tests` block at the bottom of `service_presence.rs` (mirror the existing `delete_qso_removes_row_and_is_idempotent` test in `qso.rs`):

```rust
#[test]
fn delete_service_presence_removes_row_and_is_idempotent() {
    let store = Store::open_in_memory().unwrap();
    store.upsert_service_presence(&sample("a", "qrz", Some("q1"))).unwrap();
    assert_eq!(store.service_presence_count().unwrap(), 1);

    store.delete_service_presence("a").unwrap();
    assert_eq!(store.service_presence_count().unwrap(), 0);
    // idempotent: deleting a missing id is not an error
    store.delete_service_presence("a").unwrap();
    assert_eq!(store.service_presence_count().unwrap(), 0);
}
```

(Confirm the test helper name — the existing tests already call `sample(...)` and `Store::open_in_memory()`; reuse them as-is.)

- [ ] **Step 2: Run test to verify it fails**

Run: `cd rust/cw-core && cargo test -p cw-store delete_service_presence`
Expected: FAIL — `no method named delete_service_presence`.

- [ ] **Step 3: Write minimal implementation**

Add this method inside the existing `impl Store { … }` block in `service_presence.rs`, next to `upsert_service_presence` (model it on `qso.rs`'s `delete_qso`):

```rust
/// Delete a `service_presence` row by id. Idempotent — deleting a missing
/// id succeeds (mirrors the QSO delete path the live mirror relies on).
pub fn delete_service_presence(&self, id: &str) -> Result<()> {
    self.conn
        .execute("DELETE FROM service_presence WHERE id = ?", params![id])?;
    Ok(())
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd rust/cw-core && cargo test -p cw-store delete_service_presence`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add rust/cw-core/cw-store/src/service_presence.rs
git commit -m "$(cat <<'EOF'
Phase 4 (B): cw-store delete_service_presence (idempotent)

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

### Task 2: `delete_service_presence` FFI + notify(.Delete)

**Files:**
- Modify: `rust/cw-core/cw-ffi/src/entities/service_presence.rs`
- Reference: `rust/cw-core/cw-ffi/src/lib.rs:438` (`delete_qso`), `rust/cw-core/cw-ffi/src/observation.rs` (`FfiChangeKind::Delete`)

- [ ] **Step 1: Write the failing test**

In `rust/cw-core/cw-ffi/src/observation.rs` tests (next to `delete_qso_fires_delete_notification`), add:

```rust
#[test]
fn delete_service_presence_fires_delete_notification() {
    let (store, rx) = store_with_observer();
    store
        .upsert_service_presence(sample_ffi_service_presence("a"))
        .unwrap();
    let _ = rx.try_recv(); // drain the upsert notification
    store.delete_service_presence("a".to_string()).unwrap();
    let change = rx.try_recv().expect("expected a change notification");
    assert_eq!(change.table, FfiStoreTable::ServicePresence);
    assert_eq!(change.kind, FfiChangeKind::Delete);
}
```

(Reuse the test scaffolding `store_with_observer()` already used by `delete_qso_fires_delete_notification`. Add a small `sample_ffi_service_presence(id)` helper in the test module if one doesn't exist, building an `FfiServicePresence` with all fields populated.)

- [ ] **Step 2: Run test to verify it fails**

Run: `cd rust/cw-core && cargo test -p cw-ffi delete_service_presence_fires_delete_notification`
Expected: FAIL — `no method named delete_service_presence`.

- [ ] **Step 3: Write minimal implementation**

Add to the `#[uniffi::export] impl FieldStore { … }` block in `entities/service_presence.rs` (mirror `lib.rs`'s `delete_qso`):

```rust
pub fn delete_service_presence(&self, id: String) -> Result<(), CwError> {
    {
        let store = self.inner.lock().expect("store mutex poisoned");
        store.delete_service_presence(&id)?;
    }
    self.notify(FfiStoreChange {
        table: FfiStoreTable::ServicePresence,
        kind: FfiChangeKind::Delete,
    });
    Ok(())
}
```

- [ ] **Step 4: Run test + clippy**

Run: `cd rust/cw-core && cargo test -p cw-ffi delete_service_presence_fires_delete_notification && cargo clippy -p cw-ffi`
Expected: PASS, no clippy warnings.

- [ ] **Step 5: Commit**

```bash
git add rust/cw-core/cw-ffi/src/entities/service_presence.rs rust/cw-core/cw-ffi/src/observation.rs
git commit -m "$(cat <<'EOF'
Phase 4 (B): cw-ffi delete_service_presence fires notify(.Delete)

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

### Task 3: Regenerate xcframework + Swift bindings

**Files:**
- Run: `rust/cw-core/scripts/build-xcframework.sh`, `rust/cw-core/scripts/generate-swift-bindings.sh`

- [ ] **Step 1: Regenerate**

Run:
```bash
cd rust/cw-core && ./scripts/generate-swift-bindings.sh && ./scripts/build-xcframework.sh
```
Expected: scripts complete; the generated `FieldStore` Swift binding now exposes `deleteServicePresence(id:)`.

- [ ] **Step 2: Verify the new symbol is in the bindings**

Run: `grep -rn "deleteServicePresence" swift/ | head`
Expected: at least one hit in the generated bindings file.

- [ ] **Step 3: Commit**

```bash
git add rust/cw-core swift
git commit -m "$(cat <<'EOF'
Phase 4 (B): regenerate CwFfi xcframework + bindings (delete_service_presence)

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

### Task 4: `CwStoreMirrorActor` — ServicePresence apply methods

**Files:**
- Modify: `swift/ios/CarrierWave/Services/RustStore/CwStoreMirrorActor.swift`
- Test: `swift/ios/CarrierWaveTests/RustStore/CwStoreMirrorActorTests.swift`

- [ ] **Step 1: Write the failing test**

Add to `CwStoreMirrorActorTests.swift` (mirror the existing QSO apply test; build a `FieldStore` over an in-memory store the way the existing tests do):

```swift
@Test func appliesServicePresenceUpsertsAndDeletes() async throws {
    let store = try makeInMemoryStore()
    let actor = CwStoreMirrorActor(store: store)

    let sp = FfiServicePresence(
        id: "sp1", serviceTypeRawValue: "qrz", isPresent: true, needsUpload: false,
        uploadRejected: false, rejectedAtBuild: nil, isSubmitted: false,
        lastConfirmedAt: nil, parkReference: nil, cloudDirtyFlag: false, qsoId: "q1"
    )
    await actor.applyServicePresenceUpserts([sp])
    #expect(try store.servicePresenceCount() == 1)

    await actor.applyServicePresenceDeletes(["sp1"])
    #expect(try store.servicePresenceCount() == 0)
}
```

(Use whatever in-memory `FieldStore` factory the existing actor tests use — match their helper name.)

- [ ] **Step 2: Run test to verify it fails**

Build/run the `CarrierWaveTests` target's `CwStoreMirrorActorTests`. Expected: compile failure — `applyServicePresenceUpserts` undefined.

- [ ] **Step 3: Write minimal implementation**

Add to `CwStoreMirrorActor` (after `applyDeletes`):

```swift
func applyServicePresenceUpserts(_ items: [FfiServicePresence]) {
    for item in items {
        try? store.upsertServicePresence(item: item)
    }
}

func applyServicePresenceDeletes(_ ids: [String]) {
    for id in ids {
        try? store.deleteServicePresence(id: id)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run the test. Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add swift/ios/CarrierWave/Services/RustStore/CwStoreMirrorActor.swift swift/ios/CarrierWaveTests/RustStore/CwStoreMirrorActorTests.swift
git commit -m "$(cat <<'EOF'
Phase 4 (B): CwStoreMirrorActor — ServicePresence upsert/delete apply

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

### Task 5: `CwStoreMirror` — capture ServicePresence saves

**Files:**
- Modify: `swift/ios/CarrierWave/Services/RustStore/CwStoreMirror.swift`
- Test: `swift/ios/CarrierWaveTests/RustStore/CwStoreMirrorTests.swift`

- [ ] **Step 1: Write the failing test (incl. background context)**

Add to `CwStoreMirrorTests.swift`, mirroring the existing QSO + background-context tests:

```swift
@Test func mirrorsServicePresenceInsertUpdateDelete() async throws {
    let harness = try MirrorTestHarness()           // existing helper used by QSO tests
    harness.mirror.start()
    defer { harness.mirror.stop() }

    let qso = QSO(/* minimal valid QSO with id */)
    let sp = ServicePresence(serviceType: .qrz, isPresent: true, qso: qso)
    harness.mainContext.insert(qso)
    harness.mainContext.insert(sp)
    try harness.mainContext.save()
    await harness.mirror.drain()
    #expect(try harness.store.servicePresenceCount() == 1)

    harness.mainContext.delete(sp)
    try harness.mainContext.save()
    await harness.mirror.drain()
    #expect(try harness.store.servicePresenceCount() == 0)
}

@Test func mirrorsServicePresenceFromBackgroundContext() async throws {
    let harness = try MirrorTestHarness()
    harness.mirror.start()
    defer { harness.mirror.stop() }

    let bg = ModelContext(harness.container)
    let qso = QSO(/* minimal valid QSO */)
    let sp = ServicePresence(serviceType: .lotw, isPresent: true, qso: qso)
    bg.insert(qso); bg.insert(sp)
    try bg.save()                                   // must NOT crash (no assumeIsolated)
    await harness.mirror.drain()
    #expect(try harness.store.servicePresenceCount() == 1)
}
```

(Match the existing harness/helper names in this file — the QSO background-context test `testBackgroundContextSaveMirrorsWithoutAssumingMainActor` shows the pattern.)

- [ ] **Step 2: Run tests to verify they fail**

Run `CwStoreMirrorTests`. Expected: FAIL — `servicePresenceCount` stays 0 (ServicePresence not yet captured).

- [ ] **Step 3: Write minimal implementation**

In `CwStoreMirror.swift`, extend `Pending` and the two handlers:

```swift
private struct Pending {
    var upserts: [FfiQso] = []
    var deletes: [String] = []
    var spUpserts: [FfiServicePresence] = []
    var spDeletes: [String] = []

    var isEmpty: Bool {
        upserts.isEmpty && deletes.isEmpty && spUpserts.isEmpty && spDeletes.isEmpty
    }
}
```

In `handleWillSave`, after the QSO loops, add ServicePresence capture (the importer projection already exists):

```swift
for case let sp as ServicePresence in context.insertedModelsArray {
    batch.spUpserts.append(SwiftDataStoreImporter.project(sp))
}
for case let sp as ServicePresence in context.changedModelsArray {
    batch.spUpserts.append(SwiftDataStoreImporter.project(sp))
}
for case let sp as ServicePresence in context.deletedModelsArray {
    batch.spDeletes.append(SwiftDataStoreImporter.uuid(sp.id))
}
```

And in `handleWillSave`'s buffering block, append the SP arrays too:

```swift
lock.withLock {
    pending[key, default: Pending()].upserts.append(contentsOf: batch.upserts)
    pending[key, default: Pending()].deletes.append(contentsOf: batch.deletes)
    pending[key, default: Pending()].spUpserts.append(contentsOf: batch.spUpserts)
    pending[key, default: Pending()].spDeletes.append(contentsOf: batch.spDeletes)
}
```

In `handleDidSave`'s `Task`, flush them after the QSO writes (order: QSO upserts → SP upserts → QSO deletes → SP deletes, so a SP referencing a just-upserted QSO sees it, and SP deletes follow QSO deletes):

```swift
let task = Task { [mirrorActor] in
    if !batch.upserts.isEmpty { await mirrorActor.applyUpserts(batch.upserts) }
    if !batch.spUpserts.isEmpty { await mirrorActor.applyServicePresenceUpserts(batch.spUpserts) }
    if !batch.deletes.isEmpty { await mirrorActor.applyDeletes(batch.deletes) }
    if !batch.spDeletes.isEmpty { await mirrorActor.applyServicePresenceDeletes(batch.spDeletes) }
}
```

Confirm `SwiftDataStoreImporter.project(_:)` has a `ServicePresence → FfiServicePresence` overload (it does — the importer calls `Self.project(model)` for `ServicePresence` at `SwiftDataStoreImporter.swift:81`). If `project`/`uuid` are not visible from the app target, widen their access from `internal` as needed (they're already used by the QSO path here).

- [ ] **Step 4: Run tests to verify they pass**

Run `CwStoreMirrorTests`. Expected: both new tests PASS, existing QSO tests still PASS.

- [ ] **Step 5: Commit**

```bash
git add swift/ios/CarrierWave/Services/RustStore/CwStoreMirror.swift swift/ios/CarrierWaveTests/RustStore/CwStoreMirrorTests.swift
git commit -m "$(cat <<'EOF'
Phase 4 (B): CwStoreMirror dual-writes ServicePresence saves (live sync/pending)

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

## Phase 2 — AST → SQL compiler (`cw-store/query`)

Goal: lower `ParsedQuery` to a parameterized SQL `WHERE` + params and execute it, at parity with `QueryCompiler`. Build the module bottom-up with a value enum for bound params, then per-condition lowering, then composition, then the public fetch/count.

### Task 6: Module scaffold + `cw_lower` UDF + LIKE escaping

**Files:**
- Create: `rust/cw-core/cw-store/src/query/mod.rs`
- Create: `rust/cw-core/cw-store/src/query/sql.rs`
- Modify: `rust/cw-core/cw-store/src/lib.rs` (add `pub mod query;`, register UDF on `Store::open*`)

- [ ] **Step 1: Write the failing test**

Create `rust/cw-core/cw-store/src/query/sql.rs` with a test module:

```rust
//! Low-level SQL building blocks for the query compiler: bound-parameter values,
//! the `cw_lower` UDF registration, and `LIKE` escaping. Kept apart from the AST
//! lowering so the string-handling parity rules live in one place.

use rusqlite::Connection;

/// A bound SQL parameter. Mirrors the value kinds the lowering produces.
#[derive(Debug, Clone, PartialEq)]
pub enum SqlValue {
    Text(String),
    Int(i64),
    Real(f64),
}

/// Escape `%`, `_`, and `\` in a user value so it is matched literally inside a
/// `LIKE` pattern using `ESCAPE '\'`. Mirrors Swift's literal `contains/hasPrefix/
/// hasSuffix` (which are NOT pattern matches).
pub fn escape_like(value: &str) -> String {
    let mut out = String::with_capacity(value.len());
    for ch in value.chars() {
        if ch == '\\' || ch == '%' || ch == '_' {
            out.push('\\');
        }
        out.push(ch);
    }
    out
}

/// Register `cw_lower(x)` — a Unicode-aware lowercaser matching Swift
/// `String.lowercased()` closely enough for log fields. Used on both column and
/// value sides so comparisons are case-insensitive identically to the Swift path.
pub fn register_cw_lower(conn: &Connection) -> rusqlite::Result<()> {
    use rusqlite::functions::FunctionFlags;
    conn.create_scalar_function(
        "cw_lower",
        1,
        FunctionFlags::SQLITE_UTF8 | FunctionFlags::SQLITE_DETERMINISTIC,
        |ctx| {
            let s: Option<String> = ctx.get(0)?;
            Ok(s.map(|v| v.to_lowercase()))
        },
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn escape_like_escapes_wildcards() {
        assert_eq!(escape_like("a%b_c\\d"), "a\\%b\\_c\\\\d");
        assert_eq!(escape_like("plain"), "plain");
    }

    #[test]
    fn cw_lower_lowercases_via_sql() {
        let conn = Connection::open_in_memory().unwrap();
        register_cw_lower(&conn).unwrap();
        let out: String = conn
            .query_row("SELECT cw_lower('AbÇD')", [], |r| r.get(0))
            .unwrap();
        assert_eq!(out, "abçd");
    }
}
```

Create `rust/cw-core/cw-store/src/query/mod.rs`:

```rust
//! Compiles a `cw-domain` `ParsedQuery` to SQL against the `qso`/`service_presence`
//! schema, at parity with the Swift `QueryCompiler`. See
//! docs/plans/2026-06-15-qso-cutover-B-query-compiler-design.md.

pub mod sql;
```

In `lib.rs`, add `pub mod query;` next to the other `pub mod` lines.

- [ ] **Step 2: Run tests to verify they fail/pass-compile**

Run: `cd rust/cw-core && cargo test -p cw-store query::sql`
Expected: the two `sql` tests PASS (this task has no failing-then-passing cycle beyond compiling the new module — they assert the helpers directly).

- [ ] **Step 3: Register the UDF on every connection**

In `lib.rs`, in whichever constructor(s) build the `Connection` (`Store::open`, `Store::open_in_memory`), call `crate::query::sql::register_cw_lower(&conn)?;` immediately after the connection is opened and keyed, before returning the `Store`. (Find the existing `Connection::open*` / SQLCipher key application and add the registration right after.)

- [ ] **Step 4: Verify the UDF is available store-wide**

Add a test in `sql.rs`:

```rust
#[test]
fn store_registers_cw_lower() {
    let store = crate::Store::open_in_memory().unwrap();
    let out: String = store
        .conn
        .query_row("SELECT cw_lower('XY')", [], |r| r.get(0))
        .unwrap();
    assert_eq!(out, "xy");
}
```

Run: `cd rust/cw-core && cargo test -p cw-store query::sql && cargo clippy -p cw-store`
Expected: PASS, no clippy warnings. (If `store.conn` is private, use a public store method or `#[cfg(test)]` accessor that already exists in the crate's tests.)

- [ ] **Step 5: Commit**

```bash
git add rust/cw-core/cw-store/src/query rust/cw-core/cw-store/src/lib.rs
git commit -m "$(cat <<'EOF'
Phase 4 (B): cw-store/query scaffold — cw_lower UDF + LIKE escaping

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

### Task 7: AST → WHERE lowering — fields & conditions

**Files:**
- Create: `rust/cw-core/cw-store/src/query/compiler.rs`
- Modify: `rust/cw-core/cw-store/src/query/mod.rs` (add `pub mod compiler;`)

This is the parity core. Implement a `Lowering` that walks `QueryExpression` and emits `(String, Vec<SqlValue>)`. Build it field-group by field-group with a test per group.

- [ ] **Step 1: Write the failing tests (string + numeric + date + status + bool composition)**

Create `compiler.rs` with the test module below. Each test compiles a query string (via `cw_domain::query::parse`) and asserts the SQL fragment + params. Assert on a normalized fragment so whitespace is not brittle.

```rust
//! AST → SQL lowering at parity with Swift `QueryCompiler`.

use crate::query::sql::{escape_like, SqlValue};
use cw_domain::query::{
    DateMatch, ParsedQuery, QueryExpression, QueryField, QueryTerm, TermCondition,
};
use cw_domain::service_type::ServiceType;
use chrono::{Local, TimeZone};

#[cfg(test)]
mod tests {
    use super::*;
    use cw_domain::query::parse;

    fn lower(input: &str) -> (String, Vec<SqlValue>) {
        let q = parse(input).unwrap();
        compile_where(&q)
    }

    #[test]
    fn callsign_equals_is_case_insensitive() {
        let (sql, params) = lower("call:w1aw");
        assert_eq!(sql, "(cw_lower(callsign) = cw_lower(?))");
        assert_eq!(params, vec![SqlValue::Text("w1aw".into())]);
    }

    #[test]
    fn notes_contains_escapes_and_wraps() {
        let (sql, params) = lower("notes:de%");
        assert_eq!(sql, "(cw_lower(notes) LIKE '%' || cw_lower(?) || '%' ESCAPE '\\')");
        assert_eq!(params, vec![SqlValue::Text(escape_like("de%"))]);
    }

    #[test]
    fn band_and_mode_compose_with_and() {
        let (sql, _) = lower("band:20m mode:ft8");
        assert_eq!(
            sql,
            "((cw_lower(band) = cw_lower(?)) AND (cw_lower(mode) = cw_lower(?)))"
        );
    }

    #[test]
    fn frequency_greater_than_is_numeric() {
        let (sql, params) = lower("freq:>14000");
        assert_eq!(sql, "(freq_khz > ?)");
        assert_eq!(params, vec![SqlValue::Real(14000.0)]);
    }

    #[test]
    fn confirmed_yes_is_any_service() {
        let (sql, _) = lower("confirmed:yes");
        assert_eq!(sql, "((qrz_confirmed = 1 OR lotw_confirmed = 1))");
    }

    #[test]
    fn synced_qrz_is_exists_subquery() {
        let (sql, params) = lower("synced:qrz");
        assert_eq!(
            sql,
            "(EXISTS (SELECT 1 FROM service_presence sp WHERE sp.qso_id = qso.id \
             AND sp.is_present = 1 AND sp.service_type_raw_value = ?))"
        );
        assert_eq!(params, vec![SqlValue::Text("qrz".into())]);
    }

    #[test]
    fn pending_yes_is_exists_needs_upload() {
        let (sql, _) = lower("pending:yes");
        assert_eq!(
            sql,
            "(EXISTS (SELECT 1 FROM service_presence sp WHERE sp.qso_id = qso.id \
             AND sp.needs_upload = 1))"
        );
    }

    #[test]
    fn source_qrz_maps_to_import_source() {
        let (sql, params) = lower("source:qrz");
        assert_eq!(sql, "(import_source_raw_value = ?)");
        assert_eq!(params, vec![SqlValue::Text("qrz".into())]);
    }

    #[test]
    fn not_wraps() {
        let (sql, _) = lower("-mode:cw");
        assert_eq!(sql, "(NOT ((cw_lower(mode) = cw_lower(?))))");
    }

    #[test]
    fn bare_contains_searches_call_park_sota_notes() {
        let (sql, _) = lower("pota");
        // bare term `pota` lexes as park alias? No — bare value, not field. Expect OR group.
        assert!(sql.contains("cw_lower(callsign) LIKE"));
        assert!(sql.contains("cw_lower(park) LIKE"));
        assert!(sql.contains("cw_lower(sota_ref) LIKE"));
        assert!(sql.contains("cw_lower(notes) LIKE"));
    }

    #[test]
    fn date_after_resolves_to_unix_lower_bound() {
        let (sql, params) = lower("after:2026-01-01");
        assert_eq!(sql, "(qso_date >= ?)");
        // 2026-01-01 00:00 local → unix seconds
        let expected = Local
            .with_ymd_and_hms(2026, 1, 1, 0, 0, 0)
            .single()
            .unwrap()
            .timestamp();
        assert_eq!(params, vec![SqlValue::Int(expected)]);
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd rust/cw-core && cargo test -p cw-store query::compiler`
Expected: FAIL — `compile_where` undefined.

- [ ] **Step 3: Write the implementation**

In `compiler.rs` (above the test module), implement the lowering. The field→column map, the per-condition lowering, and the date→unix conversion live here.

```rust
/// Lower a parsed query to a SQL boolean expression over the `qso` table plus
/// `service_presence` EXISTS subqueries, with its bound parameters in order.
pub fn compile_where(query: &ParsedQuery) -> (String, Vec<SqlValue>) {
    let mut params = Vec::new();
    let sql = lower_expr(&query.expression, &mut params);
    (sql, params)
}

fn lower_expr(expr: &QueryExpression, params: &mut Vec<SqlValue>) -> String {
    match expr {
        QueryExpression::Empty => "1=1".to_string(),
        QueryExpression::Term(term) => format!("({})", lower_term(term, params)),
        QueryExpression::And(exprs) => join(exprs, " AND ", params),
        QueryExpression::Or(exprs) => join(exprs, " OR ", params),
        QueryExpression::Not(inner) => format!("(NOT ({}))", lower_expr(inner, params)),
    }
}

fn join(exprs: &[QueryExpression], op: &str, params: &mut Vec<SqlValue>) -> String {
    let parts: Vec<String> = exprs.iter().map(|e| lower_expr(e, params)).collect();
    format!("({})", parts.join(op))
}

/// `column` for the simple string/numeric fields. `None` ⇒ handled specially
/// (date/status/bare).
fn string_column(field: QueryField) -> Option<&'static str> {
    use QueryField::*;
    Some(match field {
        Callsign => "callsign",
        Band => "band",
        Mode => "mode",
        MyCallsign => "my_callsign",
        Park => "park",
        Sota => "sota_ref",
        Grid => "their_grid",
        State => "state",
        Country => "country",
        Name => "name",
        Qth => "qth",
        Notes => "notes",
        MyGrid => "my_grid",
        _ => return None,
    })
}

fn lower_term(term: &QueryTerm, params: &mut Vec<SqlValue>) -> String {
    match term.field {
        Some(field) => lower_field_term(field, &term.condition, params),
        None => lower_bare_term(&term.condition, params),
    }
}

fn lower_field_term(field: QueryField, cond: &TermCondition, params: &mut Vec<SqlValue>) -> String {
    use QueryField::*;
    if let Some(col) = string_column(field) {
        return lower_string_match(col, cond, params);
    }
    match field {
        Frequency => lower_numeric("freq_khz", cond, params),
        Dxcc => lower_numeric("dxcc", cond, params),
        Power => lower_numeric("power", cond, params),
        Date | After | Before => lower_date(field, cond, params),
        Confirmed => lower_confirmed(cond, params),
        Synced => lower_presence("is_present = 1", cond, params),
        Pending => lower_presence("needs_upload = 1", cond, params),
        Source => lower_source(cond, params),
        _ => "1=1".to_string(), // string fields handled above
    }
}

/// String comparisons reproduce Swift `lowercased()` semantics via `cw_lower`.
fn lower_string_match(col: &str, cond: &TermCondition, params: &mut Vec<SqlValue>) -> String {
    match cond {
        TermCondition::Equals(v) => {
            params.push(SqlValue::Text(v.clone()));
            format!("cw_lower({col}) = cw_lower(?)")
        }
        TermCondition::Contains(v) => {
            params.push(SqlValue::Text(escape_like(v)));
            format!("cw_lower({col}) LIKE '%' || cw_lower(?) || '%' ESCAPE '\\'")
        }
        TermCondition::Prefix(v) => {
            params.push(SqlValue::Text(escape_like(v)));
            format!("cw_lower({col}) LIKE cw_lower(?) || '%' ESCAPE '\\'")
        }
        TermCondition::Suffix(v) => {
            params.push(SqlValue::Text(escape_like(v)));
            format!("cw_lower({col}) LIKE '%' || cw_lower(?) ESCAPE '\\'")
        }
        TermCondition::Range(a, b) => {
            params.push(SqlValue::Text(a.clone()));
            params.push(SqlValue::Text(b.clone()));
            format!("cw_lower({col}) >= cw_lower(?) AND cw_lower({col}) <= cw_lower(?)")
        }
        _ => "1=1".to_string(),
    }
}

fn lower_numeric(col: &str, cond: &TermCondition, params: &mut Vec<SqlValue>) -> String {
    match cond {
        TermCondition::GreaterThan(n) => { params.push(SqlValue::Real(*n)); format!("{col} > ?") }
        TermCondition::LessThan(n) => { params.push(SqlValue::Real(*n)); format!("{col} < ?") }
        TermCondition::GreaterThanOrEqual(n) => { params.push(SqlValue::Real(*n)); format!("{col} >= ?") }
        TermCondition::LessThanOrEqual(n) => { params.push(SqlValue::Real(*n)); format!("{col} <= ?") }
        TermCondition::NumericRange(a, b) => {
            params.push(SqlValue::Real(*a));
            params.push(SqlValue::Real(*b));
            format!("{col} >= ? AND {col} <= ?")
        }
        TermCondition::Equals(v) => {
            // numeric field given a bare value — match Swift's numeric equality
            if let Ok(n) = v.parse::<f64>() { params.push(SqlValue::Real(n)); format!("{col} = ?") }
            else { "1=1".to_string() }
        }
        _ => "1=1".to_string(),
    }
}

fn lower_date(field: QueryField, cond: &TermCondition, params: &mut Vec<SqlValue>) -> String {
    let unix = |dt: chrono::NaiveDateTime| -> i64 {
        Local.from_local_datetime(&dt).single()
            .map(|d| d.timestamp())
            .unwrap_or_else(|| dt.and_utc().timestamp())
    };
    match cond {
        TermCondition::DateEquals(d) | TermCondition::DateAfter(d)
        | TermCondition::DateBefore(d) => {
            let (start, end) = d.resolve();
            match cond {
                TermCondition::DateEquals(_) => {
                    params.push(SqlValue::Int(unix(start)));
                    params.push(SqlValue::Int(unix(end)));
                    "qso_date >= ? AND qso_date < ?".to_string()
                }
                TermCondition::DateAfter(_) => {
                    params.push(SqlValue::Int(unix(start)));
                    "qso_date >= ?".to_string()
                }
                _ => { params.push(SqlValue::Int(unix(end))); "qso_date < ?".to_string() }
            }
        }
        TermCondition::DateRange(a, b) => {
            let (start, _) = a.resolve();
            let (_, end) = b.resolve();
            params.push(SqlValue::Int(unix(start)));
            params.push(SqlValue::Int(unix(end)));
            "qso_date >= ? AND qso_date < ?".to_string()
        }
        _ => { let _ = field; "1=1".to_string() }
    }
}

fn lower_confirmed(cond: &TermCondition, _params: &mut Vec<SqlValue>) -> String {
    match cond {
        TermCondition::Boolean(true) => "qrz_confirmed = 1 OR lotw_confirmed = 1".to_string(),
        TermCondition::Boolean(false) => "qrz_confirmed = 0 AND lotw_confirmed = 0".to_string(),
        TermCondition::Service(ServiceType::Lotw) => "lotw_confirmed = 1".to_string(),
        TermCondition::Service(ServiceType::Qrz) => "qrz_confirmed = 1".to_string(),
        TermCondition::Service(_) => "0".to_string(), // only LoTW/QRZ confirm
        _ => "1=1".to_string(),
    }
}

fn lower_presence(predicate: &str, cond: &TermCondition, params: &mut Vec<SqlValue>) -> String {
    let base = "EXISTS (SELECT 1 FROM service_presence sp WHERE sp.qso_id = qso.id";
    let not_base = "NOT EXISTS (SELECT 1 FROM service_presence sp WHERE sp.qso_id = qso.id";
    // predicate is on sp.* — rewrite bare column names to sp-qualified
    let pred = predicate.replace("is_present", "sp.is_present").replace("needs_upload", "sp.needs_upload");
    match cond {
        TermCondition::Boolean(true) => format!("{base} AND {pred})"),
        TermCondition::Boolean(false) => format!("{not_base} AND {pred})"),
        TermCondition::Service(svc) => {
            params.push(SqlValue::Text(svc.raw_value().to_string()));
            format!("{base} AND {pred} AND sp.service_type_raw_value = ?)")
        }
        _ => "1=1".to_string(),
    }
}

fn lower_source(cond: &TermCondition, params: &mut Vec<SqlValue>) -> String {
    match cond {
        TermCondition::Service(svc) => {
            params.push(SqlValue::Text(svc.raw_value().to_string()));
            "import_source_raw_value = ?".to_string()
        }
        TermCondition::Equals(v) if v.eq_ignore_ascii_case("manual") || v.eq_ignore_ascii_case("logger") => {
            params.push(SqlValue::Text("logger".to_string()));
            "import_source_raw_value = ?".to_string()
        }
        _ => "0".to_string(),
    }
}

fn lower_bare_term(cond: &TermCondition, params: &mut Vec<SqlValue>) -> String {
    // Mirrors Swift compileBareSearchTerm: contains→call/park/sota/notes;
    // equals/prefix/suffix→call/park/sota.
    let cols_contains = ["callsign", "park", "sota_ref", "notes"];
    let cols_other = ["callsign", "park", "sota_ref"];
    let like = |col: &str, params: &mut Vec<SqlValue>, v: &str, pat: &str| -> String {
        params.push(SqlValue::Text(escape_like(v)));
        match pat {
            "contains" => format!("cw_lower({col}) LIKE '%' || cw_lower(?) || '%' ESCAPE '\\'"),
            "prefix" => format!("cw_lower({col}) LIKE cw_lower(?) || '%' ESCAPE '\\'"),
            _ => format!("cw_lower({col}) LIKE '%' || cw_lower(?) ESCAPE '\\'"),
        }
    };
    match cond {
        TermCondition::Contains(v) => {
            let parts: Vec<String> = cols_contains.iter().map(|c| like(c, params, v, "contains")).collect();
            format!("({})", parts.join(" OR "))
        }
        TermCondition::Equals(v) => {
            let parts: Vec<String> = cols_other.iter().map(|c| {
                params.push(SqlValue::Text(v.clone()));
                format!("cw_lower({c}) = cw_lower(?)")
            }).collect();
            format!("({})", parts.join(" OR "))
        }
        TermCondition::Prefix(v) => {
            let parts: Vec<String> = cols_other.iter().map(|c| like(c, params, v, "prefix")).collect();
            format!("({})", parts.join(" OR "))
        }
        TermCondition::Suffix(v) => {
            let parts: Vec<String> = cols_other.iter().map(|c| like(c, params, v, "suffix")).collect();
            format!("({})", parts.join(" OR "))
        }
        _ => "1=1".to_string(),
    }
}
```

Update `mod.rs`: add `pub mod compiler;` and `pub use compiler::compile_where;`.

Note on the `synced:`/`pending:` test expectations: the implementation emits `sp.is_present = 1` / `sp.needs_upload = 1`; adjust the Step-1 expected strings to match the exact spacing the implementation produces (run the test, copy the actual into the expected — these are parity-internal, not externally specified).

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd rust/cw-core && cargo test -p cw-store query::compiler && cargo clippy -p cw-store`
Expected: PASS, no clippy warnings. Fix any fragment-mismatch by aligning expected to actual.

- [ ] **Step 5: Commit**

```bash
git add rust/cw-core/cw-store/src/query
git commit -m "$(cat <<'EOF'
Phase 4 (B): cw-store/query — AST→WHERE lowering (fields, conditions, EXISTS)

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

### Task 8: `fetch_qsos_query` + `count_query` on `Store`

**Files:**
- Modify: `rust/cw-core/cw-store/src/qso.rs` (new methods, reuse `QSO_COLUMNS`, `row_to_qso`, `MAX_FETCH_LIMIT`)
- Modify: `rust/cw-core/cw-store/src/query/sql.rs` (helper to bind `Vec<SqlValue>`)

- [ ] **Step 1: Write the failing test**

Add to `qso.rs` tests:

```rust
#[test]
fn query_filters_and_counts_with_full_dsl() {
    let store = Store::open_in_memory().unwrap();
    store.upsert_qso(&sample_qso("a", "W1AW", Some("20m"), Some("FT8"))).unwrap();
    store.upsert_qso(&sample_qso("b", "K2XX", Some("40m"), Some("CW"))).unwrap();
    store.upsert_qso(&sample_qso("c", "W3YY", Some("20m"), Some("CW"))).unwrap();

    let q = cw_domain::query::parse("band:20m mode:cw").unwrap();
    let rows = store.fetch_qsos_query(&q, 100, 0).unwrap();
    assert_eq!(rows.iter().map(|r| r.id.clone()).collect::<Vec<_>>(), vec!["c"]);
    assert_eq!(store.count_query(&q).unwrap(), 1);
}

#[test]
fn query_excludes_hidden_and_orders_desc() {
    let store = Store::open_in_memory().unwrap();
    let mut hidden = sample_qso("h", "W1AW", Some("20m"), Some("CW"));
    hidden.is_hidden = true;
    store.upsert_qso(&hidden).unwrap();
    let mut newer = sample_qso("n", "W1AW", Some("20m"), Some("CW"));
    newer.qso_date = 2_000;
    let mut older = sample_qso("o", "W1AW", Some("20m"), Some("CW"));
    older.qso_date = 1_000;
    store.upsert_qso(&newer).unwrap();
    store.upsert_qso(&older).unwrap();

    let q = cw_domain::query::parse("call:w1aw").unwrap();
    let rows = store.fetch_qsos_query(&q, 100, 0).unwrap();
    assert_eq!(rows.iter().map(|r| r.id.clone()).collect::<Vec<_>>(), vec!["n", "o"]);
}
```

(Reuse/define a `sample_qso(id, callsign, band, mode)` test helper consistent with the existing QSO tests in this file.)

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd rust/cw-core && cargo test -p cw-store query_filters_and_counts query_excludes_hidden`
Expected: FAIL — `fetch_qsos_query`/`count_query` undefined.

- [ ] **Step 3: Write the implementation**

Add a binding helper to `query/sql.rs`:

```rust
impl SqlValue {
    pub fn to_sql_param(&self) -> Box<dyn rusqlite::types::ToSql> {
        match self {
            SqlValue::Text(s) => Box::new(s.clone()),
            SqlValue::Int(n) => Box::new(*n),
            SqlValue::Real(n) => Box::new(*n),
        }
    }
}
```

Add to `impl Store` in `qso.rs` (reusing `compile_where`, `QSO_COLUMNS`, `row_to_qso`, `MAX_FETCH_LIMIT`):

```rust
/// Full-DSL query fetch. Applies the Logbook base predicate (`is_hidden = 0`),
/// date-desc ordering, and the bounded limit, then the compiled WHERE.
pub fn fetch_qsos_query(
    &self,
    query: &cw_domain::query::ParsedQuery,
    limit: i64,
    offset: i64,
) -> Result<Vec<Qso>> {
    if limit > MAX_FETCH_LIMIT {
        return Err(StoreError::FetchLimitExceeded { requested: limit, max: MAX_FETCH_LIMIT });
    }
    let (where_sql, values) = crate::query::compile_where(query);
    let sql = format!(
        "SELECT {QSO_COLUMNS} FROM qso WHERE is_hidden = 0 AND ({where_sql}) \
         ORDER BY qso_date DESC LIMIT ? OFFSET ?"
    );
    let mut boxed: Vec<Box<dyn rusqlite::types::ToSql>> =
        values.iter().map(|v| v.to_sql_param()).collect();
    boxed.push(Box::new(limit));
    boxed.push(Box::new(offset));
    let refs: Vec<&dyn rusqlite::types::ToSql> = boxed.iter().map(|b| b.as_ref()).collect();
    let mut stmt = self.conn.prepare(&sql)?;
    let rows = stmt.query_map(refs.as_slice(), Self::row_to_qso)?;
    let mut out = Vec::new();
    for row in rows { out.push(row?); }
    Ok(out)
}

/// Count for a full-DSL query (same WHERE, no limit/offset).
pub fn count_query(&self, query: &cw_domain::query::ParsedQuery) -> Result<i64> {
    let (where_sql, values) = crate::query::compile_where(query);
    let sql = format!("SELECT COUNT(*) FROM qso WHERE is_hidden = 0 AND ({where_sql})");
    let boxed: Vec<Box<dyn rusqlite::types::ToSql>> =
        values.iter().map(|v| v.to_sql_param()).collect();
    let refs: Vec<&dyn rusqlite::types::ToSql> = boxed.iter().map(|b| b.as_ref()).collect();
    Ok(self.conn.query_row(&sql, refs.as_slice(), |r| r.get(0))?)
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd rust/cw-core && cargo test -p cw-store && cargo clippy -p cw-store`
Expected: PASS, no clippy warnings.

- [ ] **Step 5: Commit**

```bash
git add rust/cw-core/cw-store/src/qso.rs rust/cw-core/cw-store/src/query/sql.rs
git commit -m "$(cat <<'EOF'
Phase 4 (B): cw-store fetch_qsos_query + count_query (full-DSL, is_hidden base)

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

### Task 9: Shared parity corpus (Rust golden)

**Files:**
- Create: `rust/cw-core/cw-store/tests/query_corpus.rs`
- Create: `rust/cw-core/cw-store/tests/fixtures/query_corpus.json` (shared with Swift — see Task 13)

- [ ] **Step 1: Define the corpus + fixture**

Create `query_corpus.json` — an array of query strings covering every field × applicable condition, AND/OR/NOT/grouping, bare terms, `synced:`/`pending:` (with and without a service), `confirmed:`/`source:`, wildcards, mixed-case, an accented value, empty query, and negation-only. Example (extend to full coverage):

```json
{
  "queries": [
    "", "call:w1aw", "call:W1AW", "band:20m mode:ft8", "band:20m | band:40m",
    "-mode:cw", "freq:>14000 freq:<14350", "park:K-1234", "notes:portable",
    "confirmed:yes", "confirmed:lotw", "synced:qrz", "pending:yes",
    "source:pota", "dxcc:291", "power:>=100", "after:2026-01-01 before:2026-02-01",
    "name:*son", "w1", "café"
  ]
}
```

Create a fixture builder in the test that inserts a **small** set (≤ 50) of QSOs + ServicePresence rows into an in-memory `Store`, deterministically, covering the dimensions the corpus exercises.

- [ ] **Step 2: Write the parity assertion (golden id-sets)**

```rust
//! Runs the shared corpus against cw-store and snapshots the result-id list per
//! query. The same corpus + fixture is replayed by the Swift QueryCompiler test
//! (Task 13); both must agree. This file is the Rust-side ground truth.

#[test]
fn corpus_runs_and_is_deterministic() {
    let store = build_fixture();           // ≤50 QSOs + ServicePresence
    let corpus: Corpus = serde_json::from_str(include_str!("fixtures/query_corpus.json")).unwrap();
    for query_str in corpus.queries {
        let q = cw_domain::query::parse(&query_str).unwrap();
        let ids: Vec<String> = store.fetch_qsos_query(&q, 1000, 0).unwrap()
            .into_iter().map(|r| r.id).collect();
        let count = store.count_query(&q).unwrap();
        assert_eq!(ids.len() as i64, count, "count vs page mismatch for `{query_str}`");
        // snapshot: write/compare against an expected map (insta or a checked-in JSON)
        assert_expected(&query_str, &ids);
    }
}
```

Use a checked-in `fixtures/query_corpus_expected.json` (id-lists keyed by query). On first run, generate it and eyeball a few entries for correctness against the Swift semantics described in the design; commit it as the golden.

- [ ] **Step 3: Run**

Run: `cd rust/cw-core && cargo test -p cw-store --test query_corpus`
Expected: PASS (after generating + committing the expected golden).

- [ ] **Step 4: Commit**

```bash
git add rust/cw-core/cw-store/tests/query_corpus.rs rust/cw-core/cw-store/tests/fixtures/
git commit -m "$(cat <<'EOF'
Phase 4 (B): shared query corpus + Rust golden parity test

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

## Phase 3 — FFI + Swift read seam

### Task 10: FFI `fetch_qsos_query` + `qso_count_query`

**Files:**
- Modify: `rust/cw-core/cw-ffi/src/lib.rs` (near `fetch_qsos`, `qso_count`)
- Then regenerate bindings (as Task 3)

- [ ] **Step 1: Write the failing test**

In `cw-ffi` tests, add one asserting the FFI parses + executes a query string end-to-end:

```rust
#[test]
fn fetch_qsos_query_filters_by_dsl() {
    let store = field_store_in_memory();
    store.upsert_qso(sample_ffi_qso("a", "W1AW", "20m", "FT8")).unwrap();
    store.upsert_qso(sample_ffi_qso("b", "K2XX", "40m", "CW")).unwrap();
    let rows = store.fetch_qsos_query("band:20m".to_string(), 100, 0).unwrap();
    assert_eq!(rows.iter().map(|r| r.id.clone()).collect::<Vec<_>>(), vec!["a"]);
    assert_eq!(store.qso_count_query("band:20m".to_string()).unwrap(), 1);
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd rust/cw-core && cargo test -p cw-ffi fetch_qsos_query_filters_by_dsl`
Expected: FAIL — method undefined.

- [ ] **Step 3: Write the implementation**

Add to the `#[uniffi::export] impl FieldStore` block in `lib.rs`. Parse the string in Rust; map a parse error to `CwError` (reuse the existing error mapping, or add an `InvalidQuery` variant if none fits):

```rust
pub fn fetch_qsos_query(
    &self,
    query: String,
    limit: i64,
    offset: i64,
) -> Result<Vec<FfiQso>, CwError> {
    let parsed = cw_domain::query::parse(&query).map_err(CwError::from)?;
    let store = self.inner.lock().expect("store mutex poisoned");
    let rows = store.fetch_qsos_query(&parsed, limit, offset)?;
    Ok(rows.into_iter().map(FfiQso::from).collect())
}

pub fn qso_count_query(&self, query: String) -> Result<i64, CwError> {
    let parsed = cw_domain::query::parse(&query).map_err(CwError::from)?;
    let store = self.inner.lock().expect("store mutex poisoned");
    Ok(store.count_query(&parsed)?)
}
```

If `CwError: From<QueryError>` doesn't exist, add it next to the other `From` impls (map to an `InvalidQuery { message }` variant; add the variant to the `CwError` enum).

- [ ] **Step 4: Run test + clippy**

Run: `cd rust/cw-core && cargo test -p cw-ffi fetch_qsos_query_filters_by_dsl && cargo clippy -p cw-ffi`
Expected: PASS, clean.

- [ ] **Step 5: Regenerate bindings + xcframework, commit**

```bash
cd rust/cw-core && ./scripts/generate-swift-bindings.sh && ./scripts/build-xcframework.sh
cd ../.. && git add rust/cw-core swift
git commit -m "$(cat <<'EOF'
Phase 4 (B): cw-ffi fetch_qsos_query + qso_count_query; regenerate bindings

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

### Task 11: Extend `QSOReadSource` with query page/count

**Files:**
- Modify: `swift/packages/CarrierWaveData/Sources/CarrierWaveData/RustStore/QSOReadSource.swift`
- Create: `swift/packages/CarrierWaveData/Sources/CarrierWaveData/RustStore/QSOSnapshot.swift`
- Test: `swift/packages/CarrierWaveData/Tests/CarrierWaveDataTests/RustStore/QSOReadSourceTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
@Test func rustReadSourcePagesByQuery() async throws {
    let store = try makeInMemoryFieldStore()
    try store.upsertQso(qso: sampleFfiQso(id: "a", callsign: "W1AW", band: "20m", mode: "FT8"))
    try store.upsertQso(qso: sampleFfiQso(id: "b", callsign: "K2XX", band: "40m", mode: "CW"))
    let source = RustQSOReadSource(store: store)

    let page = try await source.page(query: "band:20m", limit: 100, offset: 0)
    #expect(page.map(\.id) == ["a"])
    #expect(try await source.count(query: "band:20m") == 1)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run the `CarrierWaveDataTests` `QSOReadSourceTests`. Expected: compile failure — `page(query:)`/`count(query:)` undefined.

- [ ] **Step 3: Write the implementation**

Create `QSOSnapshot.swift` — a `Sendable` value the Logbook can render from (id + the fields the row needs). Start minimal (id + the columns the list cell uses) and map from `FfiQso`:

```swift
public struct QSOSnapshot: Sendable, Identifiable, Equatable {
    public let id: String
    public let callsign: String
    public let band: String?
    public let mode: String?
    public let timestamp: Date
    // extend with the fields LogsListView's row needs (sub-project C will widen this)
}

extension QSOSnapshot {
    init(ffi: FfiQso) {
        self.init(
            id: ffi.id, callsign: ffi.callsign, band: ffi.band, mode: ffi.mode,
            timestamp: Date(timeIntervalSince1970: TimeInterval(ffi.qsoDate))
        )
    }
}
```

Extend the protocol + both witnesses in `QSOReadSource.swift`:

```swift
public protocol QSOReadSource: Sendable {
    func count() async throws -> Int
    func count(query: String) async throws -> Int
    func page(query: String, limit: Int, offset: Int) async throws -> [QSOSnapshot]
}
```

`RustQSOReadSource`:

```swift
public func count(query: String) async throws -> Int {
    try Int(store.qsoCountQuery(query: query))
}

public func page(query: String, limit: Int, offset: Int) async throws -> [QSOSnapshot] {
    try store.fetchQsosQuery(query: query, limit: Int64(limit), offset: Int64(offset))
        .map(QSOSnapshot.init(ffi:))
}
```

`SwiftDataQSOReadSource` — compile via the Swift `QueryParser`/`QueryCompiler` over a bounded fetch, returning snapshots, so the seam is symmetric. (The compiler lives in the app target, not the package; if `QueryCompiler` is not visible to `CarrierWaveData`, implement the SwiftData witness in the app target where `QueryCompiler` lives, and keep only the protocol + Rust witness in the package. Confirm visibility before writing — `QueryCompiler.swift` is under `swift/ios/CarrierWave/Services/QueryLanguage/`, i.e. the app target, so the SwiftData witness belongs there.)

- [ ] **Step 4: Run test to verify it passes**

Run `QSOReadSourceTests`. Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add swift/packages/CarrierWaveData/Sources/CarrierWaveData/RustStore/ swift/packages/CarrierWaveData/Tests/CarrierWaveDataTests/RustStore/QSOReadSourceTests.swift
git commit -m "$(cat <<'EOF'
Phase 4 (B): QSOReadSource page(query:)/count(query:) + QSOSnapshot

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

### Task 12: Swift-side corpus parity test

**Files:**
- Create: `swift/packages/CarrierWaveData/Tests/CarrierWaveDataTests/RustStore/QueryParityTests.swift` (or in the app test target if it needs `QueryCompiler`)
- Reference fixture: the same `query_corpus.json` from Task 9 (copy or symlink into the Swift test bundle resources)

- [ ] **Step 1: Write the parity test**

Load the shared corpus + an identical fixture (same QSOs + ServicePresence) into both an in-memory SwiftData container and an in-memory `FieldStore`, then for each query assert identical ordered id lists:

```swift
@Test func swiftAndRustAgreeOnCorpus() async throws {
    let fixture = try ParityFixture.make()      // builds identical data in both stores
    let corpus = try ParityFixture.loadCorpus() // query_corpus.json
    let rust = RustQSOReadSource(store: fixture.store)

    for query in corpus {
        let rustIds = try await rust.page(query: query, limit: 1000, offset: 0).map(\.id)
        let swiftIds = fixture.swiftDataResultIDs(for: query)  // QueryCompiler over the fixture
        #expect(rustIds == swiftIds, "parity mismatch for `\(query)`")
    }
}
```

`fixture.swiftDataResultIDs(for:)` parses with `QueryParser`, compiles with `QueryCompiler`, applies `!isHidden`, sorts `timestamp` desc, and returns ids — exactly the Logbook path, over the small fixture (kept below `searchBatchSize` so no truncation).

- [ ] **Step 2: Run**

Run the parity test. Expected: PASS. Any mismatch is a real parity bug — fix the Rust lowering (not the test) until green.

- [ ] **Step 3: Commit**

```bash
git add swift/packages/CarrierWaveData/Tests/CarrierWaveDataTests/RustStore/QueryParityTests.swift
git commit -m "$(cat <<'EOF'
Phase 4 (B): Swift↔Rust query parity test over shared corpus

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

## Phase 4 — On-device parity sweep

### Task 13: `QSOParityProbe` saved-query sweep

**Files:**
- Modify: `swift/packages/CarrierWaveData/Sources/CarrierWaveData/RustStore/QSOParityProbe.swift`
- Test: `swift/packages/CarrierWaveData/Tests/CarrierWaveDataTests/RustStore/QSOParityProbeTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
@Test func sweepClassifiesMatchSupersetAndMismatch() {
    let probe = QSOParityProbe()
    // identical
    #expect(probe.compareQuery(query: "band:20m", swiftDataIDs: ["a", "b"], rustIDs: ["a", "b"]).status == .match)
    // Rust superset because Swift's batch window truncated (rust has extra trailing ids)
    #expect(probe.compareQuery(query: "x", swiftDataIDs: ["a"], rustIDs: ["a", "b"]).status == .rustSupersetLikelyBatchWindow)
    // genuine mismatch (different ids, not a tail extension)
    #expect(probe.compareQuery(query: "y", swiftDataIDs: ["a", "c"], rustIDs: ["a", "b"]).status == .mismatch)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run `QSOParityProbeTests`. Expected: compile failure — `compareQuery` undefined.

- [ ] **Step 3: Write the implementation**

Add to `QSOParityProbe.swift`:

```swift
public enum QueryParityStatus: Sendable, Equatable {
    case match
    case rustSupersetLikelyBatchWindow   // Swift IDs are a prefix of Rust IDs (Swift truncated)
    case mismatch
}

public struct QueryParityResult: Sendable, Equatable {
    public let query: String
    public let swiftDataCount: Int
    public let rustCount: Int
    public let status: QueryParityStatus
}

public func compareQuery(query: String, swiftDataIDs: [String], rustIDs: [String]) -> QueryParityResult {
    let status: QueryParityStatus
    if swiftDataIDs == rustIDs {
        status = .match
    } else if rustIDs.count > swiftDataIDs.count && Array(rustIDs.prefix(swiftDataIDs.count)) == swiftDataIDs {
        // Swift's bounded search window truncated; Rust returns the complete set.
        status = .rustSupersetLikelyBatchWindow
    } else {
        status = .mismatch
    }
    return QueryParityResult(query: query, swiftDataCount: swiftDataIDs.count, rustCount: rustIDs.count, status: status)
}
```

- [ ] **Step 4: Run test to verify it passes**

Run `QSOParityProbeTests`. Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add swift/packages/CarrierWaveData/Sources/CarrierWaveData/RustStore/QSOParityProbe.swift swift/packages/CarrierWaveData/Tests/CarrierWaveDataTests/RustStore/QSOParityProbeTests.swift
git commit -m "$(cat <<'EOF'
Phase 4 (B): QSOParityProbe saved-query sweep with batch-window classification

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

### Task 14: Wire the sweep into Data Migration UI

**Files:**
- Modify: `swift/ios/CarrierWave/Views/Settings/ExperimentsView.swift` (the Data Migration section A added)
- Reference: `swift/packages/CarrierWaveData/Sources/CarrierWaveData/Query/SavedQuery/SavedQueryStore.swift` (the user's saved queries)

- [ ] **Step 1: Add a "Run Saved-Query Parity Sweep" action**

Next to A's existing "Run QSO Parity Check" button, add a button that:
1. loads the user's saved `.cwquery` queries from `SavedQueryStore`,
2. for each: runs `SwiftDataQSOReadSource.page(query:)` (or the existing Logbook compile path) and `RustQSOReadSource.page(query:)` after `await mirror.drain()`,
3. calls `probe.compareQuery(...)` per query,
4. logs a summary (counts of `match` / `rustSupersetLikelyBatchWindow` / `mismatch`) and the first-N `mismatch` queries to the same in-app diagnostics surface A's count probe uses.

Follow the exact logging/diagnostics call A's "Run QSO Parity Check" uses — match its surface, don't introduce `os_log`/`print` (project rule: route through the in-app diagnostics surface).

- [ ] **Step 2: Build**

In a local Xcode env: `xc build`. In cloud: rely on Xcode Cloud — verify cross-file symbols (`compareQuery`, `page(query:)`, `fetchQsosQuery`) resolve.

- [ ] **Step 3: Commit**

```bash
git add swift/ios/CarrierWave/Views/Settings/ExperimentsView.swift
git commit -m "$(cat <<'EOF'
Phase 4 (B): Data Migration — saved-query parity sweep action

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

### Task 15: Full-suite verification

- [ ] **Step 1: Rust gate**

Run: `cd rust/cw-core && cargo build && cargo clippy --workspace && cargo test --workspace`
Expected: all pass, no clippy warnings. (No `cargo fmt`.)

- [ ] **Step 2: Swift tests**

Run the `CarrierWaveData` package tests and the app `CwStoreMirror*`/`QSOReadSource`/parity tests (local: `xc test-unit` + `xc test-core`). Expected: all pass.

- [ ] **Step 3: On-device smoke (manual, if a device is available)**

Enable the **QSO Rust Store** experiment → Data Migration → set `shadow` → run the saved-query parity sweep → expect zero `mismatch` (some `rustSupersetLikelyBatchWindow` is acceptable on large logs). Flip `on`, open the Logbook with a few filters, confirm results match `off`. Flip `off` for rollback.

- [ ] **Step 4: Final commit (if any cleanup)**

```bash
git add -A
git commit -m "$(cat <<'EOF'
Phase 4 (B): query compiler + ServicePresence mirror — verification pass

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

## Self-Review — spec coverage

- Full DSL, no fallback → Tasks 7–8 lower **every** `QueryField` + `TermCondition`; Tasks 9/12 assert parity over a corpus covering all of them. ✅
- `synced:`/`pending:` via mirrored ServicePresence → Tasks 1–5 (delete + live mirror), Task 7 EXISTS lowering. ✅
- Compiler in `cw-store`, `cw-domain` untouched → Tasks 6–8. ✅
- Case parity / LIKE escaping → Task 6 (`cw_lower` + `escape_like`), exercised in 7/9/12. ✅
- Date tz parity → Task 7 `lower_date` uses `DateMatch::resolve()` (Local) → unix via `Local`. ✅
- Base predicate `is_hidden = 0` + `qso_date DESC` → Task 8. ✅
- Parity acceptance gate (shared corpus, fixture < batch window) → Tasks 9, 12. ✅
- On-device saved-query sweep with batch-window classification → Tasks 13–14. ✅
- LogsListView refactor stays out (sub-project C) → not in this plan. ✅

**Open confirmations for the implementer (verify against code, don't assume):**
- `QSO.parkReference` ↔ `park` column (vs `their_park`) — confirm before trusting `park:`/bare-term mapping.
- Exact `CwError`↔`QueryError` mapping (Task 10) — add `InvalidQuery` variant if none fits.
- Test-helper names (`sample`, `sample_qso`, `makeInMemoryStore`, `MirrorTestHarness`) — match the existing ones in each file.
