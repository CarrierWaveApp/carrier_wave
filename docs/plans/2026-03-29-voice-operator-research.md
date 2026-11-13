# Voice/SSB Operator Research

**Date:** 2026-03-29
**Status:** Research complete

## Context

Research into what voice/SSB operators care about and what Carrier Wave can add to improve their experience. Combines codebase analysis with community research across QRZ forums, Reddit, POTA community, eHam, and competitor analysis (N1MM, Log4OM, HAMRS, Ham2K PoLo).

## What We Already Do Well

- **Smart RST defaults**: 59 for phone, 599 for CW — automatic based on mode
- **Quick entry parsing**: `W1AW 57` logs a voice QSO in seconds
- **Band plan integration**: Suggests correct phone segments per band (e.g., 14.250 for 20m SSB)
- **Equipment tracking**: Mic picker appears for voice sessions
- **POTA phone counting**: Separate CW/data/phone QSO counters
- **CAT control**: Real-time freq/mode sync with Icom CI-V, Kenwood, Yaesu
- **Phone/SSB dedup repair**: Merges USB/LSB/SSB/PHONE mismatches automatically

## Key Findings

### 1. Speed Is Everything

Voice QSOs happen every 15-30 seconds in pileups. FT8 has 15-second auto-sequenced windows. Voice operators are in live conversation with zero pause time for UI.

- POTA doesn't even import RST data — signal report fields are pure waste for activators
- Most voice ops give 59/59 every time — the fields are wasted taps for 95%+ of contacts
- The bar for replacing paper logging: "faster than writing"
- N1MM users report eliminating mouse grabs saves 80+ minutes over 1,000 QSOs

**Opportunity:** Callsign-only fast log mode. One field, one tap. RST defaults silently.

### 2. Callsign Accuracy Is the #1 Challenge

Voice callsigns are frequently misheard (D/T/V sound alike, accents, QRM). Unlike FT8 where decoding is binary, voice is noisy and ambiguous.

- No logging app currently displays phonetic spelling of callsigns — unique opportunity
- Partial callsign lookup ("W1A...") helps resolve ambiguous calls
- Previous QSO recall ("worked 3x before") enriches live conversation

**Opportunity:** Phonetic overlay, fuzzy/partial callsign search, super-check partial.

### 3. Frequency Management Is More Complex

Voice operators QSY frequently, chase spots, use split TX/RX frequencies.

- Split frequency support needed for DX operations (TX on one freq, RX on another)
- 60-meter band has special USB-only rules with 5 discrete channels
- Band edge awareness prevents out-of-band transmission from SSB bandwidth

**Opportunity:** Split freq display, recent frequencies bar, band segment indicator.

### 4. Spots & Needs Are Underserved for Voice

- No automated spotting for SSB (unlike RBN for CW, PSK Reporter for digital) — self-spotting is critical
- Mode-specific needs tracking (WAS-SSB, DXCC-SSB are real awards)
- DXPulse concept: FT8 SNR can estimate SSB feasibility on same path

**Opportunity:** One-tap self-spot, mode-specific needs, voice spot prioritization.

### 5. Context During the QSO Matters More

Voice operators want info while talking — no pause between sequences like FT8.

- Operator name must be visible before QSO ends ("Thanks John")
- Previous QSO history enables "Good to work you again!"
- Quick notes for things mentioned in conversation

**Opportunity:** Prominent name display, previous QSO badge, quick notes chips.

### 6. Portable/Field Operation

- One-handed operation (holding mic with other hand)
- Sunlight-readable, large touch targets
- Offline-first (many parks have no cell service)
- Paper vs app debate is real — app must be faster than paper

**Opportunity:** Optimized for outdoor, one-handed, gloved operation.

## Priority Ranking

| Pri | Feature | Impact | Effort |
|-----|---------|--------|--------|
| P0 | Inline dupe check (real-time as you type) | Critical | Small |
| P0 | Prominent name display from lookup | High | Small |
| P1 | Quick SSB mode (callsign-only + auto 59) | High | Medium |
| P1 | Previous QSO history badge | High | Small |
| P1 | Live session stats bar (rate, count, time) | High | Medium |
| P1 | One-tap POTA self-spot | High | Medium |
| P2 | Phonetic alphabet overlay | Medium | Small |
| P2 | Super-check partial (fuzzy callsign match) | Medium | Medium |
| P2 | Quick notes chips | Medium | Small |
| P2 | Mode-specific needs (WAS-SSB, DXCC-SSB) | Medium | Medium |
| P3 | Split frequency support | Medium | Medium |
| P3 | Recent frequencies quick-switch | Medium | Small |
| P3 | Band segment indicator | Low-med | Small |
| P3 | Haptic feedback on log | Low | Tiny |

## Competitor Landscape

| Feature | N1MM | Log4OM | HAMRS/PoLo | CW (us) |
|---------|------|--------|------------|---------|
| Voice keyer (F-key WAV) | Yes | No | No | No |
| Real-time dupe checking | Yes | Yes | Yes | Partial |
| Phonetic display | No | No | No | No |
| Run/S&P mode | Yes | No | No | No |
| One-tap self-spot | No | No | PoLo yes | No |
| Previous QSO recall | Yes | Yes | Partial | No |
| iOS/mobile native | No | No | Yes | Yes |

## Sources

- QRZ forums, Reddit r/amateurradio, POTA community
- N1MM, Log4OM, Ham2K PoLo, HAMRS documentation
- WT8P, K0PIR, QRPer, VK5PAS blogs
- HamAlert, DXPulse, POTACAT documentation
- ARRL band plans, RST system references
