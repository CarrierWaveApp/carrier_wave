# Azimuthal Map & Antenna Placement Research

**Date:** 2026-03-06
**Status:** Research / Proposal

## Problem Statement

Portable operators (POTA, SOTA, Field Day) and contesters both need to answer: "Which direction should I focus my antenna?" No mobile ham app provides this. Desktop tools (NS6T azimuthal maps, DX Atlas, DXView, HamClock) exist but aren't integrated with live spots or logging. Hams cobble together Theodolite, Google Earth, or just guess.

## Existing Carrier Wave Primitives

| Primitive | Location |
|-----------|----------|
| Bearing & distance | `MaidenheadConverter.bearing(from:to:)`, `distanceMiles()` |
| Geodesic paths | `QSOAnnotation.computeGeodesicPath()`, `ActivationMapHelpers.geodesicPath()` |
| Antenna type metadata | `AntennaDescriptionParser`, `AntennaType` enum |
| Live spots | `SessionSpot` (RBN, POTA, SOTA, WWFF) |
| DX Cluster (CWSweep) | `TelnetClusterClient`, `DXSpotParser`, `ClusterManager` |
| Grid conversion | `MaidenheadConverter.coordinate(from:)`, `grid(from:)` |
| Map rendering | `QSOMapView` (MapKit), `BandMapView` (Canvas, CWSweep) |
| FT8 bearing enrichment | `FT8DecodeEnricher` — bearing + distance per decode |

## Proposed Features (Ranked)

### Tier 1: Spot-Density Azimuthal View + Antenna Pattern Overlay

**The headline feature.** An azimuthal (polar) projection centered on your GPS location showing:

- **Live spots as a bearing heatmap** — RBN/POTA/SOTA spots plotted by bearing and distance. Color intensity = spot density per angular sector. Filter by band.
- **Your antenna's radiation pattern** — simplified 2D azimuthal lobe overlaid on the same view:
  - Vertical / EFHW-vertical → omnidirectional (circle)
  - Dipole / EFHW-horizontal → figure-8, broadside to wire orientation
  - Yagi / Moxon → cardioid with forward gain lobe
  - Hex beam → wide cardioid
- **Phone compass integration** — as user rotates phone (or manually sets heading), the antenna pattern rotates on the azimuthal map, showing alignment with activity.
- **Actionable guidance** — "Rotate 35° clockwise to cover 40% more active stations."

**Why it's novel:** No mobile ham app combines live spot data with antenna pattern visualization. HamDXMap shows beam width on a globe but it's desktop-only and doesn't use live spots.

**Implementation notes:**
- Azimuthal projection is simple polar coordinates: angle = bearing, radius = distance (with configurable max)
- Render with SwiftUI Canvas for smooth rotation
- Antenna pattern is a polar gain function (no full NEC — just parametric shapes)
- CoreLocation provides compass heading for auto-orientation
- Spot data already flows through `SessionSpot`

### Tier 2: QSO Coverage Gap Analysis

For the current session/activation, overlay logged QSOs on the same azimuthal view:
- **Bright sectors** = lots of QSOs in that direction
- **Dark sectors** = gaps (unexplored bearings)
- Combined with spot overlay: "There are 12 spots at 310° and you have 0 QSOs there"

**For POTA:** Maximize unique contacts by revealing underserved directions.
**For contests:** Classic multiplier hunting — find the bearing sectors with new entities.

### Tier 3: Grayline + MUF Contours

On the azimuthal view:
- **Grayline terminator** — dawn/dusk arc where low-band propagation peaks
- **MUF contours** by bearing — from ionosonde data, showing maximum usable frequency
- Helps predict band openings 15-30 minutes ahead

### Tier 4: Historical Pattern Analysis

After multiple activations with logged antenna type + orientation:
- Build per-band, per-time empirical "what worked" maps
- Compare QSO distances/bearings against antenna orientation across sessions
- Personalized propagation + antenna intelligence from your own data

**Genuinely novel** — nobody does this. Uses data already being collected.

### Tier 5: CW Sweep (Desktop) Extensions

With more screen real estate on macOS:
- Side-by-side: azimuthal map + band map
- Click spot on azimuthal → QSY radio (via CAT) + show bearing for rotator
- Full-session azimuthal time-lapse replay

## What to Skip

| Idea | Why Skip |
|------|----------|
| Full NEC/EZNEC radiation modeling | Too complex, needs ground conductivity, simplified shapes are 90% as useful |
| Rotator control from mobile | Hardware integration rabbit hole, N1MM/DXView own this on desktop |
| VOACAP propagation prediction | Heavy computation, fragile API, real-time spots are a better proxy |
| 3D elevation angle patterns | Hard to visualize on phone, depends on unknown local terrain |

## User Personas

### Portable POTA Activator with Linked Dipole
"I'm at a park with my EFHW over a tree branch. Should I run the wire N-S or E-W? Where are the hunters?" → Spot heatmap + figure-8 pattern overlay answers this in seconds.

### Serious Contester (CW Sweep)
"I've been running EU for 2 hours. Where are the fresh multipliers?" → QSO gap analysis + spot overlay by bearing sector shows neglected directions.

### FT8 Operator
"I see 40 decodes — which direction is the band open?" → FT8DecodeEnricher already provides bearing per decode. Plot them on the azimuthal view for instant propagation awareness.

## Technical Approach

### Azimuthal Projection Math

```
// Center: operator's lat/lon (from GPS)
// For each point (spot, QSO, etc.):
let bearing = MaidenheadConverter.bearing(from: myGrid, to: targetGrid)  // 0-360°
let distance = MaidenheadConverter.distanceMiles(from: myGrid, to: targetGrid)
let radius = min(distance / maxDistance, 1.0)  // normalize to [0, 1]

// Polar to Cartesian for Canvas rendering:
let x = center.x + radius * sin(bearing.radians) * viewRadius
let y = center.y - radius * cos(bearing.radians) * viewRadius
```

### Antenna Pattern Functions (Parametric)

```swift
enum AntennaPattern {
    case omnidirectional                    // gain = 1.0 at all angles
    case figurEight(orientation: Degrees)   // gain = |cos(angle - orientation)|
    case cardioid(heading: Degrees, beamwidth: Degrees)  // forward lobe
}

func gain(at bearing: Degrees) -> Double  // 0.0 ... 1.0, relative
```

### Data Flow

```
SessionSpot / FT8Decode
    → bearing + distance enrichment (MaidenheadConverter)
    → AzimuthalDataProvider (sector binning, density calculation)
    → AzimuthalMapView (Canvas render: heatmap + pattern + grayline)
    → CompassHeadingProvider (CoreLocation) → pattern rotation
```

## Competitive Landscape

| Tool | Platform | Azimuthal | Live Spots | Antenna Pattern | Mobile |
|------|----------|-----------|------------|-----------------|--------|
| NS6T | Web | Yes | No | No | Responsive |
| DX Atlas | Windows | Yes | No | No | No |
| HamDXMap | Web | Globe | No | Beam width | No |
| GridTracker | Desktop | No | FT8 decodes | No | No |
| HamClock | Desktop/RPi | Yes | DX Cluster | No | No |
| DXView | Windows | Yes | DX Cluster | No | No |
| **Carrier Wave** | **iOS/macOS** | **Proposed** | **RBN+POTA+SOTA+FT8** | **Proposed** | **Yes** |

The combination of mobile + live multi-source spots + antenna pattern overlay is unoccupied territory.
