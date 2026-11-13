---
title: "Radio Macros"
description: "Reusable CAT routines for your rig — tune-and-set-mode, voice memory triggers, RIT/XIT, CW templates"
weight: 11
showToc: true
---

Radio macros are reusable CAT routines that let you script your rig with a handful of taps. A macro is a sequence of typed steps — set frequency, set mode, vendor command, CW send, raw bytes, key the PTT — that runs against the connected radio. Macros are gated behind the **Radio CAT Control** experiment and the macro feature toggle inside it.

## Enabling Macros

1. Open **Settings → Experiments**.
2. Enable **Radio CAT Control**.
3. Open **Radio CAT Control → Macros**.

On CW Sweep, the same toggle lives under **Settings → Macros**; runs open in their own window so you can have several in flight at once.

## The Library

`MacrosLibraryView` has three tabs:

- **Mine** — macros you've authored or installed locally. Swipe to delete (the row tombstones rather than hard-deletes so iCloud sync survives) or duplicate.
- **Browse** — the community catalog served by the activities server. Search and filter by radio family or "transmits"; an Install button on each card grabs the macro into your library. The catalog is also published on the web at [carrierwave.app/manual/macros](/macros/) with a one-tap `cwmacro://` deep-link button per macro.
- **Updates** — installed macros that have a newer revision in the catalog. Review the diff, then Update, Keep My Version, or open the macro's web page.

## Building a Macro

`MacroEditorView` splits across four sections:

- **Header** — name, SF Symbol icon, tags, optional description. Saved-icon and tag chips persist across edits.
- **Capabilities** — five toggles (`transmits`, `requires-PTT`, `changes-frequency`, `changes-mode`, `sends-raw-bytes`). Toggling a capability off offers to remove conflicting steps.
- **Args** — typed parameters the macro asks for at run time. Frequency args require min/max bounds; the verifier blocks Save without them.
- **Steps** — eleven step kinds grouped by intent. TX-related kinds show a safety chevron. Reorder by drag, swipe to delete.

A `MacroVerifierIssuesBanner` lives in the safe-area below the form. Any **error**-severity issue blocks Save; **warning**-severity issues are advisory.

### Step Kinds

| Kind | Use |
|------|-----|
| `setFrequency` | Tune VFO-A (or VFO-B) to a frequency. Unit-aware editor (Hz/kHz/MHz) with common-band quick picks. |
| `setMode` | Set operating mode (CW / SSB / FM / FT8 / …). |
| `setPTT` | Key or unkey the PTT. Cooperative cancellation re-releases the PTT on macro cancel. |
| `cwSend` | Send CW with template substitution. Live preview against `MacroContext.preview` shows what tokens like `{{call}}` resolve to. |
| `vendorCommand` | Pick a named command from the vendor catalog (Yaesu, Kenwood/Elecraft, CI-V Icom) and fill its args. |
| `rawBytes` | The danger surface — write hex bytes directly to the radio. A permanent red banner and live hex validation gate this kind. Acceptance is per-macro and re-prompted after edits. |
| `wait` | Sleep for a fixed interval before the next step. |
| `setRIT` / `setXIT` | RIT/XIT offset in Hz with on/off toggle. |
| `setSplit` | Enable/disable split operation. |
| `setPower` | Adjust output power. |

## Running a Macro

Tap a macro in the library → **Run**. `MacroRunSheetView` runs a pre-flight check:

- **Allowed** — the macro runs immediately, with a live executor log.
- **Confirmation** — an orange banner explains why (transmits, raw bytes, out-of-band-plan for your region, etc.) before you tap Run.
- **Refused** — a red banner explains why; the gate refuses to run (e.g., transmit disabled globally, or post-substitution frequency lands in a no-TX segment).

The safety gate runs `verifier → protocol match → post-substitution band-plan → TX policy` in that order. The band-plan check is **region-aware** — your IARU region (R1/R2/R3) is read from your callsign profile on iOS and from the `userIARURegionOverride` UserDefaults key on macOS (default R2).

## Sharing & Installing

Macros are `.cwmacro` documents (JSON with a typed step list). You can:

- **Open `.cwmacro` files** from AirDrop / Files / Finder / Mail. The `MacroImportSheet` runs the same safety gate as in-app authoring and shows provenance — files from outside the registry are highlighted, raw-bytes installs require an explicit "Trust raw bytes?" confirmation.
- **Install from the catalog** in the Browse tab; the registry version is recorded so the Updates tab can flag newer revisions.
- **Export your own** via the Run / Edit / Export menu in `MacroDetailView`.
- **Open from a link** — `cwmacro://import?slug=<slug>` and `https://carrierwave.app/manual/m/<slug>` both route through the same import sheet.

## Telemetry

Run telemetry is **opt-in** and **off by default**. With `Settings → Experiments → Radio CAT Control → Share macro telemetry` enabled, successful and failed runs of registry-installed macros are reported to the activities server. Error messages are stripped to the first four alphanumeric/dash tokens (cap 64 chars) before being sent — callsigns, frequencies, and free-form notes never leave the device. Locally-authored macros never report telemetry regardless of the toggle.

## Limitations & Notes

- Cancellation is cooperative via `Task.cancel`; mid-run cancellation releases the PTT and stops on the next step boundary, not mid-step.
- Tombstoned macros (withdrawn by the author or admin) stay visible in the Mine tab with an orange capsule but Run/Edit are disabled. Delete to remove permanently or "Keep as Read-only Artifact" to retain.
- The vendor command catalog is bundled with the app — Yaesu CAT entries cover FT-857/897/817/991(A) and FT-DX10/710/DX101 generations as of 1.93.0.
- Vintage binary-CAT Yaesu radios (pre-FT-857) must use the raw-bytes step; ASCII vendor commands are FT-857+ only.
