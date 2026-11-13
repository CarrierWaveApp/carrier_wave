# Investigation: iOS test target — SwiftData container failures in `Schema([RadioMacro.self])`

## Symptom

After the CAR-272 compile fix (`67200a8b`), the iOS test target compiles cleanly
but two unrelated suites fail every run, both with the same error:

```
SwiftDataError(_error: SwiftData.SwiftDataError._Error.loadIssueModelContainer,
                _explanation: nil)
```

Affected suites (every test inside fails, all in `setUp`):

- `CarrierWaveTests/ServicePresenceTests` — 24 tests
- `CarrierWaveTests/LoggingSessionTests` — 28 tests

Both suites' `setUp()` calls `TestModelContainer.createWithContext()` which
constructs:

```swift
Schema(CarrierWaveSchema.models + [POTAUploadAttempt.self, Friendship.self, …])
```

The exact same construction also fails in a minimal diagnostic:

```swift
let schema = Schema([RadioMacro.self])
let config = ModelConfiguration(isStoredInMemoryOnly: true)
_ = try ModelContainer(for: schema, configurations: [config])
// throws SwiftDataError.loadIssueModelContainer
```

## Hypothesis

`RadioMacro` (added by CAR-269 in commit `e0aa6130`) has a SwiftData schema
problem that only surfaces in the iOS app's test target (`@testable import
CarrierWave` plus `import CarrierWaveData`), not in the CarrierWaveData package
test target. The same `Schema([RadioMacro.self])` construction is exercised by
`MacrosRegistryServiceTests` in CarrierWaveData and passes cleanly.

The fact that the failure is reproducible from a one-model schema rules out:

- Schema-level duplicates (we re-add `WebSDRRecording`/`WebSDRFavorite` on top
  of `CarrierWaveSchema.models`, but removing them changed nothing)
- Missing `CustomNeed` (iOS-target-only model; adding it to the test container
  changed nothing)
- Stale `loadIssue` reasons inherited from production: `ModelConfiguration` is
  `isStoredInMemoryOnly: true`, so there is no on-disk store to migrate from

## Evidence

### 1. The failure is `RadioMacro`-specific

A minimal `MinimalContainerDiagTest` in the iOS test target attempted six
schema permutations:

| Schema                                          | Result |
|-------------------------------------------------|--------|
| `Schema([QSO.self])`                            | passed |
| `Schema([ServicePresence.self])`                | passed |
| `Schema([QSO.self, ServicePresence.self])`      | passed |
| `Schema([LoggingSession.self])`                 | passed |
| `Schema([RadioMacro.self])`                     | **failed** |
| `Schema(CarrierWaveSchema.models)` (full bundle)| **failed** |

So `RadioMacro` is sufficient to provoke the failure on its own.

### 2. The same construction passes in CarrierWaveData package tests

`MacrosRegistryServiceTests.makeContainer()`:

```swift
private func makeContainer() throws -> ModelContainer {
    let schema = Schema([RadioMacro.self])
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    return try ModelContainer(for: schema, configurations: [config])
}
```

This is exercised by 5 tests (`MacrosRegistryServiceTests`) — all green in
`swift test` runs against the package directly.

Difference between the two test environments:

- **Package test target** (`CarrierWaveDataTests`): pulls in
  `CarrierWaveData` as a direct dependency. `RadioMacro` is compiled into the
  same module that the test imports.
- **iOS test target** (`CarrierWaveTests`): `@testable import CarrierWave`
  plus `import CarrierWaveData`. `RadioMacro` arrives through the
  `CarrierWaveData` precompiled framework, while the iOS app target is
  recompiled with `@testable`.

### 3. `SwiftDataError._explanation` is `nil`

The error surface gives no second-stage hint — `_explanation` is `nil`, and
the simulator system log captured during the test run shows no SwiftData
subsystem messages from the test process (`Clone 1 of iPhone 17 Pro`).

### 4. Inspected for known schema landmines

- All stored properties have valid SwiftData types (`UUID`, `String`, `String?`,
  `Data`, `Int`, `Bool`, `Bool?`, `Date`).
- `@Attribute(.unique) public var id = UUID()` is the same pattern as `QSO.id`.
- Only one `@Relationship` in the package (`QSO.servicePresences`), unrelated.
- `nonisolated public final class RadioMacro` matches `QSO`'s declaration.
- Tried replacing `format: Int = RadioMacroDocument.currentFormat` with a
  literal `2` — no change, so it's not a static-default reference.

### 5. Pre-existing nature

This isn't a regression from CAR-272 — `RadioMacro` was added by CAR-269 on
2026-05-23 (`e0aa6130`). The iOS test target has been failing to compile
since that commit (the `theirGrid` parameter drift was the visible failure,
but the SwiftData failure was hiding underneath the cascade). After the
compile fix, the SwiftData failure surfaces.

## Root Cause

**Unknown.** The minimal repro `Schema([RadioMacro.self])` succeeding in the
package and failing in the iOS test target points at module/runtime
metadata differences for the `@Model` macro, but the error is opaque
(`_explanation: nil`) and the SwiftData subsystem produces no log lines we
can grep against.

Plausible next-investigation paths:

1. **CloudKit / `@Attribute(.allowsCloudEncryption)` mismatch.** `RadioMacro`
   has CloudKit-shaped fields (Data blobs encoded with the journal engine).
   The iOS app's `ModelConfiguration` uses `cloudKitDatabase: .none`; the
   test config uses `isStoredInMemoryOnly: true`. Maybe @Model's runtime
   schema validator sees a mismatch that the production `.none` path
   tolerates.
2. **Compiled-from-framework vs. compiled-here.** `@Model` injects schema
   metadata into the class. Crossing the package-precompiled boundary into
   `@testable`-recompiled iOS code may break a hash/version check.
3. **Default-value evaluation timing.** `format` defaults to
   `RadioMacroDocument.currentFormat`. The SwiftData schema builder may try
   to evaluate that default eagerly. Changing to a literal didn't help, but
   `cloudDirtyFlag = false` (no type annotation) and `argsJSON = Data()`
   (empty Data) may have their own quirks.
4. **The `format` keyword.** SwiftData/Core Data has a reserved
   `formatVersion` and similar. Renaming `RadioMacro.format` to e.g.
   `documentFormat` is a cheap experiment worth trying.

## Fix

**None applied.** Documented as a follow-up because:

- The two suites failing are pre-existing on `main` independent of CAR-272.
- The CAR-272 code adds CarrierWaveData package tests that exercise
  `Schema([RadioMacro.self])` and **pass** — coverage isn't lost.
- Production app launches and uses `RadioMacro` against the same schema via
  `ContainerSetup.createModelContainer` without error. The bug is
  test-target-specific.

## Lessons

- When a SwiftData container fails with `loadIssueModelContainer` and
  `_explanation: nil`, the model-by-model ablation pattern (`Schema([X.self])`
  one at a time) is the fastest way to localise the offending model.
- The iOS test target compiles and runs models through a different code path
  than the CarrierWaveData package tests. New `@Model` types should be
  covered by **both** a package-side and an app-side container construction
  test so regressions don't hide for weeks.
- `SwiftDataError._explanation` being `nil` is itself a problem worth filing
  — SwiftData should surface the underlying NSError userInfo.

## Next steps (proposed)

- Open a follow-up ticket: "Fix `Schema([RadioMacro.self])` in iOS test
  target".
- First experiment: rename `RadioMacro.format` → `RadioMacro.documentFormat`
  to test the reserved-keyword hypothesis (5-minute experiment).
- Second experiment: add a tiny `RadioMacroContainerTest` in the iOS test
  target with no `@testable import CarrierWave`, only `import
  CarrierWaveData`. If it passes, the `@testable` recompile is implicated.
