# CAR-123: Command Palette for Radio Tuning (Cmd+Shift+P)

**Date:** 2026-03-06
**Status:** Phase 1 implemented (parser + palette UI + keyboard shortcut wiring)

## Context

CW Sweep already has a Cmd+K command palette (`CommandPaletteView.swift`) that handles app-level actions, role switching, and basic smart parsing (frequencies, callsigns, park references). CAR-123 proposes a dedicated Cmd+Shift+P palette specifically for radio tuning commands with richer parsing and feedback.

The two-palette pattern follows VS Code's Cmd+P (files) vs Cmd+Shift+P (commands) precedent and maps cleanly to how hams think: "do something in the app" vs "tell the radio something."

## Research Summary

### How Existing Loggers Handle This

| Logger | Approach | Key Feature |
|--------|----------|-------------|
| **N1MM+** | Callsign field doubles as command line | Auto-detects frequency vs callsign vs mode; F1-F12 for CW macros |
| **Win-Test** | Richest text command system | `SPLIT`/`NOSPLIT`, `SPEED`, `TIMER`, `SKED`, band-by-meters |
| **MacLoggerDX** | GUI-driven with modifier+arrow keys | Shift/Ctrl/Opt+arrows for frequency stepping |
| **RUMlogNG** | GUI-driven | Arrow keys for frequency stepping |
| **TLF** | Colon-prefixed commands (`:help`) | Bare numbers = frequency (kHz) |

**Universal convention:** Bare numbers are frequencies (kHz), bare mode abbreviations switch mode.

## Command Syntax

### Core Grammar

```
[frequency] [mode] [split_directive]
```

All parts are optional and order-flexible. The parser should produce identical results regardless of token order.

### Frequency Formats

| Input | Interpretation | Rule |
|-------|---------------|------|
| `14074` | 14074 kHz | >= 1000 -> kHz |
| `14074.5` | 14074.5 kHz | >= 1000 with decimal -> kHz |
| `14.074` | 14.074 MHz = 14074 kHz | < 1000 with decimal -> MHz |
| `144300` | 144300 kHz (2m) | VHF/UHF |

### Band Shortcuts

| Input | Default Frequency | Notes |
|-------|------------------|-------|
| `160m` | 1840 kHz | Adjusts by current mode (e.g., FT8 -> 1840, CW -> 1810) |
| `80m` | 3530 kHz | |
| `40m` | 7030 kHz | |
| `20m` | 14030 kHz | |
| `15m` | 21030 kHz | |
| `10m` | 28030 kHz | |
| `6m` | 50100 kHz | |
| `2m` | 144300 kHz | |

Band shortcuts tune to a mode-appropriate default. If mode is FT8, `20m` goes to 14074, not 14030.

### Mode Keywords

`CW`, `SSB` (auto USB/LSB by band), `USB`, `LSB`, `FT8`, `FT4`, `RTTY`, `PSK`/`PSK31`, `AM`, `FM`, `DIGI`/`DATA`

### Split Directives

| Input | Action |
|-------|--------|
| `UP 5` | TX 5 kHz above RX |
| `DN 10` / `DOWN 10` | TX 10 kHz below RX |
| `UP` | TX 1 kHz above (default offset) |
| `SPLIT 14210` | TX on explicit frequency |
| `NOSPLIT` | Disable split |

### Combined Examples

| Input | Action |
|-------|--------|
| `14074 FT8` | Tune 14.074 MHz, FT8 mode |
| `7035 CW` | Tune 7.035 MHz, CW mode |
| `21074 FT8 UP 1` | Tune 21.074, FT8, split +1 kHz |
| `20m SSB` | Tune 20m phone segment |
| `CW` | Mode change only |
| `UP 5` | Split only |

## Commands Beyond Radio Tuning

### Phase 2 Commands

| Command | Action |
|---------|--------|
| `QRZ <call>` / `? <call>` | Callsign lookup |
| `SPOT <call> [freq]` | Spot to cluster |
| `SPOTS [band/mode]` | Show/filter spots |
| `PWR 100` / `PWR QRP` | Set TX power |
| `PARK K-1234` | Change POTA park |
| `SUMMIT W7W/KG-001` | Change SOTA summit |

### Phase 3 Commands

| Command | Action |
|---------|--------|
| `CQ` | Send CQ macro (F1) |
| `WPM 25` / `SPEED 25` | CW speed |
| `TIMER 10M` | Countdown timer |
| `RUN` / `S&P` | Contest mode toggle |
| `MARK` | Mark frequency on bandmap |
| `FIND <call>` | Search log |
| `LAST 10` | Show recent QSOs |
| `COUNT` | Session QSO count |
| `ANT 1` / `ROTOR 45` | Antenna control |

## UX Design

### Parse-and-Confirm Pattern

The radio palette is fundamentally different from the app palette. Instead of search-and-select, it's parse-and-confirm:

```
+--------------------------------------------------+
| Radio   14074 UP 1 CW                            |
+--------------------------------------------------+
|  Frequency  14.074 MHz    20m FT8 segment        |
|  Split      UP 1 kHz     valid offset            |
|  Mode       CW           supported               |
+--------------------------------------------------+
|  [Enter] Apply to radio    [Tab] Autocomplete    |
+--------------------------------------------------+
```

### Key Design Principles

1. **Real-time parse feedback** -- Parsed tokens shown as labeled pills below input, color-coded by validation state (green=valid, yellow=warning, red=error, gray=ambiguous)
2. **Context-awareness** -- Show current radio frequency/mode, gray out unchanged values so user sees what will *change*
3. **Token-order flexibility** -- `CW 14074 UP 1` and `14074 UP 1 CW` parse identically
4. **Completion candidates** -- Typing `14` shows common frequencies: 14.074 (FT8), 14.060 (QRP CW), 14.300 (Emergency), plus recent history

### Progressive Disclosure

**Beginners:**
- Rotating placeholder text: `"e.g. '14074 CW' or '7255 USB UP 5'"`
- Empty state shows recent commands + contextual suggestions
- Inline help when parsing fails: `"Try: frequency [mode] [UP/DOWN offset]"`
- Cmd+? opens syntax cheatsheet popover

**Power users:**
- Up-arrow recalls history (shell-style)
- Abbreviations: `u1` = `UP 1`, band names resolve to band-edge
- Tab completion
- No animation delay
- Preserve partial input if dismissed accidentally (5s window)

### Visual Design

- `.ultraThinMaterial` background, 12pt corner radius
- Top-center anchored, 200ms spring animation
- Mode indicator pill ("Radio" vs "App") to differentiate from Cmd+K
- `.monospacedDigit()` for frequency display
- System semantic colors, not custom radio-themed colors
- Allow palette switching: Cmd+K while radio palette is open morphs to app palette

### Parsing Strategy

Hybrid structured + fuzzy:
1. Try structured parse (frequency/mode/split) first
2. If first token matches a command keyword (exact or fuzzy), parse as named command
3. If input looks like a callsign (letter + digits), offer "Look up?" or "Spot?"

### Keyboard Handling

- `.onKeyPress` (macOS 14+) for arrows/escape/tab/return
- Escape dismisses
- Arrow keys navigate suggestions
- Tab autocompletes
- Enter executes

## Implementation Phases

| Phase | Scope | Depends On |
|-------|-------|-----------|
| **1 (MVP)** | Frequency + mode + split parsing, band shortcuts, live preview, recent history | RadioManager API (exists) |
| **2** | `QRZ`, `SPOT`, `PWR`, `PARK`, `SUMMIT` commands | Phase 1 parser extensibility |
| **3** | CW macros, timer, contest commands, log search, antenna | Phase 2 + keyer integration |
| **4** | Fuzzy command search, `>` bridge between palettes, custom aliases | Phase 2 |

## Key Files

| File | Purpose |
|------|---------|
| `CWSweep/Views/CommandPalette/CommandPaletteView.swift` | Existing Cmd+K palette (reference) |
| `CWSweep/Commands/CWSweepCommands.swift` | Menu bar + keyboard shortcuts |
| `CWSweep/Views/Workspace/WorkspaceView.swift` | Root view, FocusedValues wiring |
| `CWSweep/Utilities/FocusedValues.swift` | Action bridge definitions |
| `CWSweep/Services/Radio/RadioManager.swift` | Radio control API (tuneToFrequency, setMode, setXIT, etc.) |
| `CWSweep/Services/Radio/RadioSession.swift` | Radio session + polling |

## Sources

- [N1MM+ Keyboard Shortcuts](https://n1mmwp.hamdocs.com/setup/keyboard-shortcuts/)
- [N1MM+ Entry Window](https://n1mmwp.hamdocs.com/manual-windows/entry-window/)
- [N1MM+ Function Keys](https://n1mmwp.hamdocs.com/setup/function-keys/)
- [Win-Test Text Commands](https://docs.win-test.com/wiki/Text_commands)
- [MacLoggerDX Keyboard Shortcuts](https://dogparksoftware.com/MacLoggerDX%20Help/mldxfc_keyboard_shortcuts.html)
- [Command Palette UX Patterns](https://medium.com/design-bootcamp/command-palette-ux-patterns-1-d6b6e68f30c1)
- [Command Palette UI Design (Mobbin)](https://mobbin.com/glossary/command-palette)
