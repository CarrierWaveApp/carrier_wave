# Carrier Wave

Monorepo for Carrier Wave amateur radio software: iOS app (Field), macOS companion (Sweep), shared Swift packages, Rust server backend, SDR recording server, and website.

> Read this file and linked docs for context. Only explore source files when actively implementing.

> Do not make any changes until you have 95% confidence in what you need to build. Ask me follow up questions until you reach that confidence.

## Project Architecture

Monorepo organized by language and platform.

```
carrier_wave/
├── swift/
│   ├── ios/                   # Carrier Wave: Field (SwiftUI/SwiftData)
│   ├── macos/                 # CW Sweep (macOS companion)
│   ├── packages/
│   │   ├── CarrierWaveCore/   # SPM: protocol logic, parsers, utilities, FT8 codec
│   │   └── CarrierWaveData/   # SPM: SwiftData models, cloud sync, shared services
│   ├── watch/                 # watchOS companion (target in iOS xcodeproj)
│   └── widgets/               # Widget extension (target in iOS xcodeproj)
├── pebble/
│   └── carrier-wave/          # Pebble Time 2 / Round 2 watchapp (C + PebbleKit JS)
├── website/                   # carrierwave.app — marketing site, Hugo manual, devlog
├── server/                    # Rust backend (activities API, aggregators, RBN proxy)
├── swl/                       # CW SWL — SDR recording server (Rust workspace)
├── docs/                      # Shared documentation
├── scripts/                   # Dev tooling scripts
└── Tools/                     # Standalone dev utilities
```

Each subdirectory has its own `CLAUDE.md` with component-specific conventions.

## File Discovery

- Start at [FILE_INDEX.md](FILE_INDEX.md) — thin root pointing to per-subproject indexes
- Load **exactly one** subproject `FILE_INDEX.md` per task (iOS app / iOS services / iOS views / macOS / watch / widgets / CarrierWaveCore / CarrierWaveData / server / swl / website)
- **FORBIDDEN:** loading the root index together with a child, scanning all source files, broad `Glob`/`Grep` across the repo, reading more than 5 files at once
- When adding/removing/renaming files, update the nearest `FILE_INDEX.md`
- If an index grows past ~600 lines, split it further and add a pointer row in the parent

## Quick Reference

| Area | Details |
|------|---------|
| Architecture | [docs/architecture.md](docs/architecture.md) |
| Setup | [docs/SETUP.md](docs/SETUP.md) |
| Design Language | [docs/design-language.md](docs/design-language.md) |
| UX North Star | [docs/ux-north-star.md](docs/ux-north-star.md) |
| Performance | [docs/PERFORMANCE.md](docs/PERFORMANCE.md) |
| Releasing | [docs/RELEASING.md](docs/RELEASING.md) |
| Investigation Template | [docs/investigation-template.md](docs/investigation-template.md) |
| Server API | [server/docs/api.md](server/docs/api.md) |
| SWL Configuration | [swl/docs/configuration.md](swl/docs/configuration.md) |

## Model Selection

Default **Sonnet** for coding tasks. **Opus** for: failed first attempts, 5+ file spans, architecture, security. **Haiku** for: search/grep, simple edits, worker subagents.

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

## Changelog

Maintain `CHANGELOG.md` incrementally using [Keep a Changelog](https://keepachangelog.com/). Update after completing features/fixes. Full conventions in [docs/RELEASING.md](docs/RELEASING.md).

## What's New Sheet

User-facing release notes shipped in-app. Source of truth: `WhatsNewCatalog.entries` in `swift/packages/CarrierWaveData/Sources/CarrierWaveData/Utilities/WhatsNewCatalog.swift`.

**App versions live in one file: `swift/Versions.xcconfig`** (`CARRIER_WAVE_IOS_*` for the iOS app/watch/widgets, `CW_SWEEP_*` for macOS). Both Xcode projects read it; never hardcode `MARKETING_VERSION`/`CURRENT_PROJECT_VERSION` in the pbxproj or `project.yml`. `scripts/check-versions.sh` (pre-commit, `make release`, and CI) fails if the xcconfig, the newest `WhatsNewEntry` for that platform, and the newest released `CHANGELOG.md` heading disagree. Details: [docs/RELEASING.md](docs/RELEASING.md).

**When bumping a version in `swift/Versions.xcconfig`**, prepend a new `WhatsNewEntry` to the top of `entries` (in `WhatsNewCatalog+Recent.swift`):

- `version` must match the new `CFBundleShortVersionString` exactly (e.g. `"0.9.0"`).
- `platforms` gates which apps see the entry — use `[.iOS]`, `[.macOS]`, or `[.iOS, .macOS]`.
- `items` use `WhatsNewItemKind` — `.feature` (New), `.improvement` (Improved), `.fix` (Fixed). Keep titles ≤ 40 chars; detail ≤ one sentence. Full notes go in `CHANGELOG.md` / App Store release notes / devlog.
- No network — copy ships with the binary. To change text after release, ship another build.
- Don't bump the version without an entry; `WhatsNewService` will show an empty sheet.

The sheet auto-presents on first launch after an update via `WhatsNewService` (per-platform `UserDefaults` last-seen key). Fresh installs are suppressed by `markFreshInstallIfNeeded()`. Tests in `Tests/CarrierWaveDataTests/WhatsNewTests.swift` cover the filter + lifecycle.

## Investigation Traces

Create `docs/investigations/YYYY-MM-DD-<desc>.md` when debugging non-trivial issues. Template: [docs/investigation-template.md](docs/investigation-template.md).

## Infrastructure

Server provisioning and deployment (Ansible, Terraform, deploy workflows) live in a separate private repository. Paths under `infra/` mentioned in component docs refer to that repository.

## Per-Developer Notes

Each developer has a gitignored `CLAUDE.local.md` with their own test device UDID and any machine-specific notes. Template: [CLAUDE.local.md.example](CLAUDE.local.md.example). Copy it to `CLAUDE.local.md` and fill in your values.

## Workflow Rules

When asked to commit and deploy, execute the full pipeline: build → fix any issues → deploy to device → commit → push. Don't stop at just committing.

When asked to implement changes, start coding immediately. Do not spend more than 2-3 minutes on exploration/planning before writing actual code. If a plan is needed, write it concisely and move to implementation in the same session.

## Git Workflow
