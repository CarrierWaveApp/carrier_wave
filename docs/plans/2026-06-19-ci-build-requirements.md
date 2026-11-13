# CI & Build Requirements for the Rust-ification — Followup

**Date:** 2026-06-19
**Author:** handoff from the Phase-4 read-source/write-seam work (commits `79e2a095`, `c29c198f`)
**Companion:** [Rust-ification finish handoff](2026-06-18-rustification-finish-handoff.md)

## Why this doc

The Phase-4 cutover is now bottlenecked on **verification**, not on writing code. Package-level
logic (`cw-store` reads, parity probes, write-seam logic that lives in `CarrierWaveData`) is fully
testable on this machine in seconds. But everything that lives in the **iOS app target**
(`CwStoreMirror`, `QSOWriteSink`, `ServicePresenceWriteSink`, and every future read-cutover/consumer
change) **cannot be built or run locally** — the local toolchain hangs and the local test runners are
broken. We need CI to be the source of truth for the app target. This doc says exactly what works,
what doesn't, where the time goes, and what CI must provide.

## Status (2026-06-19) — REVERSED: no macOS in CI

The macOS-runner CI jobs proposed below (and briefly committed) were **removed**: macOS GitHub
runners are too expensive. `.github/workflows/ci.yml` now runs **only** `lint` and
`performance-audit` (both ubuntu). The Rust workspace's own `cw-core-rust.yml` (with its macos-15
`xcframework` + parity job) is left as-is.

**Decision:** the iOS app build, `CwFfi.xcframework`, and the `CarrierWaveCore` / `CarrierWaveData`
swift-test suites are verified **locally** instead of in CI. The full app build is done locally by
pushing through the `actool` hang (kill `actool` so link proceeds) rather than relying on a runner.

The rest of this doc (the ask, what works/breaks locally) is kept as the rationale and as the local
verification playbook — the "CI must own this" conclusion is superseded by the cost decision above.

## TL;DR — the ask

CI already lints and runs the two SPM package test suites. **It does not build or test the iOS app
target at all.** We need one new CI job:

> **Build the `CarrierWave` iOS app for an Apple-Silicon simulator and run the `CarrierWaveTests`
> bundle** (at least the cw-store seam tests: `CwStoreMirrorTests`, `CwStoreMirrorActorTests`,
> `QSOWriteSinkTests`, `QueryParityTests`), with `CwFfi.xcframework` built first and the build
> pinned to **arm64** simulator slices.

Without this, app-target changes (the bulk of remaining Phase 4–6 work) ship unverified.

## What works locally — fast, reliable, use it

| Gate | Command | Time (warm) | Notes |
|------|---------|-------------|-------|
| Rust workspace | `cd rust/cw-core && cargo build --workspace && cargo clippy --workspace -- -D warnings && cargo test --workspace` | **~15 s** | No `cargo fmt` (hand-formatted). 155+ tests. |
| CarrierWaveData package | `cd swift/packages/CarrierWaveData && swift test --filter <Suite>` | **~3–6 s** | Single-suite, `.build` warm. This is the verification path for all cw-store read/parity/write-seam *logic*. |
| Package incremental (1 file changed) | same | **~3 s** | |
| Package cold build (empty `.build`) | same | **minutes, not measured** | Dominated by vendored **GRDB + SQLCipher C compilation**; `.build` is ~1.8 GB warm. CI must cache `.build` / SourcePackages or eat this every run. |

Key facts:
- `swift test` does **not** rebuild the Rust lib — it links the **prebuilt** `libcw_ffi.a`
  (~109 MB, staged into `.build` by the xcframework script). If that staticlib/xcframework is
  absent, the package fails to link.
- Tests must use a **minimal per-test schema** (`Schema([Model.self])`). The full `CarrierWaveSchema`
  will not load in-memory in this environment (`loadIssueModelContainer`).
- 8 RustStore count/parity tests are green today (`QSOReadSource`, `LoggingSessionReadSource`,
  `ServicePresenceReadSource`, `CountReadSource`, `*ParityProbe`, `StoreCountParity`).

## What's broken / hangs locally — do NOT rely on these

### 1. Full iOS app build hangs deterministically in `actool`
A full `xcodebuild -scheme CarrierWave ... build` reproducibly **hangs in the asset-catalog
compiler** (`actool`) — first on the **Watch** target's `Assets.xcassets`, then on the **iOS**
target's. Symptoms: `xcodebuild` at **0% CPU, STAT S for 30+ minutes**, a dormant `SWBBuildService`
child, zombie `ibtoold` processes, zero filesystem activity, no `BUILD SUCCEEDED`. Killing
`actool` (`pkill -9 -f actool`) lets compilation/link proceed.

This is an **Xcode/CoreSimulator environment fault, not a code fault.** It cost ~45 min once before
being recognized.

**Consequence:** you cannot get a clean local `BUILD SUCCEEDED` for the app. The most you can verify
locally is that the **Swift compile completes** — confirm the build reaches the **`Ld` (link) phase**
with zero `error:` lines from `swiftc`. (Grep the build log for `SwiftCompile ... in target
'CarrierWave'` present, `error:` absent, `Ld ...CarrierWave.debug.dylib` present.) In the run that
proved the Phase-4 work compiles: **2,495 `SwiftCompile` invocations, 0 Swift errors, reached `Ld`.**

### 2. Universal simulator build fails at link (architecture)
Building for `generic/platform=iOS Simulator` links a **universal (arm64 + x86_64)** binary. The
vendored `CwFfi.xcframework` ships only **`ios-arm64`, `ios-arm64-simulator`, `macos-arm64_x86_64`** —
**no x86_64 simulator slice.** So the x86_64 link fails:

```
ld: warning: ignoring file '...libcw_ffi.a(...)': found architecture 'arm64', required architecture 'x86_64'
Undefined symbols: _uniffi_cw_ffi_fn_method_fieldstore_upsert_qso, ... (all uniffi_cw_ffi_* from CarrierWaveCwFfi.o)
ld: symbol(s) not found for architecture x86_64
```

**Fix options (CI must pick one):**
- Build **arm64-only** (`ARCHS=arm64 ONLY_ACTIVE_ARCH=YES`, Apple-Silicon runner, arm64 simulator). Simplest.
- OR add an **x86_64 simulator slice** to `build-xcframework.sh` if any Intel runner / universal build is required.

### 3. Local test runners are broken (pre-existing, per the 2026-06-18 handoff)
- **Device** runner fails whole classes with `SwiftDataError.loadIssueModelContainer` + "Lost pending
  connection to the test runner."
- **Simulator** runner intermittently refuses to launch the host app (`RequestDenied` from
  `SBMainWorkspace`); the app launches fine via `simctl` standalone.
- `killall com.apple.CoreSimulator.CoreSimulatorService` + a fresh sim *sometimes* yields a clean run.

This is the other half of why app-target tests (`CarrierWaveTests`) can't be trusted locally and must
run on CI.

## Current CI state (`.github/workflows/`)

| Workflow / job | Runner | What it does | Gap |
|----------------|--------|--------------|-----|
| `ci.yml` → `lint` | ubuntu | SwiftFormat `--lint` + SwiftLint `--strict` | — |
| `ci.yml` → `test-core` | macos-15 | `swift test` CarrierWaveCore | **Does not build `CwFfi.xcframework` first** — verify this still passes now that Core/Data depend on cw-ffi |
| `ci.yml` → `test-data` | macos-15 | `swift test` CarrierWaveData | **Same xcframework concern** — this is the suite that exercises the cw-store read/parity code; if the staticlib isn't staged it can't link |
| `ci.yml` → `performance-audit` | ubuntu | `scripts/performance-audit.sh` on changed Swift | — |
| `cw-core-rust.yml` → `test` | ubuntu | cargo build/clippy/test `--workspace` | — |
| `cw-core-rust.yml` → `xcframework` | macos-15 | runs `build-xcframework.sh`, runs Swift **parity** gates (QueryAnalyzer, Maidenhead), uploads xcframework artifact | Builds the xcframework but **`ci.yml`'s swift jobs don't consume it** |
| — | — | **iOS app target build** | **MISSING ENTIRELY** |
| — | — | **`CarrierWaveTests` (app-target unit tests)** | **MISSING ENTIRELY** |

## What we need CI to provide

### A. (Required) App-target build + seam tests
New job, **macos-15 (Apple Silicon), arm64 simulator**:
1. Build `CwFfi.xcframework` first: `rust/cw-core/scripts/build-xcframework.sh` (it also regenerates
   `CwFfi+Generated.swift`). This is **mandatory before any swift build** that touches
   `CarrierWaveCwFfi` — the xcframework is **gitignored**.
2. `xcodebuild -project swift/ios/CarrierWave.xcodeproj -scheme CarrierWave -destination 'platform=iOS Simulator,name=<arm64 sim>,arch=arm64' ARCHS=arm64 ONLY_ACTIVE_ARCH=YES build CODE_SIGNING_ALLOWED=NO`
3. Run the cw-store seam tests via the existing Makefile pattern (or `-only-testing:`):
   `CwStoreMirrorTests`, `CwStoreMirrorActorTests`, `QSOWriteSinkTests`, `QueryParityTests`
   (and, once added, the ServicePresence write-seam + future read-cutover tests).

**Acceptance gate:** `** BUILD SUCCEEDED **` + those test suites green. This is the gate the local
machine cannot produce.

### B. (Required) Make the existing `test-core` / `test-data` jobs build the xcframework first
Add a `build-xcframework.sh` step (or download the `cw-core-rust.yml` artifact) before
`swift test`, so the package link against `libcw_ffi.a` is guaranteed. Confirm these two jobs are
actually green today — they may have silently broken when Core/Data took the cw-ffi dependency.

### C. (Nice to have) Performance smoke on real data volumes
`make test-performance-quick` (50k QSOs, ~1–2 min) on the same runner, to keep the
"QSO count must never affect main-thread responsiveness" invariant honest as writes move to cw-store.

## Open questions for whoever owns CI
1. Is `actool` hanging **only** on this developer machine, or does it reproduce on macos-15 runners?
   (If runners are clean, the app build "just works" there and item A is straightforward. If not,
   we need the `pkill actool` workaround or to investigate the asset catalogs.)
2. Are `test-core` / `test-data` currently passing on CI **with** the cw-ffi dependency, or have they
   been red/skipped? (Determines whether B is a fix or just hardening.)
3. Do we ever need an **x86_64 simulator** slice (Intel runners), or is Apple-Silicon-only acceptable
   for the foreseeable future? (Determines whether `build-xcframework.sh` needs a 4th slice.)
4. Cold `swift` build time on a fresh runner is unmeasured but minutes (GRDB + SQLCipher). Confirm
   `.build` / SourcePackages caching is wired so every PR isn't paying the SQLCipher C compile.

## One-line summary
Local = great for Rust + SPM-package logic (`cargo`, `swift test`, seconds). Local = useless for the
iOS app (actool hang + broken runners + arm64-only FFI). **CI must own the app-target build + seam
tests on an Apple-Silicon arm64 simulator, with the xcframework built first.**
