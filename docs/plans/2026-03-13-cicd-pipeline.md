# CI/CD Pipeline Plan: GitHub Actions + Claude Code Hooks

**Date:** 2026-03-13
**Scope:** Unified validation pipeline for CarrierWave (iOS) and CW Sweep (macOS), plus Claude Code quality enforcement

---

## Problem Statement

1. **No full app build validation in CI** — Current GitHub Actions only runs SwiftLint, SwiftFormat, and SPM-level unit tests (`swift test`). Neither the iOS app nor CWSweep is actually compiled in CI, so broken builds can merge.
2. **Claude Code submits failing code** — Cloud/web Claude Code sessions can't run Xcode, and the `.needs-quality-check` advisory file doesn't prevent merging broken code. We need Claude Code to produce properly formatted, linted code directly — not defer to a human cleanup step.
3. **macOS runner costs** — GitHub Actions macOS runners cost $0.08/min (10x Linux). Running full `xcodebuild` on every PR is expensive for a solo/small-team project.

## Architecture

```
PR Opened
    │
    ├──► GitHub Actions (Linux, cheap)
    │      └── Lint & Format (SwiftLint-static + SwiftFormat)
    │
    ├──► GitHub Actions (macOS, existing)
    │      └── Unit tests (CarrierWaveCoreTests, swift test)
    │
    └──► Claude Code Hooks (in-session)
           ├── Auto-format on every Swift edit (SwiftFormat)
           └── Lint check on every Swift edit (SwiftLint)

Push to main
    │
    └──► GitHub Actions (macOS)
           ├── CarrierWave iOS build (xcodebuild, simulator)
           ├── CWSweep macOS build (xcodebuild)
           └── Unit tests
           │
           ▼
    Build failure on main = release blocker
    (fix before tagging any release)
```

**Key tradeoff:** PRs are validated for lint, format, and SPM unit tests (cheap). Full app compilation runs only on pushes to `main`. A build failure on `main` blocks any release — you can't tag or ship until it's green.

---

## Phase 1: GitHub Actions — Build Validation on `main`

### 1A. Add iOS Build Job (main only)

```yaml
build-ios:
  name: Build iOS
  runs-on: macos-15
  if: github.ref == 'refs/heads/main'
  steps:
    - uses: actions/checkout@v4

    - name: Select Xcode
      run: sudo xcode-select -s /Applications/Xcode_16.2.app

    - name: Build CarrierWave for Simulator
      run: |
        xcodebuild build \
          -project CarrierWave.xcodeproj \
          -scheme CarrierWave \
          -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
          CODE_SIGN_IDENTITY="" \
          CODE_SIGNING_REQUIRED=NO \
          CODE_SIGNING_ALLOWED=NO \
          | tail -20
```

### 1B. Add CWSweep Build Job (main only)

```yaml
build-cwsweep:
  name: Build CWSweep
  runs-on: macos-15
  if: github.ref == 'refs/heads/main'
  steps:
    - uses: actions/checkout@v4

    - name: Select Xcode
      run: sudo xcode-select -s /Applications/Xcode_16.2.app

    - name: Generate CWSweep project
      run: |
        if command -v xcodegen &> /dev/null; then
          cd CWSweep && xcodegen generate
        fi

    - name: Build CWSweep for macOS
      run: |
        xcodebuild build \
          -project CWSweep/CWSweep.xcodeproj \
          -scheme CWSweep \
          -destination 'platform=macOS' \
          CODE_SIGN_IDENTITY="" \
          CODE_SIGNING_REQUIRED=NO \
          CODE_SIGNING_ALLOWED=NO \
          | tail -20
```

### 1C. Move Lint & Format to Linux Runner (all PRs + main)

SwiftLint-static and SwiftFormat both have Linux binaries. Moving lint from `macos-15` to `ubuntu-latest` cuts cost ~10x for this job:

```yaml
lint:
  name: Lint & Format
  runs-on: ubuntu-latest
  steps:
    - uses: actions/checkout@v4

    - name: Install SwiftLint
      run: |
        curl -sL https://github.com/realm/SwiftLint/releases/download/0.63.2/swiftlint_linux_amd64.zip \
          -o /tmp/swiftlint.zip
        unzip -o /tmp/swiftlint.zip -d /tmp/swiftlint_bin
        sudo cp /tmp/swiftlint_bin/swiftlint-static /usr/local/bin/swiftlint
        sudo chmod +x /usr/local/bin/swiftlint

    - name: Install SwiftFormat
      run: |
        curl -sL https://github.com/nicklockwood/SwiftFormat/releases/download/0.60.1/swiftformat_linux.zip \
          -o /tmp/swiftformat.zip
        unzip -o /tmp/swiftformat.zip -d /tmp/swiftformat_bin
        sudo cp /tmp/swiftformat_bin/swiftformat_linux /usr/local/bin/swiftformat
        sudo chmod +x /usr/local/bin/swiftformat

    - name: Check formatting
      run: swiftformat --lint .

    - name: Run SwiftLint
      run: swiftlint lint --strict --reporter github-actions-logging
```

**Note:** The static SwiftLint binary skips 4 SourceKit-dependent rules (`literal_expression_end_indentation`, `statement_position`, `vertical_whitespace_closing_braces`, `vertical_whitespace_opening_braces`). These are minor whitespace rules that SwiftFormat already handles.

### 1D. Release Gate Workflow

The build jobs on `main` act as a release gate. The release process (documented in `docs/RELEASING.md`) should verify the latest `main` build is green before tagging:

```yaml
release:
  name: Release
  needs: [build-ios, build-cwsweep, unit-tests]
  if: startsWith(github.ref, 'refs/tags/v')
  # ... archive, upload to App Store Connect, etc.
```

If `Build iOS` or `Build CWSweep` failed on a prior `main` push, the release workflow won't run until the build is fixed.

---

## Phase 2: Claude Code Quality Enforcement

### Key Insight: SwiftLint and SwiftFormat Run on Linux

**Verified:** Both tools have Linux x86_64 binaries that work in the Claude Code cloud environment:
- `swiftlint-static` (0.63.2) — fully static binary, no dependencies. Skips 4 SourceKit-dependent rules but catches all style/convention violations.
- `swiftformat_linux` (0.60.1) — works with the project's `.swiftformat` config.

This means we can **eliminate `.needs-quality-check` entirely** for lint/format. Claude Code can run the real tools on every edit.

### 2A. SessionStart Hook: Install Tools Automatically

Use a Claude Code `SessionStart` hook to download and install both tools when a session begins. This runs once per session, not on every edit.

**`.claude/hooks/setup-swift-tools.sh`:**
```bash
#!/bin/bash
# Install SwiftLint and SwiftFormat Linux binaries if not present
TOOLS_DIR="$HOME/.local/bin"
mkdir -p "$TOOLS_DIR"

if [ ! -f "$TOOLS_DIR/swiftlint" ]; then
    curl -sL https://github.com/realm/SwiftLint/releases/download/0.63.2/swiftlint_linux_amd64.zip \
        -o /tmp/swiftlint.zip
    unzip -o /tmp/swiftlint.zip -d /tmp/swiftlint_bin
    cp /tmp/swiftlint_bin/swiftlint-static "$TOOLS_DIR/swiftlint"
    chmod +x "$TOOLS_DIR/swiftlint"
    rm -rf /tmp/swiftlint.zip /tmp/swiftlint_bin
fi

if [ ! -f "$TOOLS_DIR/swiftformat" ]; then
    curl -sL https://github.com/nicklockwood/SwiftFormat/releases/download/0.60.1/swiftformat_linux.zip \
        -o /tmp/swiftformat.zip
    unzip -o /tmp/swiftformat.zip -d /tmp/swiftformat_bin
    cp /tmp/swiftformat_bin/swiftformat_linux "$TOOLS_DIR/swiftformat"
    chmod +x "$TOOLS_DIR/swiftformat"
    rm -rf /tmp/swiftformat.zip /tmp/swiftformat_bin
fi

# Inject context so Claude knows the tools are available
echo "SwiftLint and SwiftFormat are installed at $TOOLS_DIR."
echo "Run swiftformat on Swift files after editing. Run swiftlint to check for violations."
```

### 2B. PostToolUse Hook: Auto-Format After Every Swift Edit

Use a Claude Code `PostToolUse` hook on `Edit|Write` to auto-format every Swift file immediately after Claude edits it. This ensures formatting is always correct without relying on Claude's knowledge of SwiftFormat rules.

**`.claude/hooks/post-swift-edit.sh`:**
```bash
#!/bin/bash
INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

# Only process Swift files
[[ "$FILE_PATH" =~ \.swift$ ]] || exit 0

TOOLS_DIR="$HOME/.local/bin"

# Auto-format in place (fix, don't just lint)
if [ -x "$TOOLS_DIR/swiftformat" ]; then
    "$TOOLS_DIR/swiftformat" "$FILE_PATH" 2>/dev/null
fi

# Lint and report violations to stderr (Claude sees this as feedback)
if [ -x "$TOOLS_DIR/swiftlint" ]; then
    LINT_OUTPUT=$("$TOOLS_DIR/swiftlint" lint --strict --quiet "$FILE_PATH" 2>&1)
    if [ -n "$LINT_OUTPUT" ]; then
        echo "SwiftLint violations in $FILE_PATH:" >&2
        echo "$LINT_OUTPUT" >&2
        # Exit 2 blocks the action and sends feedback to Claude to fix
        exit 2
    fi
fi

exit 0
```

**How this works:**
1. Claude edits a `.swift` file via `Edit` or `Write` tool
2. Hook runs SwiftFormat on the file — **fixes formatting in place automatically**
3. Hook runs SwiftLint — if violations exist, **exit 2 blocks the action** and sends the violations back to Claude as feedback
4. Claude sees the lint errors and fixes them before proceeding

Claude never commits unformatted code because formatting happens automatically. Lint violations are caught inline and Claude is forced to address them.

### 2C. Claude Code Settings Configuration

**`.claude/settings.json`:**
```json
{
  "hooks": {
    "SessionStart": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "./.claude/hooks/setup-swift-tools.sh"
          }
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "Edit|Write",
        "hooks": [
          {
            "type": "command",
            "command": "./.claude/hooks/post-swift-edit.sh"
          }
        ]
      }
    ]
  }
}
```

This file is committed to the repo, so every Claude Code session (cloud or local) gets the hooks.

### 2D. Update CLAUDE.md: Remove `.needs-quality-check` Workflow

Replace the cloud/web environment section:

```markdown
> **Cloud/web environment (Claude Code app):** Xcode is not available.
> Skip all `xc` / `make` commands. Focus on code changes only.
>
> Claude Code hooks automatically run SwiftFormat and SwiftLint on every
> Swift file edit. Formatting is fixed in place; lint violations block the
> edit until resolved. No manual quality check step is needed.
>
> **What hooks CAN'T catch:** Compilation errors (missing imports, type
> mismatches, access control). GitHub Actions builds catch these on merge
> to main. Be careful with cross-file changes — if you rename a type or
> change a function signature, verify all call sites.
```

Delete `.needs-quality-check` and remove all references to it from CLAUDE.md.

---

## Phase 3: Validation Coverage Summary

| Problem | Caught By | When |
|---------|-----------|------|
| Formatting violations | **PostToolUse hook** (auto-fixed) | Immediately on edit |
| SwiftLint style violations | **PostToolUse hook** (blocks + feedback) | Immediately on edit |
| Lint violations (full) | **GitHub Actions** lint job | On PR + main |
| iOS compilation errors | **GitHub Actions** `Build iOS` job | On push to main |
| macOS compilation errors | **GitHub Actions** `Build CWSweep` job | On push to main |
| Unit test failures | **GitHub Actions** `Unit Tests` job | On PR + main |
| Performance regressions | **GitHub Actions** perf tests | Nightly |

**Worst case:** A PR merges with a compilation error. The `main` build goes red. You see it immediately, fix it before releasing. No broken build ever ships.

---

## Execution Order

| Step | What | Effort | Dependency |
|------|------|--------|------------|
| 1 | Create `.claude/hooks/` with setup + post-edit scripts | 30 min | None |
| 2 | Create `.claude/settings.json` with hook config | 10 min | Step 1 |
| 3 | Test hooks in a cloud Claude Code session | 15 min | Steps 1-2 |
| 4 | Update CLAUDE.md — remove `.needs-quality-check`, document hooks | 15 min | Step 3 |
| 5 | Delete `.needs-quality-check` file | 1 min | Step 4 |
| 6 | Add `Build iOS` + `Build CWSweep` jobs to ci.yml (main only) | 20 min | None |
| 7 | Move lint job to Linux runner with static binaries | 15 min | None |
| 8 | Update release process to require green main build | 10 min | Step 6 |

All steps can be done immediately — no external service setup required.

---

## Cost Estimate

| Job | Runner | Trigger | Per-Run Cost |
|-----|--------|---------|--------------|
| Lint & Format | `ubuntu-latest` | Every PR + main | ~$0.008 |
| Unit Tests | `macos-15` | Every PR + main | ~$0.24-0.40 |
| Build iOS | `macos-15` | **Main only** | ~$0.64-0.96 |
| Build CWSweep | `macos-15` | **Main only** | ~$0.40-0.64 |
| Claude Code hooks | In-session | Every edit | Free |

**Per PR:** ~$0.25-0.41 (lint + unit tests only)
**Per merge to main:** ~$1.30-2.00 (lint + tests + both builds)
**At ~20 merges/month:** ~$26-40/month total

Compared to building on every PR (~$26-40/month just for PR builds), this approach costs roughly half since most PRs iterate through multiple pushes before merging.

---

## What This Doesn't Solve

- **Compilation errors on PRs** — You won't know a PR breaks the build until it merges. For high-risk PRs (large refactors, cross-file renames), manually trigger the build workflow before merging.
- **Runtime bugs** — CI validates compilation and lint, not correctness. Unit tests help but don't cover everything.
- **Performance regressions** — The nightly perf tests catch these, but not before merge.
- **Code signing for distribution** — Out of scope. Future work: add a release workflow triggered by version tags.
- **Rust backend CI** — The activities server needs its own pipeline (GitHub Actions with Linux runner, standard `cargo test`).

## Future Enhancements

- **Manual PR build trigger:** Add `workflow_dispatch` or a `/build` comment trigger so you can opt-in to a full build on risky PRs without paying for it on every push.
- **CarrierWaveCore on Linux:** With a small `#if canImport(Accelerate)` guard, the core package could build via `swift build` on a Linux runner — catching compilation errors in shared code on every PR for ~$0.01.
- **Build caching:** Cache DerivedData and SPM packages to cut macOS build times.
