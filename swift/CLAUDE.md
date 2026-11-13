# Swift

Shared conventions for all Swift targets (iOS, macOS, packages, watch, widgets).

## Building and Testing

> **Cloud/web environment (Claude Code app):** Xcode is not available. Skip all `xc` / `make` commands. Focus on code changes only.
>
> Claude Code hooks automatically run SwiftFormat and SwiftLint on every Swift file edit. Formatting is fixed in place; lint violations block the edit until resolved. No manual quality check step is needed.
>
> **What hooks CAN'T catch:** Compilation errors (missing imports, type mismatches, access control). Xcode Cloud builds catch these on merge to main. Be careful with cross-file changes — if you rename a type or change a function signature, verify all call sites.

> **Local environment:** Use `xc quality` (format + lint + build) as the pre-commit gate.

When running locally with Xcode, use the **xcode-build** skill (`xc`) for all builds and tests. Device configured in `CLAUDE.local.md`.

```bash
xc build        # Build for device
xc test-unit    # Run unit tests (skip perf)
xc test-core    # CarrierWaveCore SPM tests (no device)
xc lint         # SwiftLint with JSON output
xc format       # SwiftFormat
xc quality      # format → lint → build (pre-commit gate)
xc deploy       # Build + install + launch on device
```

Deploy to device yourself (`make deploy`). Don't ask the user to build.

All package path dependencies are monorepo-relative (e.g. `../packages/CarrierWaveCore`).

## Code Standards

- `actor` for API clients, `@MainActor` for view-bound services
- Credentials in Keychain, never SwiftData
- Tests use in-memory SwiftData containers
- Follow linked docs: [Performance](../docs/PERFORMANCE.md), [Design Language](../docs/design-language.md), [Callsign Filtering](../docs/features/callsign-filtering.md), [Tours](../docs/features/tour-requirements.md), [Delete Confirmation](../docs/features/delete-confirmation.md)

## Performance Rules (MANDATORY)

Full details: [docs/PERFORMANCE.md](../docs/PERFORMANCE.md). These cause multi-second freezes or OOM crashes if violated:

- **QSO count must NEVER affect startup speed or UI responsiveness.** Background work takes longer — that's fine. Main thread impact must be O(1). Not even sublinear is acceptable.
- **Max 1,000 QSO/ServicePresence objects loaded at a time.** Use batched fetches with fresh `ModelContext` per batch. See PERFORMANCE.md for the required batching pattern.
- **Serialize concurrent full-table scans.** Multiple background computations scanning all QSOs must run sequentially, not concurrently — concurrent scans multiply peak memory and cause OOM on 4 GB devices.
- **`@Query` is BANNED** for QSO and ServicePresence — use `@State` + `FetchDescriptor` in `.task`
- **Always set `fetchLimit`** on QSO/ServicePresence descriptors — no unbounded fetches, ever
- **No unbounded scans** — no `filter`/`map`/`reduce`/`count` on collections without a prior `fetchLimit`; use predicates, not in-memory filtering
- **No network in text field `onChange`** without 500ms+ debounce
- **Bulk loading on background actors** — `ModelContext(container)` on the actor, convert to `Sendable` snapshots
- **NEVER use `nonisolated(unsafe)`** on mutable collections — use `NSLock`-protected storage with `lock.withLock` for synchronous cross-actor reads. Constants (e.g., `CBUUID`) are the only acceptable use.
- **Recursive SwiftUI views MUST type-erase with `AnyView`** — View A → View B → View A causes the SIL generator to hang forever (`computeLoweredRValueType` infinite loop). Use a `private var content: AnyView` property and return it from `body`. Same for recursive `@ViewBuilder` functions. See PERFORMANCE.md for the pattern.

## Linting & Formatting

SwiftLint + SwiftFormat. **Pre-commit hooks block on ANY violation.** Run `xc format` before committing (local Xcode environment only — in cloud/web, the user will format locally).

**Hard limits:**
- File: 500 lines | Function body: 50 lines | Type body: 300 lines
- Line length: 120 chars | Cyclomatic complexity: 15
- Nesting: 2 type levels, 3 function levels

Split proactively when approaching limits.

### SwiftLint Naming Rules

Follow these when writing code — violations block commits:

- **No single-letter variables.** Minimum 2 characters. Allowed exceptions: `id`, `ok`, `i`, `j`, `k`, `x`, `y`, `z`, `db`, `tz`, `rx`, `tx`, `n`, `m`, `dp`, `e`, `v`, `a`, `b`.
- **Type names:** 3–50 characters.
- **No trailing closures with multiple closure arguments** — use labeled syntax instead.
- **Prefer `first(where:)` over `filter(...).first`**, `last(where:)` over `filter(...).last`, `contains(where:)` over `filter(...).isEmpty`.
- **Prefer `sorted().first`/`.last` over manual min/max** — use `sorted_first_last` pattern.
- **Use `reduce(into:)` over `reduce()`** for collections (avoids copies).
- **No explicit `.init()`** — use implicit initialization.
- **No Yoda conditions** (e.g., `42 == x`) — use `x == 42`.
- **No redundant nil coalescing** (e.g., `x ?? nil`).
- **No redundant type annotations** when the type is obvious from context.
- **NEVER use `import os` or `import os.log`** — the Darwin `os` module shadows Foundation types across the entire target, causing cascading build failures ("Cannot find 'FileManager'/'Date'/'URL' in scope"). Use `import OSLog` instead (provides `Logger`, `OSLog`, `OSSignposter`).

## Quality Checks

Always run a full build (`xc build`) after making changes to Swift files. Fix all build errors, lint violations (SwiftLint function length, parameter count, trailing closure), and Sendable/MainActor isolation issues before presenting work as complete.

## Swift Conventions

When splitting Swift files or moving code to extensions, remember that Swift extensions cannot access `private` or `private(set)` properties. Change access to `internal` or `fileprivate` before splitting. Always build immediately after splitting to catch access control errors.

## UI Implementation

When implementing UI changes from mockups or screenshots, match the FULL visual design on the first pass — colors, spacing, typography, dark/light aesthetics, and layout structure. Do not apply only partial token changes.

## Metadata Pseudo-Modes (IMPORTANT)

Modes `WEATHER`, `SOLAR`, `NOTE` are PoLo activation metadata — NOT actual QSOs.

**NEVER** sync, upload, count in stats, or display on map. Use `QSOMode.metadataModes` or `QSOMode.isMetadata(_:)` from CarrierWaveData — the single source of truth. All enforcement sites reference this shared constant. See `ImportService`, `LoggingSessionManager`, `SyncService+Upload`, `POTAClient+Upload`, `QSOStatistics`, `StatsComputationActor`.
