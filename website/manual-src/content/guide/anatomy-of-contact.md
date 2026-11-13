---
title: "The Anatomy of a Contact"
description: "What information makes up a QSO"
weight: 2
---

Every {{< term "QSO" >}} consists of information that both stations exchange and record.

## The Basics

### Callsigns

Every contact involves two {{< term "Callsign" >}}s — yours and theirs. US callsigns start with W, K, N, or AA-AL; Canadian calls start with VE; Japanese with JA. When you type a callsign into Carrier Wave, the app looks it up and fills in the operator's name and location automatically.

### Date and Time

Contacts are always logged in {{< term "UTC" >}} (Coordinated Universal Time), not local time. This prevents confusion when stations in different time zones log the same contact. Carrier Wave records UTC automatically.

### Frequency and Band

The {{< term "Band" >}} is which part of the radio spectrum you're using — think of bands as neighborhoods on the dial:

- **HF**: 80m, 40m, 20m, 15m, 10m — long-distance bands that can reach around the world
- **VHF**: 6m, 2m — regional range, great for repeaters
- **UHF**: 70cm — local range, common for handhelds

The frequency is more specific — for example, 14.250 MHz on the 20 meter band.

### Mode

The {{< term "Mode" >}} describes how you're communicating:

- **SSB** (Single Sideband) — Voice on HF
- **FM** — Voice on VHF/UHF, the mode your handheld probably uses
- **CW** — Morse code (yes, people still love it!)
- **FT8** — A digital mode where your computer sends encoded messages. Works with incredibly weak signals. Carrier Wave has built-in FT8 support.

## Signal Reports (RST)

Stations exchange signal reports using the {{< term "RST" >}} system:

- **R** (Readability): 1-5, how clearly you understand them
- **S** (Signal Strength): 1-9, how strong their signal is
- **T** (Tone): 1-9, Morse code tone quality (CW only)

A typical voice report is "59" (perfectly readable, very strong). A CW report might be "599."

{{< callout "note" "The 59 Convention" >}}
In contests and quick contacts, many operators exchange "59" regardless of actual signal quality. For casual conversations, listen carefully and report what you actually hear.
{{< /callout >}}

## Optional Information

Beyond the basics, you can also log:

- **Name** — Often filled in automatically from QRZ lookups
- **QTH** — Their location (ham code for "What is your location?")
- **Grid Square** — A precise location code based on a worldwide grid system
- **State/Province** — Useful for Worked All States (WAS) awards
- **Notes** — Anything memorable ("First DX contact!" or "Great antenna discussion")
- **Park or Summit Reference** — If the other station is activating a park (POTA) or summit (SOTA), log the reference so both of you get credit
- **Photos** — Attach photos to sessions for remembering where you operated

## Equipment

Carrier Wave tracks the gear you used for each session — radio, antenna, key, and microphone. This helps you compare how different setups perform.

## What's Next?

Now that you know what goes in a log entry, let's explore [why you might want to sync your log to the cloud](/guide/why-cloud/).
