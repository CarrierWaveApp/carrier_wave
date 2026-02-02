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

**NEVER build, run tests, or use the iOS simulator yourself. Always prompt the user to do so.**

When you need to verify changes compile or tests pass, ask the user to run the appropriate command (e.g., `make build`, `make test`) and report back the results.

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

## Code Standards

- **Maximum file size: 1000 lines.** Refactor when approaching this limit.
- Use `actor` for API clients (thread safety)
- Use `@MainActor` for view-bound services
- Store credentials in Keychain, never in SwiftData
- Tests use in-memory SwiftData containers
- **Follow [Performance Guidelines](docs/PERFORMANCE.md)** — especially for Logger, Map, and tab transitions
- **Follow [Callsign Filtering Guidelines](docs/features/callsign-filtering.md)** — only operate on primary callsign for syncs
- **Follow [Design Language](docs/design-language.md)** — colors, typography, spacing, and component patterns

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

1. **All statistics computation MUST use cooperative yielding** (`Task.yield()` between phases)
2. **All bulk data loading MUST happen off the main thread** or use pagination
3. **All network fetches MUST be cancellable** and not block UI updates

See [Performance Guidelines](docs/PERFORMANCE.md) for detailed patterns and examples.

## Linting & Formatting

Uses SwiftLint (`.swiftlint.yml`) and SwiftFormat (`.swiftformat`).

**Key limits:**
- Line length: 120 (warning), 200 (error)
- File length: 500 (warning), 1000 (error)
- Function body: 50 lines (warning), 100 (error)
- Type body: 300 lines (warning), 500 (error)
- Cyclomatic complexity: 15 (warning), 25 (error)

**Formatting rules:**
- 4-space indentation, no tabs
- LF line endings
- Trailing commas allowed
- `else` on same line as closing brace
- Spaces around operators and ranges
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

## Issue and feature ideas

I'll occasionally store human-generated plans/bugs/etc in `docs/plans/human` and `docs/bugs`. Look through these to find new work to do. Mark the documents as done in a way that you can easily find once they're completed.

## Git Workflow

**Do NOT use git worktrees.** All work should be done on the main branch or feature branches in the primary working directory.
