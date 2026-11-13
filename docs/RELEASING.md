# Releasing a New Version

## Overview

Releases follow this flow:

1. **Bump version** in `swift/Versions.xcconfig`, add the What's New entry and CHANGELOG heading, run `scripts/check-versions.sh`, commit
2. **Push to `main`** to get the code on GitHub
3. **Run `make release`** to create the git tag, push it, and notify Discord (it re-runs the version check first)
4. **Xcode Cloud** picks up the new tag, builds, archives, and uploads to TestFlight

## Where the version lives

**`swift/Versions.xcconfig` is the single source of truth for both Apple apps** (CAR-158):

| Variable | App | Feeds |
|---|---|---|
| `CARRIER_WAVE_IOS_MARKETING_VERSION` | Carrier Wave: Field (iOS app, watch, widgets, tests) | `MARKETING_VERSION` → `CFBundleShortVersionString` |
| `CARRIER_WAVE_IOS_BUILD_NUMBER` | same | `CURRENT_PROJECT_VERSION` → `CFBundleVersion` |
| `CW_SWEEP_MARKETING_VERSION` | CW Sweep (macOS) | `MARKETING_VERSION` |
| `CW_SWEEP_BUILD_NUMBER` | CW Sweep | `CURRENT_PROJECT_VERSION` |

`swift/ios/CarrierWave.xcodeproj` includes the file as its project-level xcconfig and sets
`MARKETING_VERSION = $(CARRIER_WAVE_IOS_MARKETING_VERSION)` / `CURRENT_PROJECT_VERSION = $(CARRIER_WAVE_IOS_BUILD_NUMBER)`
once, at project level, so every target inherits them. `swift/macos/project.yml` includes it via
xcodegen `configFiles` and maps the `CW_SWEEP_*` pair the same way. **Never type a version literal
into the pbxproj or `project.yml`** — Xcode's target inspector will happily do this for you; if it
happens, delete the literal so the xcconfig wins again. All in-app "About"/Settings displays and
telemetry read `CFBundleShortVersionString` from the bundle; nothing in Swift source hardcodes the
version. Android is versioned independently in `android/app/build.gradle.kts` (see the
`android-release` skill).

**`scripts/check-versions.sh`** enforces consistency and fails on any drift. For each platform it
requires strict equality between the xcconfig value, the newest `WhatsNewEntry.version` for that
platform in `WhatsNewCatalog+*.swift`, and the newest released `## [x.y.z]` (iOS) /
`## [CW Sweep x.y.z]` (macOS) heading in `CHANGELOG.md`; it also checks Android `versionName` against
the newest heading under `# Android`, and fails if a `MARKETING_VERSION`/`CURRENT_PROJECT_VERSION`
literal is hardcoded in the pbxproj or `project.yml`. Equality (not "CHANGELOG may be ahead") is
required because a release bump is a single commit that changes all three together; between
releases they already agree. It runs from the pre-commit hook (when a version-bearing file is
staged), from `scripts/release.sh`, and in the `Version Consistency` job of `.github/workflows/ci.yml`.

## Xcode Cloud Setup (one-time)

Configure a workflow in Xcode (**Product → Xcode Cloud → Manage Workflows**):

- **Start Condition:** New tag matching `v*` pattern
- **Build Action:** Archive (uses the `CarrierWave` scheme)
- **Post-Action:** TestFlight (Internal Testing) — auto-distributes to internal testers
- **Build Number:** the committed `CARRIER_WAVE_IOS_BUILD_NUMBER` in `swift/Versions.xcconfig` is the local/dev build number; `swift/ios/ci_scripts/ci_pre_xcodebuild.sh` overwrites it with Xcode Cloud's monotonic `$CI_BUILD_NUMBER` at build time so every TestFlight upload is unique

The existing `ci_scripts/ci_post_clone.sh` installs SwiftLint for the build.

## 1. Update version in code

The version is written in **one** place and mirrored by **two** release-notes artifacts that must
name the same version. Update all three in the same commit:

1. **Version** (`swift/Versions.xcconfig`):
   - iOS: `CARRIER_WAVE_IOS_MARKETING_VERSION` (e.g., `1.101.0`) and `CARRIER_WAVE_IOS_BUILD_NUMBER` (+1 per release)
   - macOS: `CW_SWEEP_MARKETING_VERSION` and `CW_SWEEP_BUILD_NUMBER` (+1 per release)
   - Nothing else needs editing for the build: the pbxproj, `project.yml`, and the Settings "About"
     rows all derive from this file. For CW Sweep, run `xcodegen generate` only if you also changed
     `project.yml`; the xcconfig is read at build time.

2. **Changelog** (`CHANGELOG.md`):
   - iOS: rename `[Unreleased]` to `[X.Y.Z] - YYYY-MM-DD` with the new version and current date, and add a new empty `[Unreleased]` section at the top for future changes
   - macOS: add a `## [CW Sweep X.Y.Z] - YYYY-MM-DD` heading with the Sweep notes

3. **What's New catalog** (`swift/packages/CarrierWaveData/Sources/CarrierWaveData/Utilities/WhatsNewCatalog+Recent.swift`):
   - Prepend a `WhatsNewEntry` whose `version` matches the new xcconfig value, with `platforms` covering which apps are shipping this version (`[.iOS]`, `[.macOS]`, or both)
   - Items use `WhatsNewItemKind.feature/.improvement/.fix`; keep titles short and detail to one sentence. The sheet ships bundled in the binary — text cannot be changed after release without another build.

Then run `scripts/check-versions.sh`. It must print `All version locations agree.`; the pre-commit
hook, `make release`, and CI all run the same script and will refuse drift.

## 2. Commit and push

Commit the version bump and push to `main`:

```bash
scripts/check-versions.sh
git add swift/Versions.xcconfig \
  CHANGELOG.md \
  swift/packages/CarrierWaveData/Sources/CarrierWaveData/Utilities/WhatsNewCatalog+Recent.swift
git commit -m "Bump version to X.Y.Z (build N)"
git push origin main
```

## 3. Tag and notify

```bash
make release VERSION=X.Y.Z
```

This will:
- Create an annotated git tag `vX.Y.Z` with the changelog as the tag message
- Push the tag to GitHub — **this triggers Xcode Cloud**
- Send a release notification to Discord (if `DISCORD_WEBHOOK_URL` is configured)

Monitor the build in Xcode (**Product → Xcode Cloud**) or App Store Connect.

### Discord notifications

To enable Discord release notifications, set the `DISCORD_WEBHOOK_URL` environment variable or add it to a `.env` file in the project root:

```bash
DISCORD_WEBHOOK_URL=https://discord.com/api/webhooks/...
```

## Local archive and upload (no Xcode Cloud)

The whole release can be produced and uploaded from a Mac shell with an App Store Connect
API key; nothing interactive in Xcode is needed.

**One-time setup.** In App Store Connect → Users and Access → Integrations → App Store Connect API,
generate a **Team Key** with the **Admin** role, or **App Manager** with *Access to Cloud Managed
Distribution Certificate* ticked. That checkbox only exists at creation time and cannot be added to
an existing key; without it `-exportArchive` fails with "Cloud signing permission error" because
this team uses cloud-managed distribution certificates and no `Apple Distribution` certificate lives
in the local keychain. Put the downloaded `AuthKey_<KEYID>.p8` in `~/.private_keys/` (mode 600) and
note the **Issuer ID** shown at the top of that page. Keep both out of the repo.

**Per release**, after the version bump commit and `scripts/release.sh` have run:

```bash
cd swift/ios
xcodebuild -project CarrierWave.xcodeproj -scheme CarrierWave \
  -destination 'generic/platform=iOS' \
  -archivePath "$HOME/Library/Developer/Xcode/Archives/$(date +%F)/CarrierWave.xcarchive" \
  archive -allowProvisioningUpdates

xcodebuild -exportArchive \
  -archivePath "$HOME/Library/Developer/Xcode/Archives/$(date +%F)/CarrierWave.xcarchive" \
  -exportOptionsPlist ExportOptions.plist -exportPath /tmp/CarrierWave-export \
  -allowProvisioningUpdates \
  -authenticationKeyPath "$HOME/.private_keys/AuthKey_$ASC_KEY_ID.p8" \
  -authenticationKeyID "$ASC_KEY_ID" -authenticationKeyIssuerID "$ASC_ISSUER_ID"
```

`ExportOptions.plist` already selects `app-store-connect` with `destination: upload`, so the second
command creates or refreshes the App Store provisioning profiles for the app, watch and widget
targets with the cloud certificate, signs, and uploads in one step. Success prints
`Upload succeeded` and `** EXPORT SUCCEEDED **`; the build then appears in App Store Connect →
TestFlight after Apple's processing. The committed `CARRIER_WAVE_IOS_BUILD_NUMBER` is what ships, so
bump it in `swift/Versions.xcconfig` for every upload (App Store Connect rejects a repeated build
number within one marketing version). If the `v*` tag also triggers Xcode Cloud, disable that
workflow or expect a second TestFlight build with Xcode Cloud's own build number.

## Changelog Conventions

**Maintain the changelog incrementally as you work.** Do not construct it from git history.

**File:** `CHANGELOG.md`

**Two version tracks.** The iOS/macOS apps (plus firmware and server) share the
version line at the top of the file. The **Android app has its own version
line** (0.1, 0.2, …) in the `# Android` section at the end of `CHANGELOG.md`.
Android-only changes go under the current Android version there; changes that
ship on both platforms are recorded on each track (tagged inline on the shared
website page — see below). When cutting an Android release, rename its
`[Unreleased]`-equivalent working entries to `[0.Y] - YYYY-MM-DD` alongside the
`versionCode`/`versionName` bump in `android/app/build.gradle.kts`.

**Website.** The public changelog at `website/changelog.html` mirrors both
tracks behind a platform toggle (`iOS · macOS` / `Android`). Add a matching
`version-block` to the correct `<div class="track">` when you publish, and keep
the platform toggle in sync. Editing the file publishes it — it is a static
page with no build step.

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
