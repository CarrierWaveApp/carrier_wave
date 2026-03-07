# Carrier Wave

SwiftUI/SwiftData iOS app for amateur radio QSO logging with cloud sync to QRZ, POTA, and Ham2K LoFi.

> Read this file and linked docs for context. Only explore source files when actively implementing.

## Project Architecture

Monorepo containing the iOS app, macOS companion (CW Sweep), and two shared SPM packages. A separate Rust server backend handles the activities API. Deploy means building and deploying to a physical device. Release involves version bump, changelog, git tag, Discord notification, and App Store upload.

```
carrier_wave/
├── CarrierWave/           # iOS app (SwiftUI/SwiftData)
├── CarrierWaveCore/       # SPM: protocol logic, parsers, utilities, FT8 codec
├── CarrierWaveData/       # SPM: SwiftData models, cloud sync, shared services
├── CWSweep/               # macOS companion app (xcodeproj from xcodegen)
├── CarrierWaveTests/      # iOS app tests
├── CarrierWaveWatch/      # watchOS companion
└── CarrierWaveWidgets/    # Widget extension
```

All package path dependencies are monorepo-relative (e.g. `../CarrierWaveCore`).

## File Discovery

- Use [docs/FILE_INDEX.md](docs/FILE_INDEX.md) to locate files by feature/purpose
- **FORBIDDEN:** Scanning all `.swift` files, broad `Glob`/`Grep` across the repo, reading more than 5 files at once
- When adding/removing files, update the file index

## Building and Testing

> **Cloud/web environment (Claude Code app):** Xcode is not available. Skip all `xc` / `make` commands. Focus on code changes only. After modifying any `.swift` files, create or append to `.needs-quality-check` with a summary of what changed (one line per commit), then commit it alongside your changes. This signals that formatting and build verification are needed locally.

> **Local environment:** On session start, check for `.needs-quality-check`. If it exists, run `xc quality` (format + lint + build). If quality passes, delete the file and commit the cleanup. If it fails, fix the issues before continuing.

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

## Quick Reference

| Area | Details |
|------|---------|
| Architecture | [docs/architecture.md](docs/architecture.md) |
| Setup | [docs/SETUP.md](docs/SETUP.md) |
| Design Language | [docs/design-language.md](docs/design-language.md) |
| Sync System | [docs/features/sync.md](docs/features/sync.md) |
| iCloud Sync & Backup | [docs/features/icloud-sync.md](docs/features/icloud-sync.md) |
| Statistics | [docs/features/statistics.md](docs/features/statistics.md) |
| Performance | [docs/PERFORMANCE.md](docs/PERFORMANCE.md) |
| Tours | [docs/features/tour-requirements.md](docs/features/tour-requirements.md) |
| Delete Confirmation | [docs/features/delete-confirmation.md](docs/features/delete-confirmation.md) |
| Releasing | [docs/RELEASING.md](docs/RELEASING.md) |
| Investigation Template | [docs/investigation-template.md](docs/investigation-template.md) |

## Code Standards

- `actor` for API clients, `@MainActor` for view-bound services
- Credentials in Keychain, never SwiftData
- Tests use in-memory SwiftData containers
- Follow linked docs: [Performance](docs/PERFORMANCE.md), [Design Language](docs/design-language.md), [Callsign Filtering](docs/features/callsign-filtering.md), [Tours](docs/features/tour-requirements.md), [Delete Confirmation](docs/features/delete-confirmation.md)

## Metadata Pseudo-Modes (IMPORTANT)

Modes `WEATHER`, `SOLAR`, `NOTE` are PoLo activation metadata — NOT actual QSOs.

**NEVER** sync, upload, count in stats, or display on map. Each enforcement site defines its own `metadataModes: Set<String>` — keep them in sync. See `ImportService`, `LoggingSessionManager`, `SyncService+Upload`, `POTAClient+Upload`, `QSOStatistics`, `StatsComputationActor`, `MapDataLoadingActor`.

## Performance Rules (MANDATORY)

Full details: [docs/PERFORMANCE.md](docs/PERFORMANCE.md). These cause multi-second freezes if violated:

- **`@Query` is BANNED** for QSO and ServicePresence — use `@State` + `FetchDescriptor` in `.task`
- **Always set `fetchLimit`** on QSO/ServicePresence descriptors
- **No full-table scans on main thread** — use predicates, not filter/map in view code
- **No network in text field `onChange`** without 500ms+ debounce
- **Bulk loading on background actors** — `ModelContext(container)` on the actor, convert to `Sendable` snapshots

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

## Model Selection

Default **Sonnet** for coding tasks. **Opus** for: failed first attempts, 5+ file spans, architecture, security. **Haiku** for: search/grep, simple edits, worker subagents.

## Changelog

Maintain `CHANGELOG.md` incrementally using [Keep a Changelog](https://keepachangelog.com/). Update after completing features/fixes. Full conventions in [docs/RELEASING.md](docs/RELEASING.md).

## Investigation Traces

Create `docs/investigations/YYYY-MM-DD-<desc>.md` when debugging non-trivial issues. Template: [docs/investigation-template.md](docs/investigation-template.md).

## Issue Tracking

**Linear** for all issues (CAR-XXX). Use `linear-cli` skill. **Never use beads.**

```bash
linear issue list --state backlog --all-assignees --sort priority --team CAR --no-pager --limit 20
linear issue view CAR-XX --no-comments --no-pager
```

- Include issue ID in commit messages for auto-linking
- Comment on issues after committing: `linear issue comment add <ID> -b "<summary>"`
- Mark done: `linear issue update CAR-XX -s "Done"`
- Also check `docs/plans/human/` and `docs/bugs/` for work not yet in Linear

## Workflow Rules

When asked to commit and deploy, execute the full pipeline: build → fix any issues → deploy to device → commit → push. Don't stop at just committing.

When asked to implement changes, start coding immediately. Do not spend more than 2-3 minutes on exploration/planning before writing actual code. If a plan is needed, write it concisely and move to implementation in the same session.

## Quality Checks

Always run a full build (`xc build`) after making changes to Swift files. Fix all build errors, lint violations (SwiftLint function length, parameter count, trailing closure), and Sendable/MainActor isolation issues before presenting work as complete.

## Swift Conventions

When splitting Swift files or moving code to extensions, remember that Swift extensions cannot access `private` or `private(set)` properties. Change access to `internal` or `fileprivate` before splitting. Always build immediately after splitting to catch access control errors.

## UI Implementation

When implementing UI changes from mockups or screenshots, match the FULL visual design on the first pass — colors, spacing, typography, dark/light aesthetics, and layout structure. Do not apply only partial token changes.

## Git Workflow

**Do NOT use git worktrees.** Work on main or feature branches in the primary directory.
