# SDR Recording Server — Product Requirements Document

**Date:** 2026-02-18
**Status:** Draft

## Problem Statement

Today's ham radio operators have limited options for capturing, reviewing, and analyzing RF activity. WebSDRs exist but offer no recording infrastructure, no transcription, and no integration with tools operators already use. The Carrier Wave iOS app has signal-processing algorithms (CW decoding, callsign extraction) that demonstrate what structured data extraction from ham radio sources looks like — but they're limited to the device.

A server-side SDR recording platform removes all those constraints: always-on capture, multi-receiver correlation, persistent archives, and compute-heavy processing (ML classification, auto-transcription) that would drain a phone battery in minutes.

## Vision

An always-on SDR recording server that captures, decodes, transcribes, and indexes CW activity — making the RF spectrum searchable and streamable.

---

## Core Features

### 1. SDR Hardware Discovery & Management

**Automatically discover and manage multiple SDR receivers from a unified interface.**

- **Automatic SDR discovery:**
  - Enumerate all locally-connected SDRs via SoapySDR device enumeration (`SoapySDR::Device::enumerate()`)
  - Detect RTL-SDR, SDRplay RSP, Airspy HF+/Mini, and other SoapySDR-supported hardware automatically
  - Discover network SDRs via mDNS/Avahi (KiwiSDR, FlexRadio SmartSDR)
  - Periodic re-scan to detect hot-plugged or disconnected devices
  - Each discovered SDR assigned a stable ID based on serial number or unique device descriptor
- **Hardware abstraction layer** — unified API across SDR backends:
  - RTL-SDR (via `rtl_sdr` / `SoapySDR`)
  - SDRplay RSP series (via `SoapySDR`)
  - Airspy HF+ / Mini
  - KiwiSDR (network SDR, WebSocket API)
  - FlexRadio SmartSDR (via SmartSDR API / DAX)
  - Elad FDM-S3 or similar high-end DDC receivers
- **Per-SDR configuration (applied after discovery):**
  - Center frequency, sample rate, bandwidth
  - Gain settings (AGC or manual)
  - Antenna port selection
  - Duty cycle / scheduling (e.g., only record 40m at night)
  - Geographic location (for propagation correlation)
  - Label / name for identification
- **Health monitoring:**
  - Signal quality metrics (noise floor, ADC clipping)
  - USB/network connection status
  - Automatic reconnection on dropout
  - Disk usage warnings

### 2. Capture Multiplexer

**Multiple consumers share a single SDR capture — no duplicate data.**

An SDR tuned to a center frequency and sample rate produces one wideband IQ stream. Multiple recordings, live streams, decoders, and RBN-triggered tasks may all need slices of that same data. The capture multiplexer ensures each SDR is tuned once and fans out data to all consumers that need it.

- **Request-driven tuning:**
  - Consumers (recordings, streams, tasks) declare what they need: SDR + center frequency + bandwidth
  - The multiplexer merges overlapping requests into the minimal set of SDR tunings
  - If two recordings want 7.030 MHz / 2.4 kHz and 7.035 MHz / 2.4 kHz on the same SDR, the SDR tunes once to cover 7.028–7.037 MHz and each consumer gets its slice
  - When a wideband capture already covers a new request, no hardware retuning occurs — the new consumer subscribes to the existing IQ stream
- **Broadcast fan-out:**
  - Each active SDR tuning produces one IQ stream
  - A broadcast channel distributes IQ samples to all subscribed consumers with zero-copy where possible
  - Consumers independently filter, demodulate, and decode their slice of the passband
  - Adding or removing a consumer does not interrupt other consumers on the same capture
- **Conflict resolution:**
  - When requests on the same SDR cannot be merged (e.g., 7 MHz and 14 MHz — different bands), the scheduler must choose or time-share
  - Priority system: explicit recordings > RBN-triggered tasks > background monitoring
  - Configurable policy: reject lower-priority request, queue it, or assign to a different SDR if available
  - SDRs with wider bandwidth (SDRplay, Airspy) can cover more requests simultaneously than narrow-bandwidth devices (RTL-SDR)
- **Reference counting & lifecycle:**
  - Each capture session tracks its active consumers
  - When the last consumer unsubscribes, the capture stops (unless a minimum-capture policy is set)
  - Recordings attach to a capture's IQ stream and write their slice; the capture itself is not a recording
  - API exposes the current capture plan: which SDRs are tuned where, how many consumers per capture

### 3. Recording Engine

**Continuous or scheduled RF capture with structured storage.**

- **Recording modes:**
  - Continuous (24/7 band capture)
  - Scheduled (e.g., 20m from 1800-0200 UTC)
  - Triggered (start recording on signal detection above threshold)
  - Event-driven (contest weekends, DXpedition alerts)
- **Capture integration:**
  - Recordings are consumers of the capture multiplexer, not direct SDR controllers
  - Multiple recordings on overlapping frequencies share one capture automatically
  - A recording stores its narrowband slice — it does not duplicate the wideband IQ
- **Storage format:**
  - Raw IQ (for full-fidelity replay and reprocessing)
  - Demodulated audio (WAV/FLAC per-channel)
  - Compressed IQ (SigMF format with metadata)
- **Segmentation:**
  - Automatic chunking by time interval (configurable: 1min, 5min, 15min, 1hr)
  - Signal-boundary detection (split on silence / carrier drop)
  - Per-QSO isolation when decoder is active

### 4. Time Alignment

**Synchronize recordings across multiple SDRs and sessions.**

- GPS-disciplined timestamps (via `gpsd` or NTP with PPS)
- NTP sync with sub-millisecond accuracy when GPS unavailable
- All recordings tagged with UTC timestamp + source SDR ID
- Cross-receiver alignment for comparing the same signal from different locations / antennas
- Drift compensation for SDRs with poor oscillator stability
- Playback engine that can sync multiple recordings to the same timeline

### 5. CW Signal Processing & Decoding

**Extract structured data from CW signals.**

- **CW decoder:**
  - Adaptive speed tracking (5-50 WPM)
  - Multi-signal separation (multiple CW signals in passband)
  - Farnsworth spacing handling
  - Prosign recognition
  - Confidence scoring per character
- **Signal classification:**
  - Detect CW signals from spectral characteristics
  - Distinguish CW from noise, carriers, and other mode signals
  - Unknown signal flagging for manual review

### 6. CW Auto-Transcription

**Convert decoded CW signals to searchable text.**

- **CW transcription:**
  - Real-time Morse-to-text with WPM annotation
  - Callsign extraction and validation against FCC/ITU databases
  - RST report extraction
  - QSO structured data extraction (callsigns, RST, QTH, name, frequency)
- **Transcription storage:**
  - Full text with timestamps linked to audio segments
  - Structured QSO records (callsign, frequency, mode, time, RST, exchange)
  - Full-text search index (Meilisearch or Tantivy)

### 7. Carrier Wave App Streaming

**Live stream decoded CW activity to the Carrier Wave iOS app.**

- **WebSocket streaming:**
  - Live audio stream (Opus-encoded, selectable bandwidth)
  - Real-time decoded text overlay
  - Waterfall/spectrogram data for visual display
  - Band activity heatmap
- **Stream types:**
  - Single-frequency monitor (tune to one signal)
  - Band overview (compressed wideband view)
  - Decoded feed (text-only stream of all decoded QSOs)
  - Alert stream (push notifications for matched criteria)
- **App integration:**
  - Stream discovery (browse available server streams)
  - Multi-server support (connect to multiple recording servers)
  - Offline mode (buffer + store streams for later review)
  - Share interesting captures with other users

### 8. RBN-Driven SDR Tasking

**Automatically tune SDRs based on Reverse Beacon Network spots.**

- **RBN telnet feed integration:**
  - Real-time spot ingestion from RBN nodes
  - Filter by band, mode (CW), SNR, spotted callsign, spotter location
- **Auto-tasking rules:**
  - "When RBN spots a new DXCC entity on 20m CW, tune SDR-2 to that frequency and record for 10 minutes"
  - "Track the loudest CW signal on each open band"
  - "Follow a specific DXpedition callsign across bands"
  - "Record any CW signal above 30 dB SNR on 40m"
- **DX Cluster integration:**
  - Ingest DX cluster spots alongside RBN
  - Cross-reference spots with recordings ("was I actually hearing that DX?")
  - Spot validation — confirm RBN/cluster spots with local reception
- **Propagation-aware scheduling:**
  - Use VOACAP / IRI models to predict band openings
  - Pre-position SDRs on bands predicted to open
  - Seasonal/solar cycle profiles

---

## Extended Features

### 9. Band Condition Monitoring & Analytics

- Continuous noise floor measurement per band
- Band-open / band-closed detection
- Propagation mode classification (F2, Es, ground wave) from signal characteristics
- Historical band condition database (queryable: "How was 10m on 2026-01-15?")
- Solar flux / K-index / A-index correlation with observed conditions
- Automated band condition reports (daily/hourly summaries)

### 10. Contest Recording & Replay

- Full-band IQ capture during contest weekends
- Post-contest replay with synchronized clock
- Rate meter overlay (QSOs/hour from decoded CW signals)
- Multiplier tracking from decoded exchanges
- Log cross-reference (compare your log against what was actually on the air)
- Spectrum timelapse generation (compressed waterfall video of entire contest)

### 11. CW Skimmer-as-a-Service

- Continuous CW decoding across multiple bands simultaneously
- Publish spots to RBN (become an RBN node)
- Private spot feed for personal use
- Historical spot database with search
- Frequency/callsign activity graphs over time

### 12. Multi-Site Correlation

- Federate multiple recording servers across geographic locations
- Compare signal reports from different QTHs simultaneously
- True diversity reception (combine signals from multiple sites)
- Propagation path visualization on map
- Collaborative recording (multiple operators contribute SDRs to a shared pool)

### 13. Alert System

- **Trigger types:**
  - Callsign spotted (specific call or prefix, e.g., "any 3Y*")
  - Band opening detected (specific band + direction)
  - New DXCC entity heard
  - Contest starting
  - Signal anomaly (unusual signal type detected)
  - Silence alert (expected signal disappeared — monitor goes quiet)
- **Delivery:**
  - Push notification to Carrier Wave app
  - Email digest
  - Webhook (integrate with Discord, Slack, Home Assistant)
  - SMS via Twilio (for critical alerts)

### 14. Archive & Search

- Retain recordings based on configurable policies (keep all CW forever, raw IQ for 7 days)
- Full-text search across all transcriptions
- Filter by: date range, frequency, mode, callsign, SNR, duration
- "Find all QSOs involving W1AW on 20m CW in January 2026"
- Shareable permalinks to specific recordings
- ADIF export of decoded QSOs for logging software (Log4OM, DXKeeper, Cloudlog)

### 15. Logging Integration

- Export decoded QSOs as ADIF records
- Direct integration with Cloudlog, Log4OM, DXKeeper, N1MM+
- QSO confirmation cross-reference (check against LoTW, QRZ, eQSL)
- DXCC / WAS / VUCC progress tracking from decoded signals
- "You've heard 237 DXCC entities this month but only logged 180"

### 16. Additional Mode Support (Post-MVP)

- FT8 / FT4 (via `wsjtx` integration or `ft8_lib`)
- RTTY (45.45 baud, 170 Hz shift standard + variants)
- PSK31 / PSK63
- JS8Call
- SSB voice transcription via Whisper
- AM / FM demodulation

---

## Architecture

### System Overview

```
                                    ┌─────────────────┐
                                    │  Carrier Wave    │
                                    │  iOS App         │
                                    └────────┬─────────┘
                                             │ WebSocket / REST
                                             │
┌──────────┐   ┌──────────┐        ┌────────┴──────────┐
│ RTL-SDR  │   │ KiwiSDR  │  ...   │   API Gateway     │
│ (local)  │   │ (remote) │        │   (axum / tower)  │
└────┬─────┘   └────┬─────┘        └────────┬──────────┘
     │              │                       │
     └──────┬───────┘               ┌───────┴────────┐
            │                       │                │
     ┌──────┴───────┐        ┌─────┴─────┐   ┌─────┴──────┐
     │ SDR Manager  │        │ Recording │   │ Search /   │
     │ (Discovery + │        │ Archive   │   │ Query API  │
     │  SoapySDR)   │        │ (S3/disk) │   └─────┬──────┘
     └──────┬───────┘        └─────┬─────┘         │
            │                      │          ┌────┴───────┐
     ┌──────┴───────┐             │          │ Tantivy /  │
     │   Capture    │◄────────────┘          │ Meilisearch│
     │ Multiplexer  │◄──── Live Streams      └────────────┘
     │ (merge reqs, │◄──── RBN Tasks
     │  fan-out IQ) │◄──── Decoders
     └──────┬───────┘
            │ broadcast IQ
     ┌──────┴───────┐
     │ DSP Pipeline │
     │ (IQ → audio) │
     └──────┬───────┘
            │
     ┌──────┴───────┐
     │  CW Decoder  │
     │  Farm        │
     └──────┬───────┘
            │
     ┌──────┴───────┐
     │ Transcription│──→ Search Index
     │ + QSO Extract│──→ ADIF Export
     └──────┬───────┘──→ Alert Engine
            │
     ┌──────┴───────┐
     │ RBN / DX     │
     │ Cluster Feed │
     └──────────────┘
```

### Tech Stack (proposed)

| Component | Technology | Rationale |
|-----------|-----------|-----------|
| Core server | Rust (tokio + axum) | Existing backend familiarity, performance for DSP |
| SDR interface | SoapySDR (C/Rust bindings) | Broadest hardware support + built-in enumeration |
| SDR discovery | SoapySDR enumerate + mDNS | Automatic detection of local and network SDRs |
| Capture multiplexer | Rust (tokio broadcast channels) | Zero-copy fan-out of IQ to multiple consumers |
| DSP | Rust (`rustfft`, custom filters) | Low-latency, zero-copy processing |
| CW decoder | Rust (port from iOS algorithms) | Direct code reuse path |
| Storage | Local disk + optional S3 | IQ files are large, need tiered storage |
| Metadata DB | SQLite (single node) / Postgres (multi) | Structured QSO/recording metadata |
| Search index | Tantivy (Rust) or Meilisearch | Full-text search over transcriptions |
| Streaming | WebSocket (tokio-tungstenite) | Low-latency live audio + data |
| Config | TOML files + REST API | File-based for headless, API for app control |
| RBN feed | Telnet client (tokio) | Standard RBN interface |
| Alerts | Push (APNs), webhooks, email (lettre) | Multi-channel notification |

### Storage Estimates

| Data Type | Rate | Daily (per SDR) | Monthly |
|-----------|------|-----------------|---------|
| Raw IQ (2 MS/s, 8-bit) | ~4 MB/s | ~346 GB | ~10 TB |
| Raw IQ (250 kS/s, 16-bit) | ~1 MB/s | ~86 GB | ~2.6 TB |
| Demodulated audio (48kHz mono FLAC) | ~100 KB/s | ~8.6 GB | ~260 GB |
| Transcription text | negligible | ~10 MB | ~300 MB |

IQ storage is the bottleneck. Tiered retention is essential: keep full IQ for days, audio for weeks/months, text forever.

---

## Configuration Example

```toml
[server]
name = "k1abc-sdr-server"
location = "FN42ig"  # Maidenhead grid
gps_device = "/dev/ttyACM0"  # optional, for precise timing

[discovery]
enabled = true
rescan_interval_secs = 30          # re-enumerate local devices every 30s
mdns_enabled = true                # discover network SDRs via mDNS
mdns_browse_types = ["_kiwisdr._tcp", "_smartsdr._tcp"]

# Override labels or settings for specific discovered SDRs by serial/ID.
# SDRs not listed here still work with defaults.
[discovery.overrides."00000001"]    # RTL-SDR serial number
label = "40m Dipole"
antenna = "dipole-40m"

[discovery.overrides."00000002"]
label = "20m Yagi"
antenna = "yagi-20m"

# Network SDRs that can't be auto-discovered can be added manually
[[discovery.network_sdrs]]
driver = "kiwisdr"
url = "http://vk4rza.proxy.kiwisdr.com:8073"
label = "VK4 KiwiSDR"

[[recording]]
sdr = "00000001"  # matches by discovered serial/ID
frequency = 7_030_000  # 40m CW
bandwidth = 2_400
mode = "cw"
schedule = "00:00-06:00 UTC"  # nighttime propagation
decoders = ["cw"]
retention_days = 30

[[recording]]
sdr = "00000001"
frequency = 14_035_000  # 20m CW
bandwidth = 2_400
mode = "cw"
schedule = "always"
decoders = ["cw"]
retention_days = 90

[[rbn_task]]
trigger = "new_dxcc"
band = "20m"
mode = "cw"
min_snr = 15
sdr = "00000001"
action = "record"
duration_minutes = 10
alert = true

[[alert]]
name = "Bouvet Island"
type = "callsign_prefix"
prefix = "3Y"
notify = ["push", "email"]
```

---

## API Surface (sketch)

```
GET    /api/v1/sdrs                          # list discovered SDRs
GET    /api/v1/sdrs/discover                 # trigger re-scan
GET    /api/v1/sdrs/:id/status               # health, signal metrics
PUT    /api/v1/sdrs/:id/config               # override settings for a discovered SDR

GET    /api/v1/captures                        # list active captures (SDR tunings + consumers)
GET    /api/v1/captures/:id                    # capture detail (frequency, bandwidth, consumer count)

GET    /api/v1/recordings                    # list recordings (filtered)
GET    /api/v1/recordings/:id                # recording metadata
GET    /api/v1/recordings/:id/audio          # stream audio (range support)
GET    /api/v1/recordings/:id/iq             # download raw IQ
GET    /api/v1/recordings/:id/transcript     # decoded text

GET    /api/v1/qsos                          # search decoded QSOs
GET    /api/v1/qsos/export?format=adif       # ADIF export

GET    /api/v1/bands                         # current band conditions
GET    /api/v1/bands/:band/history           # historical conditions

WS     /api/v1/stream/:sdr_id               # live audio + decode stream
WS     /api/v1/stream/decoded               # all decoded text (firehose)
WS     /api/v1/stream/alerts                # alert feed

GET    /api/v1/spots                         # RBN/cluster spots
GET    /api/v1/spots/matched                 # spots matched to recordings

POST   /api/v1/tasks                         # create RBN-driven task rule
GET    /api/v1/tasks                         # list task rules

GET    /api/v1/search?q=...                  # full-text transcription search
```

---

## Deployment Models

### Single Station (Home Operator)
- Raspberry Pi 5 or mini PC
- 1-2 RTL-SDRs (auto-discovered on USB)
- External USB drive for storage
- Runs as systemd service
- Accessible via Tailscale for remote monitoring

### Club Station
- Dedicated server (8+ cores, 32GB RAM)
- Multiple SDRs covering HF bands (auto-discovered)
- NAS or S3-compatible storage
- Multi-user access with API keys
- Dashboard on always-on monitor in shack

### Distributed Network
- Multiple single-station nodes reporting to a coordinator
- Shared search index across sites
- Cross-site signal comparison
- Aggregated band condition reports

---

## Open Questions

1. **IQ vs. audio-only recording?** Full IQ enables reprocessing with better decoders later, but storage costs are 10-40x higher. Offer both, default to audio-only with IQ opt-in?
2. **KiwiSDR ToS?** Some public KiwiSDRs prohibit automated/continuous use. Need per-SDR policy configuration and rate limiting.
3. **Privacy considerations?** Recording and transcribing CW QSOs at scale — ham radio is legally public, but bulk collection could be controversial. Consider opt-out mechanisms or callsign anonymization options.
4. **Monetization model?** Open source core with hosted/managed service? Hardware bundles? Or purely open source community project?
5. **FCC Part 97 compliance?** Automated retransmission (streaming to app users) — need to verify this doesn't constitute rebroadcasting under Part 97 rules. Likely fine since it's internet retransmission, not RF, but worth confirming.
6. **SoapySDR driver coverage?** Verify that all target SDR hardware has working SoapySDR drivers on Linux/ARM. RTL-SDR and SDRplay are well-supported; Airspy and FlexRadio support should be validated.
7. **Hot-plug reliability?** USB device hot-plug detection on Linux can be finicky. May need udev rules as a fallback alongside SoapySDR enumeration.

---

## Milestones

### M0: Foundation
- SDR auto-discovery (SoapySDR enumeration + mDNS)
- SDR hardware abstraction (RTL-SDR + KiwiSDR)
- Capture multiplexer (merge overlapping requests, broadcast fan-out)
- Basic recording engine (continuous capture to FLAC, as multiplexer consumer)
- GPS/NTP time-stamping
- TOML configuration with discovery overrides
- REST API skeleton

### M1: CW Decoding
- CW decoder (port from iOS)
- CW transcription storage + basic search
- Per-recording metadata
- Callsign extraction and validation

### M2: Streaming & App Integration
- WebSocket audio streaming
- Carrier Wave app connection
- Live CW decode overlay
- Stream discovery API

### M3: Intelligence
- RBN feed integration
- Auto-tasking engine
- Alert system (push + webhook)
- Band condition monitoring

### M4: Scale
- Multi-SDR coordination
- Multi-site federation
- CW signal classification (ML)
- Full-text search index
- Contest recording mode

### M5: Additional Modes & Community
- FT8/FT4 decoder integration
- RTTY / PSK31 decoders
- Voice transcription (Whisper)
- Public API for third-party integrations
- ADIF export + logging software integration
- Shared recording archives
- Collaborative spot validation
