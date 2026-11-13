# Ecosystem Features Plan: Propagation, PSK Reporter, Contests

Three features to bring Carrier Wave up to parity with (and beyond) the broader amateur radio ecosystem.

---

## Feature 1: Propagation Prediction (KC2G MUF Integration)

### What
Overlay real-time Maximum Usable Frequency (MUF) data on the QSO map, plus a dedicated propagation view showing band openings from the user's location.

### Data Source
**KC2G prop.kc2g.com** — open source, no auth, 5-minute updates from real ionosonde measurements worldwide. Far more accurate than pure VOACAP modeling because it uses Gaussian Process Regression on actual ionosonde data.

Endpoints:
- `https://prop.kc2g.com/renders/current/mufd-normal-now.geojson` — global MUF contour data
- `https://prop.kc2g.com/api/moflof.svg?grid=CN84QL&metric=mof_sp` — personalized MOF/LOF from user's grid
- 24-hour lookahead predictions available (hourly increments)

### Implementation

#### Phase 1: Band Conditions Enhancement (small)
- Add KC2G MUF data to the existing solar conditions polling
- New dashboard card: "Band Openings" showing which bands are currently open from user's grid
- Color-coded band indicators (open/marginal/closed) based on MUF vs band frequency
- Uses existing `SolarPollingService` cadence, adds a second fetch to KC2G

#### Phase 2: MUF Map Overlay (medium)
- GeoJSON MUF contour overlay on the existing QSO map
- Color gradient showing MUF across the globe (similar to KC2G's web display)
- Toggle on/off from map controls
- User taps a region → shows "20m open, 15m marginal, 10m closed" for that path

#### Phase 3: Propagation Timeline (medium)
- 24-hour propagation forecast from user's grid
- Band-by-direction heatmap: time on X axis, compass bearing on Y, color = band openness
- "Best time to work Japan on 20m" type insights
- Uses KC2G's hourly prediction endpoints

### Architecture
- New `PropagationClient` actor in CarrierWaveData (fetches KC2G GeoJSON/JSON)
- `PropagationPollingService` with 5-minute interval (matches KC2G update rate)
- GeoJSON parsing with existing MapKit overlay infrastructure
- No SwiftData persistence needed — ephemeral data, re-fetched on launch

### Effort
Phase 1: ~2 days. Phase 2: ~3-4 days. Phase 3: ~3-4 days.

---

## Feature 2: PSK Reporter Integration

### What
Add PSK Reporter as a spot source for digital mode activity, plus a "who heard me?" / "who did I hear?" feature after FT8 sessions.

### Data Sources

**HTTP API** — `https://retrieve.pskreporter.info/query`
- XML responses, no auth, poll max every 5 minutes
- Query by sender callsign, receiver callsign, mode, frequency range
- 24-hour lookback window

**MQTT Feed** — `mqtt.pskreporter.info:1883`
- Real-time JSON stream, no auth
- Topic-based filtering: `pskr/filter/v2/{band}/{mode}/{sendercall}/{receivercall}/{senderlocator}/{receiverlocator}/{sendercountry}/{receivercountry}`
- 500+ spots/second at peak — must use filtered subscriptions

### Implementation

#### Phase 1: PSK Reporter Spots in Spot Feed (medium)
- New `PSKReporterClient` actor alongside existing `RBNClient`
- HTTP API polling every 5 minutes for spots matching user's needs (DXCC, WAS, etc.)
- Merge PSK Reporter spots into existing spot aggregation pipeline
- Badge spots with source indicator (RBN/POTA/SOTA/WWFF/PSKR)
- Enrichment with existing worked-before, DXCC, distance pipeline

#### Phase 2: "Who Heard Me?" Post-Session Report (medium)
- After ending an FT8/FT4 session, query PSK Reporter for user's callsign as sender
- Map visualization: pins showing every station that decoded you, with SNR
- Distance/bearing statistics, band coverage analysis
- Useful for antenna comparison and propagation study
- Shareable as part of brag sheet

#### Phase 3: Real-time MQTT Feed (large, optional)
- CocoaMQTT or MQTT-NIO for live streaming during active FT8 sessions
- Show real-time "your signal is being heard by..." overlay
- iOS background execution limits mean this only works while app is foregrounded
- Consider whether this adds enough over 5-minute HTTP polling to justify complexity

### Architecture
- `PSKReporterClient` actor in CarrierWaveData
- XML parsing via `XMLParser` for HTTP API (or use SWXMLHash)
- Spots normalized to existing `AggregatedSpot` model
- MQTT client (Phase 3) as optional foreground-only service
- No new SwiftData models — spots are ephemeral like existing spot sources

### Effort
Phase 1: ~3-4 days. Phase 2: ~2-3 days. Phase 3: ~4-5 days (if pursued).

### Also Discovered: Spothole
[spothole.app](https://spothole.app) is an open-source spot aggregator with a JSON REST API that combines DX clusters, RBN, POTA, SOTA, WWFF, and more. Could potentially replace multiple individual spot clients with a single unified API. Worth evaluating as a simplification play for the entire spot pipeline.

---

## Feature 3: Mobile Contesting

### The Core Question: How Does Contesting Make Sense on a Phone?

You're right to question this. N1MM Logger+ is designed for a 3-monitor desktop setup with CAT control, CW keyers, SO2R switching, and multi-operator networking. That world doesn't translate to mobile.

But here's what DOES make sense on mobile:

### The Mobile Contest Use Cases

**1. Field Day (the big one)**
- 50,000+ participants annually, largest ham event in North America
- Explicitly designed for portable/emergency operation
- Categories include 1D (one person, battery power) and 1E (one person, emergency power)
- Many ops run Field Day from a park, a picnic table, or their car
- Exchange is simple: class + ARRL section (e.g., "1D SCV")
- This is ALREADY a Carrier Wave use case — people activate POTA parks during Field Day

**2. State QSO Parties**
- Dozens per year, casual/friendly, many portable operators
- Exchange is usually RST + county or state
- Often combined with POTA activations ("I'm activating a park AND participating in the PA QSO Party")
- Lower rate, phone-friendly pace

**3. QRP Contests**
- QRP operators frequently operate portable with minimal gear
- Slower pace, fewer contacts — perfect for phone logging
- Examples: ARRL QRP contest, Flight of the Bumblebees, Zombie Shuffle

**4. NAQP (North American QSO Party)**
- Popular, 100W max, CW and phone
- Simple exchange: name + state/province
- Many casual participants just want to log a few dozen contacts

**5. Casual participation in big contests**
- Not everyone in CQ WW is trying to win
- Many ops just want to "hand out contacts" and submit a valid log
- Mobile makes it easy to participate without the full desktop setup

### What Mobile Contesting Does NOT Need
- Multi-radio SO2R switching
- CW keyer integration (we have FT8, and phone contests work fine)
- Rotor control
- Multi-operator networked logging (CW Sweep handles this)
- Super Duper features or hyper-optimized rate tools
- Bandmap (nice-to-have later, but not essential for casual contesting)

### What Mobile Contesting DOES Need

**Must-haves:**
1. **Contest session type** — Start a session with a contest template selected
2. **Dynamic exchange fields** — Logger shows the right fields for the selected contest (RST + CQ zone for CQ WW, name + section for Sweepstakes, class + section for Field Day, etc.)
3. **Auto serial numbers** — Increment sent serial automatically
4. **Dupe checking** — "DUPE!" indicator on callsign entry (per contest rules: same band, same mode, etc.)
5. **Running score** — QSO count, points, multipliers visible during session
6. **Cabrillo export** — Generate valid Cabrillo 3.0 file for submission
7. **ADIF contest fields** — Ensure contest QSOs sync properly with contest fields populated

**Nice-to-haves (later):**
8. Band/mult tracker — grid showing which multipliers you still need on which bands
9. Rate display — QSOs/hour, points/hour
10. Contest-specific spot filtering — show spots that are new multipliers
11. CW macros — if BLE radio control is connected, send contest exchanges
12. Contest calendar integration — tap "Join" on an upcoming contest to start a contest session

### The Huge Advantage: We Already Have 80% of This

CW Sweep already has a full contest engine:
- `ContestDefinition` model with 8 bundled templates (Field Day, CQ WW CW/SSB, ARRL DX, NAQP CW, Sweepstakes, State QSO Party)
- `ContestEngine` actor with dupe checking, scoring, multiplier tracking, serial management
- `ContestExchangeParser` that classifies tokens (RST, CQ zone, ARRL section, state, name, etc.)
- `CabrilloExportService` for Cabrillo 3.0 generation
- `ContestDefinition` and QSO contest fields are already in CarrierWaveData (shared package!)

The QSO model already has: `contestName`, `contestSerialSent`, `contestSerialReceived`, `contestExchangeSent`, `contestExchangeReceived`. The LoggingSession model already has: `contestId`, `contestCategory`, `contestPower`, `contestBands`, `contestOperator`, `isContest`.

**We're not building a contest engine. We're building contest UI for iOS and porting the CW Sweep services to the shared package.**

### Implementation

#### Phase 1: Contest Session Setup (medium)
- Move `ContestTemplateLoader` and contest template JSON files from CWSweep into CarrierWaveData
- New "Contest" session type in session start flow
- Contest picker: shows upcoming contests from existing calendar, plus full template list
- Contest setup sheet: category (Single-Op, etc.), power class, band selection
- Persist contest metadata on LoggingSession (fields already exist)

#### Phase 2: Contest Logger UI (large — the key phase)
- Move `ContestEngine` and `ContestExchangeParser` from CWSweep into CarrierWaveData
- Adapt the logging view for contest mode:
  - Dynamic exchange field row below callsign (fields determined by ContestDefinition)
  - Each field has appropriate keyboard type (numeric for serial, text for name/section)
  - Tab/Next button flows through fields in order
  - Auto-populate sent exchange from session config
  - Auto-increment serial number
- Dupe indicator on callsign field (red "DUPE" badge, sourced from ContestEngine)
- Score bar: persistent footer showing QSOs | Points | Mults
- "Log it" commits the QSO with all contest fields populated

**Mobile UX considerations:**
- Exchange fields should use smart keyboards (number pad for serial, text for name)
- One-tap band switching (segmented control or quick-access band buttons)
- Mode indicator but not mode switching (most mobile ops stick to one mode per session)
- Callsign field remains primary — tap callsign, get dupe check, fill exchange, log
- Landscape support for faster two-thumb entry (optional)

#### Phase 3: Scoring & Cabrillo Export (medium)
- Move `CabrilloExportService` from CWSweep into CarrierWaveData
- Live score computation from ContestEngine during session
- Score summary view: QSOs by band, multiplier breakdown, claimed score
- Cabrillo export via share sheet (email to contest sponsor or save to Files)
- ADIF export with contest fields for service sync

#### Phase 4: Contest Enhancements (small each, pick and choose)
- Band/multiplier matrix: grid showing needed mults per band
- Rate meter: QSOs/hour rolling average
- Contest-filtered spots: existing spot feed filtered to show new multipliers
- Contest calendar "Join" button: tap upcoming contest → start contest session with template pre-selected
- Custom contest templates: user-defined for smaller/regional contests

### Architecture Notes
- `ContestEngine`, `ContestExchangeParser`, `CabrilloExportService`, `ContestTemplateLoader` all move from `CWSweep/Services/Contest/` to `CarrierWaveData/Sources/CarrierWaveData/Services/Contest/`
- Contest template JSON files move to `CarrierWaveData/Sources/CarrierWaveData/Resources/ContestTemplates/`
- CWSweep imports from CarrierWaveData instead of its own copies
- iOS logging view gets a contest mode variant (conditional exchange fields, score bar)
- No new SwiftData models — ContestDefinition stays in-memory, QSO/LoggingSession fields already exist

### Effort
Phase 1: ~2-3 days. Phase 2: ~5-7 days. Phase 3: ~3-4 days. Phase 4: ~1-2 days each.

---

## Priority Recommendation

| Feature | Impact | Effort | Recommendation |
|---------|--------|--------|----------------|
| Propagation (Phase 1) | High — every op wants band conditions | Small | **Do first** — quick win |
| Contest (Phases 1-3) | High — Field Day alone justifies it | Large | **Do second** — biggest gap, most code already exists |
| PSK Reporter (Phase 1) | Medium — enriches existing spot feed | Medium | **Do third** — additive to existing infrastructure |
| Propagation (Phase 2-3) | Medium — visual wow factor | Medium | After core features |
| PSK Reporter (Phase 2) | Medium — great for FT8 operators | Medium | After core features |

The contest work is the largest effort but also the most impactful differentiator. No other iOS app does real contesting with proper scoring and Cabrillo export. And we already have the engine — it's sitting right there in CW Sweep.

---

## Research Sources
- KC2G propagation: https://prop.kc2g.com, github.com/arodland/prop
- PSK Reporter API: https://pskreporter.info/pskdev.html
- PSK Reporter MQTT: mqtt.pskreporter.info (by M0LTE)
- Spothole aggregator: https://spothole.app
- ARRL Field Day rules: https://www.arrl.org/field-day-rules
- N1MM Logger+: https://n1mmwp.hamdocs.com
- CW Sweep contest engine: CWSweep/Services/Contest/ (our own codebase)
- Cabrillo 3.0 spec: https://wwrof.org/cabrillo/
