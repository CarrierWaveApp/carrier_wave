# Carrier Wave

> **IMPORTANT:** For general project context, read this file and linked docs.
> Only explore source files when actively implementing, planning, or debugging.

## File Discovery Rules

**FORBIDDEN:**
- Scanning all `.swift` files (e.g., `Glob **/*.swift`, `Grep` across entire repo)
- Using Task/Explore agents to "find all files" or "explore the codebase structure"
- Any broad file discovery that reads more than 5 files at once

**REQUIRED:**
- Use the File Index below to locate files by feature/purpose
- Read specific files by path from the index
- When editing files, update this index if adding/removing/renaming files

## File Index

See [docs/FILE_INDEX.md](docs/FILE_INDEX.md) for the complete file-to-purpose mapping.

## Model Selection

When spawning subagents via the Task tool, select models based on task complexity:

| Task Type | Model | Reasoning |
|-----------|-------|-----------|
| Exploration/search | Haiku | Fast, cheap, good enough for finding files |
| Simple edits | Haiku | Single-file changes, clear instructions |
| Multi-file implementation | Sonnet | Best balance for coding |
| Complex architecture | Opus | Deep reasoning needed |
| PR reviews | Sonnet | Understands context, catches nuance |
| Security analysis | Opus | Can't afford to miss vulnerabilities |
| Writing docs | Haiku | Structure is simple |
| Debugging complex bugs | Opus | Needs to hold entire system in mind |

**Guidelines:**
- Default to **Sonnet** for 90% of coding tasks
- Upgrade to **Opus** when: first attempt failed, task spans 5+ files, architectural decisions, or security-critical code
- Downgrade to **Haiku** when: task is repetitive, instructions are very clear, or using as a "worker" in multi-agent setup

## Building and Testing

Use the **xcode-build** skill (`~/.claude/skills/xcode-build/scripts/xc`) for all builds and tests. This wraps xcodebuild with `-quiet` and `xcresulttool` for minimal token output. All builds target the physical device **theseus** (no simulator).

```bash
xc build        # Build for device
xc test-unit    # Run unit tests (skip perf)
xc test-core    # CarrierWaveCore SPM tests (no device)
xc lint          # SwiftLint with JSON output
xc format        # SwiftFormat
xc quality       # format → lint → build (pre-commit gate)
xc deploy        # Build + install + launch on theseus
```

The Makefile is still available for simulator-based builds/tests (`make build`, `make test`) when needed.

## Overview

Carrier Wave is a SwiftUI/SwiftData iOS app for amateur radio QSO (contact) logging with cloud sync to QRZ, POTA, and Ham2K LoFi.

## Quick Reference

| Area | Description | Details |
|------|-------------|---------|
| Architecture | Data models, services, view hierarchy | [docs/architecture.md](docs/architecture.md) |
| Setup | Development environment, build commands | [docs/SETUP.md](docs/SETUP.md) |
| Design Language | Visual patterns, colors, typography, components | [docs/design-language.md](docs/design-language.md) |
| Sync System | QRZ, POTA, LoFi integration | [docs/features/sync.md](docs/features/sync.md) |
| Statistics | Dashboard stats and drilldown views | [docs/features/statistics.md](docs/features/statistics.md) |
| Performance | View body rules, critical views, review checklist | [docs/PERFORMANCE.md](docs/PERFORMANCE.md) |
| Tour Requirements | Feature tour rules, mini tour implementation | [docs/features/tour-requirements.md](docs/features/tour-requirements.md) |

## Code Standards

- Use `actor` for API clients (thread safety)
- Use `@MainActor` for view-bound services
- Store credentials in Keychain, never in SwiftData
- Tests use in-memory SwiftData containers
- **Follow [Performance Guidelines](docs/PERFORMANCE.md)** — especially for Logger, Map, and tab transitions
- **Follow [Callsign Filtering Guidelines](docs/features/callsign-filtering.md)** — only operate on primary callsign for syncs
- **Follow [Design Language](docs/design-language.md)** — colors, typography, spacing, component patterns, and **HIG compliance checklist** (accessibility labels, touch targets, @ScaledMetric, semantic colors, haptics, sheet navigation)
- **Follow [Tour Requirements](docs/features/tour-requirements.md)** — all major/minor features must have tours

## Metadata Pseudo-Modes (IMPORTANT)

Ham2K PoLo uses special "modes" to store activation metadata that are NOT actual QSOs:
- `WEATHER` - Weather conditions during activation
- `SOLAR` - Solar conditions (K-index, SFI, etc.)
- `NOTE` - Activation notes

**These must NEVER be:**
- Synced to QRZ, POTA, LoFi, or any other service
- Marked with `needsUpload` in ServicePresence
- Counted in QSO statistics
- Displayed on the map

**Where this is enforced:**
- `ImportService.createServicePresenceRecords` - Skips upload markers for metadata modes
- `LoggingSessionManager.markForUpload` - Skips upload markers for metadata modes  
- `SyncService+Upload.uploadToPOTA` - Filters out metadata before upload
- `POTAClient+Upload.buildUploadRequest` - Filters out metadata before ADIF generation
- `QSOStatistics`, `StatsComputationActor`, `MapDataLoadingActor` - Filter out metadata from calculations

**Constant locations:** Each file defines its own `metadataModes: Set<String>` constant. Keep them in sync.

## Performance Rules (MANDATORY)

**These rules are non-negotiable. Violating them causes multi-second UI freezes for users with large datasets.**

### BANNED: @Query for QSO or ServicePresence

**`@Query` is completely BANNED for QSO and ServicePresence tables.** No exceptions.

```swift
// BANNED - will freeze UI for seconds
@Query var qsos: [QSO]
@Query(filter: #Predicate<QSO> { !$0.isHidden }) var qsos: [QSO]
@Query var presence: [ServicePresence]

// REQUIRED - use @State with manual FetchDescriptor in .task
@State private var qsos: [QSO] = []
.task {
    var descriptor = FetchDescriptor<QSO>(...)
    descriptor.fetchLimit = 100
    qsos = (try? modelContext.fetch(descriptor)) ?? []
}
```

### No Full Table Scans on Main Thread

1. **NEVER call `FetchDescriptor` without `fetchLimit`** for QSO/ServicePresence
2. **NEVER filter/map/iterate full collections in view code** — use database predicates instead
3. **NEVER load data synchronously in `onAppear` or `onChange`** — use `.task` with cancellation

### Network/IO in Input Handlers

1. **NEVER trigger network requests from text field `onChange`** without aggressive debouncing (500ms+)
2. **NEVER load remote resources (URLs, files) during first keystroke** — preload on view appear
3. **NEVER block the main thread waiting for cache population** — show UI immediately, load async

### Background Work Requirements

1. **All bulk data loading MUST happen on a background actor** — create a new `ModelContext(container)` on the actor
2. **Convert managed objects to `Sendable` snapshots** immediately after fetching, before crossing actor boundaries
3. **All network fetches MUST be cancellable** and not block UI updates

**Pattern for background SwiftData loading:**
```swift
actor MyLoadingActor {
    func loadData(container: ModelContainer) async throws -> [MySnapshot] {
        let context = ModelContext(container)  // Create context on background actor
        context.autosaveEnabled = false
        // Fetch and convert to Sendable snapshots here
    }
}
```

See `StatsComputationActor`, `MapDataLoadingActor` for full examples.

See [Performance Guidelines](docs/PERFORMANCE.md) for detailed patterns and examples.

## Linting & Formatting

Uses SwiftLint (`.swiftlint.yml`) and SwiftFormat (`.swiftformat`). **Pre-commit hooks block commits on ANY SwiftLint violation (warnings included).** Treat warning thresholds as hard limits.

**Hard limits (treat as maximums when writing code):**
- **File length: 500 lines** — split into extensions in separate files before hitting this
- **Function body: 50 lines** (excluding comments/whitespace) — extract helpers proactively
- **Type body: 300 lines** — split into extensions
- **Line length: 120 characters**
- **Cyclomatic complexity: 15**

When creating or modifying files, check line count before committing. If a file is near 450 lines and you're adding code, split first. If a function is near 40 lines and you're adding logic, extract a helper.

**Formatting rules (run `make format` before committing):**
- 4-space indentation, no tabs
- LF line endings
- Trailing commas allowed
- `else` on same line as closing brace
- Remove explicit `self` where possible
- Imports sorted, testable imports at bottom

## Getting Started

See [docs/SETUP.md](docs/SETUP.md) for device builds and additional commands.

## Version Updates

When releasing a new version, follow these steps:

### 1. Update version in code

Update **all three** locations:

1. **Xcode project** (`CarrierWave.xcodeproj/project.pbxproj`):
   - `MARKETING_VERSION` - The user-facing version (e.g., "1.2.0")
   - `CURRENT_PROJECT_VERSION` - The build number (increment for each build)

2. **Settings view** (`CarrierWave/Views/Settings/SettingsView.swift`):
   - Update the hardcoded version string in the "About" section (~line 448)

3. **Changelog** (`CHANGELOG.md`):
   - Rename `[Unreleased]` to `[X.Y.Z] - YYYY-MM-DD` with the new version and current date
   - Add a new empty `[Unreleased]` section at the top for future changes

### 2. Commit and release

After committing the version bump:

```bash
make release VERSION=X.Y.Z
```

This will:
- Create an annotated git tag `vX.Y.Z` with the changelog as the tag message
- Push the tag to GitHub
- Send a release notification to Discord (if `DISCORD_WEBHOOK_URL` is configured)

### Discord notifications

To enable Discord release notifications, set the `DISCORD_WEBHOOK_URL` environment variable or add it to a `.env` file in the project root:

```bash
DISCORD_WEBHOOK_URL=https://discord.com/api/webhooks/...
```

## Changelog

**Maintain the changelog incrementally as you work.** Do not construct it from git history.

**File:** `CHANGELOG.md`

**When to update:**
- After completing a feature (add to "Added" section)
- After fixing a bug (add to "Fixed" section)
- After making breaking or notable changes (add to "Changed" section)

**Format:** Follow [Keep a Changelog](https://keepachangelog.com/) conventions:

```markdown
## [Unreleased]

### Added
- New feature description

### Fixed
- Bug fix description

### Changed
- Notable change description
```

**Guidelines:**
- Write entries immediately after completing work, while context is fresh
- Use imperative mood ("Add feature" not "Added feature")
- Be specific but concise - one line per change
- Group related changes under a single bullet with sub-items if needed
- **One section per type:** Each version should have at most one `### Added`, one `### Changed`, one `### Fixed`, and one `### Removed` section. Merge entries into existing sections rather than creating duplicates.
- **Section order:** Added → Changed → Fixed → Removed
- When releasing, rename `[Unreleased]` to `[X.Y.Z] - YYYY-MM-DD`

## Investigation Traces (REQUIRED)

**When debugging or investigating any non-trivial issue, create a markdown artifact to document the investigation.**

**Location:** `docs/investigations/YYYY-MM-DD-<short-description>.md`

**When to create:**
- Debugging a bug that requires exploring multiple files or hypotheses
- Investigating user-reported issues
- Diagnosing build failures, crashes, or unexpected behavior
- Any investigation taking more than a few minutes

**Format:**

```markdown
# Investigation: <Short Description>

**Date:** YYYY-MM-DD
**Status:** In Progress | Resolved | Blocked | Abandoned
**Outcome:** <One-line summary of resolution, if resolved>

## Problem Statement

<What triggered this investigation? User report, error message, etc.>

## Hypotheses

### Hypothesis 1: <Brief description>
- **Evidence for:** <What supports this theory>
- **Evidence against:** <What contradicts it>
- **Tested:** Yes/No
- **Result:** <What we learned>

### Hypothesis 2: <Brief description>
...

## Investigation Log

### <Timestamp or step number>
<What was checked, what was found, what was tried>

### <Next step>
...

## Files Examined

| File | Relevance | Finding |
|------|-----------|---------|
| `path/to/file.swift` | <Why looked here> | <What was found> |

## Root Cause

<If found: detailed explanation of the root cause>

## Resolution

<If resolved: what fix was applied, or why issue was closed without fix>

## Lessons Learned

<Optional: patterns to watch for, documentation to update, etc.>
```

**Guidelines:**
- Create the file at the START of the investigation, not the end
- Update incrementally as you discover new information
- Document dead ends too — they prevent re-investigating the same paths
- Mark the status as **Resolved** and add **Outcome** when done
- Link to related bugs/plans if applicable

## Issue and feature ideas

I'll occasionally store human-generated plans/bugs/etc in `docs/plans/human` and `docs/bugs`. Look through these to find new work to do. Mark the documents as done in a way that you can easily find once they're completed.

## Issue Tracking

**Use Linear for all issue tracking.** Issue references like CAR-45 are Linear issues. Use the `linear-cli` skill to interact with them.

**NEVER use beads.** Do not invoke any `beads:*` skills. This project does not use beads.

**Finding issues:**
When the user asks for the next issue or work to do, query Linear for backlog issues:
```bash
linear issue list --state backlog --all-assignees --sort priority --team CAR --no-pager --limit 20
```
- Use `--state backlog` for unstarted work (NOT `--status "Todo"` — that flag doesn't exist)
- Use `--all-states` to see everything including Done
- `--no-pager` works on `issue list` but NOT on `issue update` or other commands
- View details with `linear issue view CAR-XX --no-comments --no-pager`
- Also check `docs/plans/human/` and `docs/bugs/` for human-written plans/bugs not yet in Linear

**Workflow:**
- At the start of a task, ask the user if there is a relevant Linear issue to associate with
- Include the issue ID (e.g., `CAR-45`) in commit messages so Linear links them automatically
- After committing, post a summarized description of the changes as a comment on the Linear issue using `linear issue comment add <ID> -b "<summary>"`
- When work is done, mark the issue: `linear issue update CAR-XX -s "Done"`

## Git Workflow

**Do NOT use git worktrees.** All work should be done on the main branch or feature branches in the primary working directory.
