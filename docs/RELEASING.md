# Releasing a New Version

## 1. Update version in code

Update **all three** locations:

1. **Xcode project** (`CarrierWave.xcodeproj/project.pbxproj`):
   - `MARKETING_VERSION` - The user-facing version (e.g., "1.2.0")
   - `CURRENT_PROJECT_VERSION` - The build number (increment for each build)

2. **Settings view** (`CarrierWave/Views/Settings/SettingsView.swift`):
   - Update the hardcoded version string in the "About" section (~line 448)

3. **Changelog** (`CHANGELOG.md`):
   - Rename `[Unreleased]` to `[X.Y.Z] - YYYY-MM-DD` with the new version and current date
   - Add a new empty `[Unreleased]` section at the top for future changes

## 2. Commit and release

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

## Changelog Conventions

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
