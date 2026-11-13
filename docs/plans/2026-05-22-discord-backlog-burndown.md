# Discord Backlog Burndown — 2026-05-22

Burn down the unprioritized Discord-synced `---` items at the top of the Linear backlog (CAR-261 down through CAR-231 band), plus stragglers in the same vintage that look stale. Order picks the cheapest verifications first, then small fresh code, then larger features.

## Workflow (apply to each item)

1. **Pull current state** — `linear issue view CAR-XXX --no-comments`. If the comments thread says "shipped in <hash>" or similar, check `git log --all --oneline | grep <hash>` to confirm.
2. **Decide path:**
   - **Stale → close.** If the fix is already on `main` and tagged into a release, just close the Linear issue with a short pointer to the commit/version. No code work.
   - **Reproducible → fix.** Read the relevant code path with `FILE_INDEX.md` first (load exactly one subproject index per the project CLAUDE.md). Make the change.
   - **Needs info → comment + leave open.** If repro detail is missing and we can't decide a fix, leave a Linear comment asking for what's needed and move to the next item. Don't close.
3. **Quality gate (for code changes):** `xc build` from `/Users/jsvana/projects/carrier_wave/swift/ios`. SwiftFormat/SwiftLint run via hooks on every edit, so only the build step needs explicit invocation. Pre-existing baseline lint violations in `LoggingSessionManager.swift` / `RemoteSweep*.swift` are accepted — only block on new violations introduced by the change.
4. **Deploy to theseus** (`xc deploy`) when the change is user-visible. Include "What to test" notes when reporting back.
5. **Commit + push.** One commit per Linear issue. Subject line: `<type>(<scope>): <summary> (CAR-XXX)`. Body explains *why*, not just *what*. Co-author trailer as standard.
6. **Update Linear:**
   - `linear issue update CAR-XXX -s "Done"`
   - `linear issue comment add CAR-XXX -b "<one-paragraph resolution: commit hash, scope of fix, anything skipped and why>"`
7. **Update this plan** — flip the row in the table below to `✓`, paste the commit hash in the Resolution column. If you discovered new follow-up issues, append them to the **Discovered follow-ups** section at the bottom.

Don't bundle multiple Linear issues into one commit unless they are *truly* the same fix (e.g., one underlying bug surfacing as two reports). Separate commits keep `linear issue comment add` accurate and let us revert one without disturbing the others.

## Burndown order

| # | ID | Title | Sizing | Status | Resolution |
|---|----|-------|--------|--------|------------|
| 1 | CAR-234 | Syncing in loop, phone got incredibly hot | verify | ✓ | Duplicate of CAR-244, fix shipped in v1.84.0 (`5cdfdcd3`). Closed with explanation. |
| 2 | CAR-232 | Sync QSO count, not matching | split | ✓ | Not subsumed. Split into CAR-262 (status bar dedup), CAR-263 (iOS→Sweep propagation), CAR-264 (fresh install restore — Urgent). Original closed. |
| 3 | CAR-243 | QRZ Comments | close | ✓ | Already shipped (`948f6ae4`, v1.91.0). Closed with pointer. |
| 4 | CAR-261 | 6m spotting/hunting | close | ✓ | Already on main (`54e25332`, 2026-05-20). Will ship next release. Closed with pointer. |
| 5 | CAR-249 | Watch app doesn't like spots | close | ✓ | Fix shipped `fb2e44bd` (2026-05-04, same day as report), in v1.87.0. Duplicate Identifiable id crash. Closed with pointer. |
| 6 | CAR-239 | Power Consumption optimization | close | ✓ | Battery-drain root cause (WCSession reactivation loop) shipped in v1.84.2 (`b722bc29`, `ba1ae707`). Closed with pointer. |
| 7 | CAR-231 | CW Sweep settings menu navigation bug | close | ✓ | Fix shipped `64edd3fa` in v1.83.0 — explicit "CAR-231: use minHeight for settings window" trailer. Closed. |
| 8 | CAR-260 | My Grid Matches the POTA/SOTA Entity | close | ✓ | Duplicate of CAR-255. Shipped `d2065bd3` in v1.89.0 — `resolveSessionGrid` priority-order helper. Closed. |
| 9 | CAR-257 | WWFF export | close | ✓ | Already a first-class program with session ADIF export (`fca2e50d` → `a65d26a7` in v1.91.0). Closed. |
| 10 | CAR-259 | Real Time Location on Map | close | ✓ | "My location" button + `LocationSessionService` continuous tracking. Most recent piece `198456cf` in v1.91.0. Closed. |

Items deliberately skipped:
- **CAR-242 / CAR-241 / CAR-240** — Bridge sub-items, assigned to JK.
- **CAR-237 / CAR-236 / CAR-235** — Infra (Hetzner, contests server, website migration). Different work mode, batch separately.
- **CAR-238 — "Integrate contests into sweep"** — large unscoped feature. Needs a design pass before implementation.
- **CAR-233 — "My"** — title is incomplete and there's no detail. Comment asking the reporter for context, then leave for triage.

## Stop conditions

Pause burndown and surface to the user when any of these happen:

- A "verify" item turns out to **not** be subsumed by the candidate commit and needs real fix work — re-size and re-plan.
- A "small" item turns out to need cross-package changes (e.g., changes in `CarrierWaveCore` + `CarrierWaveData` + iOS app + server). Bring it back for re-sizing.
- A fix lands but on-device verification fails. Don't keep stacking fixes on top — get user confirmation before continuing.
- An item is missing repro information we can't infer from code. Comment on the issue asking, then skip to next.
- A change requires bumping `MARKETING_VERSION` or other release-class actions. Surface for explicit go-ahead.

## Discovered follow-ups

_New issues found while burning down — file in Linear before closing this plan._

- **CAR-262** — CW Sweep status bar QSO count shows raw/undeduplicated total. (split from CAR-232)
- **CAR-263** — iOS-logged POTA hunting QSO not propagating to Sweep via CloudKit. Needs Kyle to confirm Sweep + iOS versions before investigation. (split from CAR-232)
- **CAR-264** — **Urgent.** CW Sweep fresh install / wipe does not restore logbook from CloudKit. Defeats implicit-backup property of sync. (split from CAR-232) — Worth bumping to the top of the next planning pass; this is more severe than anything else in the Discord queue.

## Extended pass (Discord backlog tail)

After the initial 10-row burndown completed clean, a wider scan of the `---` priority backlog (CAR-229 down to CAR-171) turned up another 15 items needing the same treatment. All processed in one batch following the same workflow.

| Bucket | Count | IDs | Resolution |
|--------|-------|-----|------------|
| 🟢 Confirmed shipped | 9 | CAR-229, CAR-222, CAR-221, CAR-220, CAR-179, CAR-176, CAR-212, CAR-223, CAR-198 | Closed with commit/release pointer |
| 🟡 Likely shipped — verified | 3 | CAR-227, CAR-171, CAR-180+CAR-196 | Closed with "rewritten / fixed; retest on current" |
| 🟣 Discussion prompts | 2 | CAR-218, CAR-174 | Closed with "Discord is the right home, file specific asks as their own tickets" |
| 🔄 Reopened on review | 1 | CAR-215 | Initially closed as discussion; on reread it carries a concrete feature spec (proximity/points leaderboard). Whether to build it is a product call — leaving in backlog for that decision. |

Skipped (intentional):
- CAR-242/241/240 — Bridge subitems (JK assignee)
- CAR-238 — Integrate contests into sweep (large, needs design pass)
- CAR-237/236/235 — Infra batch (Hetzner / contests server / website migration)
- CAR-233 — "My" (incomplete title, no body)

## Real-work queue after the audit

After the audit closed 9 + 3 + 2 = 14 items in the extended pass, the *initial* real-work queue was seven items. Then within the same session two more got verified-and-closed (CAR-178, CAR-214 — both subsumed by `8917180b` "prevent pending uploads for unconfigured sync services" in v1.71.0) and two were shipped (CAR-197, CAR-175 — CAR-175 then reverted on user feedback that the existing `qsoCountChip` was sufficient).

### Code that landed today

| Commit | Issue | Description |
|--------|-------|-------------|
| `d82b6fa0` | CAR-258 | OP: prefix backfill via BatchedRewrite — strips legacy `OP: <nickname>` segments from non-user-authored notes |
| `0a1b4952` | CAR-197 | RST Sent → RST Rcvd cursor auto-advance, mode-aware (3-digit CW/digital, 2-digit phone) |
| ~~`8f66837c`~~ → `1b815d9e` | CAR-175 | Activation progress banner — shipped then reverted; existing `qsoCountChip` is sufficient. CAR-175 returned to Backlog. |

### Open queue going into next session

| ID | Priority | State | Notes |
|----|----------|-------|-------|
| ~~CAR-264~~ | ✓ Done | — | Fixed `763ad0ba`. New `CloudSyncJournalEngine.resetForLocalWipe()` actor method drops the persisted CKSyncEngine state + `cloudSyncDeviceId` + sequence + snapshot throttle and restarts the engine; both apps' "Clear All QSOs" paths now invoke it after the local delete. Bootstrap fires the same way a fresh install does. Wants on-device verification before the next release. |
| ~~CAR-262~~ | ✓ Done | — | Fixed `dbb662d2` — `StatusBarView.loadCounts` now dedups by `QSO.deduplicationKey` + `QSOMode.isMetadata`. Surfaced (and required fixing) commit `87cf50ee` to unblock CW Sweep's build after `aa139858` shipped without xcodegen regen and with Swift 6 strict-concurrency violations in `MultipeerTransportListener`. |
| CAR-263 | 🟡 — | Backlog | iOS→Sweep CloudKit propagation lag. **Blocked: needs Kyle to confirm Sweep + iOS versions** before investigation. |
| CAR-175 | 🟡 — | Backlog | Reopened. Only worth pursuing if redesigning the existing `qsoCountChip` (more prominent, out of the scrolling row) — *not* by adding a separate banner. |
| CAR-215 | 🟢 — | Backlog | "Top Competition" — proximity / points leaderboard. **Needs a product decision before any code work.** |

Plus the **pre-existing prioritized backlog** untouched today, which still needs attention:

- ~~CAR-191~~ ✓ Done — already shipped in `105a59fa` (CW Sweep 0.12.0). Closed with pointer.
- CAR-166 (Postgres backups off-site)
- CAR-145 (vault-encrypt ntfy password) — sensitive (needs credential rotation)
- ~~CAR-144~~ ✓ Done — fixed `a51d256b` (`subtle::ConstantTimeEq` swap). Waiting for next `server-v*` tag.
- ~~CAR-143~~ ✓ Done — fixed `febbe800` (`tower-governor` rate limit + CORS allowlist + 1 MiB body cap + RegisterRequest length validation). Waiting for next `server-v*` tag.
- CAR-141 (NSAllowsArbitraryLoads → domain-specific ATS)

Two server pieces (CAR-143 + CAR-144) sit on main waiting for the next server release tag — recommended to batch them. CAR-141 is the remaining iOS-only audit item. CAR-166 + CAR-145 remain as ops work (CAR-145 needs you to rotate the ntfy credential before vault-encrypt).

## Summary

Burndown complete on 2026-05-22. **24 of 25 rows resolved** (CAR-215 reopened on review). Zero new code written on the audit. (The only code from this session was CAR-258's `OPPrefixBackfillService`, written before the audit started.)

Linear backlog hygiene was the actual problem — every single Discord-synced item in this band was either shipped weeks/months ago, an exact duplicate of an already-closed issue, a community-discussion prompt with no actionable spec, or (in CAR-232's case) a stale report that hid three real bugs underneath.

Outcomes:

- **23 closures** with commit/release pointers or "this isn't a ticket" rationale.
- **1 reopen on review** (CAR-215 — premature dismissal of a real feature request).
- **1 split** (CAR-232) into three focused issues, one **Urgent**.
- **3 net new tracked issues:** CAR-262, CAR-263, CAR-264.

Lesson worth capturing: Discord-synced issues land in Linear with `priority = ---` and stay there even after the underlying fix ships. A periodic backlog audit (grep commit log for `CAR-` prefixes, cross-reference open issues) would close the loop automatically. **Worth filing as its own automation ticket** — at this rate it's collecting ~20 stale tickets every couple of months.

## Next session — fresh Claude handoff

If you're a fresh Claude reading this for the first time: this whole document is the state. Read it top to bottom before acting. The summary:

**Today's session cleared 24 stale Discord-synced Linear tickets** (most were already shipped weeks/months ago — Linear hygiene was the bottleneck) and **shipped 2 small features** (CAR-258 OP: prefix backfill, CAR-197 RST auto-advance). One feature shipped and was reverted within the session (CAR-175 banner — redundant with existing chip). The open queue is in the table above.

### Recommended pickup order

1. **CAR-262** — *small, scoped, in CW Sweep.* Status bar QSO count needs to apply the same dedup as the Sync Diagnostic Report (CloudKit mirrors + `QSOMode.isMetadata`). Single-query fix probably. Read `swift/macos/CLAUDE.md` for Sweep conventions, then `Views/Workspace/` for where the status bar lives. Build with `xcodebuild`, not `xc` (Sweep is macOS).
2. **CAR-191** — *single-file iOS Sweep bug.* "WORKED" status misleading for unworked calls. Pull the issue, read the spotted-call status logic in Sweep, fix.
3. **Security/infra cluster (CAR-141 + CAR-143 + CAR-144 + CAR-145)** — *server-side, batchable as one PR.* All in `server/` (Rust). Constant-time token comparison, rate limiting, CORS, vault-encrypted ntfy password, ATS exceptions. The user has `infra/ansible/` for the secret rotation; check `CLAUDE.local.md` for vault password instructions.
4. **CAR-264** — *Urgent but heavy.* Sweep fresh install / wipe doesn't restore from CloudKit. Multi-day investigation. **Only pick this up in a dedicated session with the user, not as filler.** Will likely require `CKSyncEngine` instrumentation, schema-version comparison, and apply-path instrumentation. Defeats the implicit-backup property of cloud sync, so it's the most user-impactful unresolved bug.
5. **CAR-263** — *blocked.* Wait for Kyle to post the Sweep + iOS versions before touching this. If unblocked, the path is similar to CAR-264.
6. **CAR-175 / CAR-215** — *not next-pickup material.* Both need product decisions before code:
   - CAR-175: revisit only if redesigning the existing `qsoCountChip` to be more prominent; do not add a separate banner.
   - CAR-215: leaderboard feature, "would this be fun or annoying" — user needs to decide whether to build before any code.

### Workflow established this session

This worked well today and is worth following:

1. **Verify before fixing.** For any issue mentioning a bug, *first* `git -C <repo> log --oneline --grep="CAR-XXX\b"` and `git log --oneline --grep="<keyword from title>"`. If a commit references the issue, it's almost certainly already shipped — just close with a pointer. Today's rate was ~80% already-shipped. Don't write new code until you've ruled this out.
2. **One commit per Linear issue.** Format: `<type>(<scope>): <summary> (CAR-XXX)`. Co-author trailer.
3. **Build + deploy before claiming done.** `~/.claude/skills/xcode-build/scripts/xc build` then `xc deploy` from `/Users/jsvana/projects/carrier_wave/swift/ios`. Pre-existing baseline lint violations in `LoggingSessionManager.swift` / `RemoteSweep*.swift` / `LiquidGlass*.swift` are accepted; only block on *new* violations.
4. **Update the CHANGELOG.md `[Unreleased]` section** for every user-visible change. Format: `**iOS Field — <one-line summary> (CAR-XXX).** <Two-three-sentence body that captures the why.**` Match the existing entries' tone.
5. **Update Linear when done:** `linear issue update CAR-XXX -s "Done"` and `linear issue comment add CAR-XXX -b "..."` with the commit hash and a short resolution paragraph.
6. **Push after each commit** unless explicitly told otherwise. Don't accumulate local commits — the iOS release pipeline picks up from origin.

### Things to know that aren't obvious from the code

- **Linear CLI gotchas.** `linear issue list` only shows *my* issues. Use `linear issue query --team CAR` for everything. The `--no-pager` flag is rejected by `update` and `comment`; only `query`/`view`/`list` accept it.
- **xc skill working dir.** `xc` auto-detects `.xcodeproj` in cwd, so `cd /Users/jsvana/projects/carrier_wave/swift/ios` first or pass absolute path; the root has no `.xcodeproj`.
- **Build skill differs for Sweep.** Sweep is in `swift/macos/`, uses `xcodebuild` directly (not `xc`), and uses xcodegen (`xcodegen generate` after adding files to `project.yml`). See `swift/macos/CLAUDE.md`. The `cw-sweep-build` skill exists for this.
- **iOS app target is `com.jsvana.FullDuplex`**, not `com.jsvana.CarrierWave` (the app was named "Full Duplex" originally — bundle id wasn't migrated).
- **`notesUserAuthored` semantics.** Default `false`. Set to `true` only at user-edit sites. Anything from sync/download/import is `false`. Don't write code that assumes `false ⇒ "data is bad"` — older pre-flag QSOs are also `false` because the field didn't exist yet.
- **Default actor isolation is `MainActor`.** All non-UI types need `nonisolated` explicitly. See `feedback_default_actor_isolation.md`.

### Memory entries worth knowing about

The memory index is at `~/.claude/projects/-Users-jsvana-projects-carrier-wave/memory/MEMORY.md`. Several entries relevant to anything you might pick up:

- `feedback_redundant_ui.md` — the lesson from CAR-175's revert; check existing surfaces before adding new ones.
- `feedback_ios_logging.md` — never use `print`/`os_log`/`Logger`/`NSLog` from app code; route through `RadioService.shared.addLog` or a domain log surface.
- `feedback_default_actor_isolation.md` — Swift 6 strict, non-UI types need `nonisolated`.
- `feedback_swiftdata_gotchas.md` — `@State + @Model` re-fetch identity, ViewThatFits threading, etc.
- `feedback_recursive_views.md` — recursive SwiftUI views hang the compiler; AnyView at recursion point.
- `feedback_dual_ft8_views.md` — FT8 layout lives in TWO files: `FT8SessionView` + `ActivityLogFT8View`; edit both.

### Single command to bring a fresh Claude up to speed

After `claude` starts in the repo root, this prompt is enough:

> Read `docs/plans/2026-05-22-discord-backlog-burndown.md` and follow the "Next session — fresh Claude handoff" section. Pick up at the top of the recommended pickup order unless I tell you otherwise.

## References

- Project CLAUDE.md → Issue Tracking, Workflow Rules, Git Workflow
- `swift/ios/CLAUDE.md` — iOS-specific conventions (experimental features, logging rule, what's-new sheet)
- `swift/macos/CLAUDE.md` — CW Sweep conventions (xcodegen, distribution, Sparkle)
- `swift/ios/FILE_INDEX.md` and `swift/ios/CarrierWave/Services/FILE_INDEX.md` — discover relevant code per task
- Commits from today: `d82b6fa0` (CAR-258), `0a1b4952` (CAR-197), `1b815d9e` (CAR-175 revert)
- Reference commits from earlier work that came up in audits: `5cdfdcd3` (CAR-244), `14e357c5` (CAR-245), `1571ff56` (CAR-246), `64edd3fa` (Kyle's UX bundle), `8917180b` (unconfigured-sync gate), `0db16b86` (CAR-243 cutoff).
