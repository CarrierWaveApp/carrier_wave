---
title: "Map View"
description: "QSO map, azimuthal projection, park boundaries, overlays, and activation maps"
weight: 12
showToc: true
---

The Map View displays your {{< term "QSO" >}} contacts on an interactive world map with markers, geodesic paths, overlays, and performance-optimized rendering.

## Overview

Map View provides visual insight into your operating patterns by showing:

- Contact locations with marker pins
- Geodesic arc paths from your station to contacted stations
- Distance and direction statistics
- Geographic coverage (states, {{< term "DXCC" >}} entities)
- Real-time session maps during active logging
- Park boundaries, summit pins, and grid square overlays

All map rendering respects your privacy settings and only displays contacts you've logged locally.

## QSO Map

The main map displays your logged contacts as markers on a world map.

### Contact Markers

Each marker represents a station you've contacted. The marker is placed at the station's location based on:

- {{< term "Grid Square" >}} coordinates (if logged)
- {{< term "QTH" >}} data from {{< term "QRZ" >}} lookup
- State/country geolocation (fallback)

Markers are color-coded and sized to indicate density in areas with many contacts.

### Geodesic Arcs

Lines connecting your station to each contacted station follow the great circle (shortest) path over Earth's surface. These arcs show:

- True bearing from your location
- Visual representation of propagation paths
- Distance coverage patterns

Arcs are semi-transparent to prevent clutter in densely-contacted areas.

### Performance Limit

To maintain smooth interaction on large logs, the map defaults to displaying **500 QSOs** maximum. This limit ensures:

- Fast rendering and panning
- Responsive zooming
- Low memory usage

**Show All Toggle:** Tap the "Show All" button to render your entire log on the map. On logs with thousands of contacts, rendering may take a few seconds. The app caches the result for subsequent loads.

## Azimuthal Map

The Azimuthal map provides an azimuthal equidistant projection centered on your station location, rendered using a high-performance Canvas renderer.

### Projection

- **Center point** - Your grid square (configurable)
- **Equidistant** - All distances from center are accurate and proportional
- **True bearing** - Directions from center to any point are correct
- **Canvas-rendered** - Uses Core Graphics for smooth 60fps rendering

### SNR Heatmap

When RBN spot data is available, the azimuthal map can display an SNR heatmap:

- **Color gradient** from blue (weak) through green (moderate) to red (strong)
- **Geographic overlay** showing signal strength by direction
- **Time-windowed** - Shows data from the last 10-30 minutes (configurable)
- **Band-filtered** - Heatmap updates when you change the band filter

### QSO Arcs

Geodesic arcs from your station to contacted stations are drawn as curves on the azimuthal projection:

- **Band-colored** arcs distinguish contacts on different bands
- **Opacity** indicates recency (newer contacts are more opaque)
- **Tap an arc** to see QSO details

### Antenna Patterns

Overlay your antenna's radiation pattern on the azimuthal map:

- **Directional patterns** show the main lobe and nulls
- **Pattern data** loaded from equipment profiles
- **Rotate** to match your antenna's actual bearing
- **Compare** propagation paths against antenna coverage

### Compass

A compass rose overlay shows cardinal directions from your station, helping orient the azimuthal projection to real-world bearings.

## Park Boundaries

### POTA Park Boundaries

POTA park boundaries are rendered as filled polygons on the map:

- **GeoJSON source** - Boundaries loaded from POTA boundary data
- **Polygon with holes** - Properly renders parks that have excluded interior areas (e.g., private land within a national forest)
- **Fill opacity** - Semi-transparent fill to show underlying terrain
- **Boundary color** - Matches the POTA brand green

### Tap to View Park Details

Tap any park boundary polygon to open the park detail sheet showing:

- Park reference and name
- Your activation history at this park
- Top activators leaderboard
- Distance from your current location

### My Parks List

The map includes a **My Parks** layer showing all parks you've activated:

- **Filled polygons** for parks with successful activations (10+ QSOs)
- **Outlined polygons** for parks you've visited but haven't completed an activation
- **QSO count badges** on each park

Toggle this layer from the map layers menu.

## SOTA Summit Pins

SOTA summits appear as mountain-icon pins on the map:

- **Point value** displayed on the pin (1-10 based on altitude)
- **Color coding** - Green for unworked summits, gold for worked summits
- **Altitude label** shown on tap
- **Summit reference** (e.g., W7W/KG-001) in the callout

### Summit Lookup

Tap a SOTA pin to view:

- Summit name and reference
- Altitude and point value
- Your QSO history with this summit
- Recent activations from SOTAwatch

## WWFF References

WWFF nature reserve boundaries appear as a distinct map layer:

- **Green-bordered polygons** showing reserve boundaries
- **WWFF reference** (e.g., KFF-1234) in the callout
- **Activation status** - Worked vs unworked indicator

## Historic Trail Overlays

For parks and areas with historic trails (e.g., Appalachian Trail, Pacific Crest Trail):

- **Trail path** rendered as a dashed line overlay
- **Trail name** shown on long-press
- **Intersection with parks** highlighted where trails pass through POTA parks

## Grid Square Overlay

Toggle the Maidenhead grid square overlay to display grid boundaries on the map:

- **4-character grid squares** shown as a broad grid
- **6-character sub-squares** shown when zoomed in
- **Grid labels** at each cell center
- **Worked grids** highlighted with a fill color
- **Unworked grids** shown as outlines only

This overlay is useful for tracking grid square awards (VUCC, Grid Squares WAS) and planning operations to fill gaps.

## Map Statistics Overlay

A heads-up statistics panel displays key metrics for the visible contacts:

| Metric | Description |
|--------|-------------|
| **QSO Count** | Total contacts displayed on the map |
| **Average Distance** | Mean distance from your station to all contacts |
| **Longest Distance** | Furthest contact ({{< term "DX" >}} record) |
| **States Worked** | Count of unique US states and Canadian provinces |
| **DXCC Entities** | Count of unique countries worked |
| **QSOs/hr Rate** | Average contact rate during the time span |
| **Time Span** | Date range of displayed contacts |

These statistics update in real time as you apply filters.

## Filtering

The map supports multi-dimensional filtering to focus on specific operating conditions.

### Date Range Filter

Set a start and end date to view contacts from a specific period. The filter defaults to your earliest {{< term "QSO" >}} date through the current date.

### Band Filter

Filter by amateur {{< term "band" >}} (e.g., 20m, 40m, 2m).

### Mode Filter

Restrict the map to contacts using a specific {{< term "mode" >}} ({{< term "SSB" >}}, {{< term "CW" >}}, {{< term "FT8" >}}, etc.).

### Park Filter

For {{< term "POTA" >}} activators, filter by park reference (e.g., US-0001) to display only contacts made during that activation.

### Confirmed Filter

Show only QSOs confirmed via {{< term "QRZ" >}} or {{< term "LoTW" >}}. The app displays the **union** of both confirmation sources.

### Active Filter Badges

All active filters are displayed as badges at the top of the map. Tap any badge to remove that filter.

## Individual QSO Toggle

The **Show Individual QSOs** toggle switches between two rendering modes:

### Grid Square Mode (Default)

Contacts are aggregated by grid square. A single marker represents all QSOs within that grid. The marker label shows the QSO count.

### Individual QSO Mode

Every contact is displayed as a small dot marker. Tapping a marker shows that specific QSO's details.

## Activation Maps

{{< term "POTA" >}} activations have dedicated map views accessible from the activation detail screen.

### RST-Based Contact Coloring

On activation maps, QSO markers are color-coded by signal report:

| Color | RST Range | Interpretation |
|-------|-----------|----------------|
| **Green** | 59, 599 | Strong signals |
| **Yellow** | 57-58, 579-589 | Good signals |
| **Red** | <57, <579 | Weak signals |

### Accessing Activation Maps

1. Open the **POTA** tab
2. Tap an activation entry
3. Tap **View Map** in the activation detail view

## QSO Callouts

Tap any contact marker to see a detailed callout overlay with callsign, frequency, mode, RST, equipment, and solar conditions (for POTA activations).

## Rove Session Maps

Rove sessions display numbered park markers, a dashed route line connecting stops in chronological order, and QSO locations overlaid on the route.

## Session Map (MAP Command)

While logging an active session, type `MAP` to view a real-time map of your current QSOs. The map updates live as you log additional contacts and automatically zooms to fit all contacts.

## Weather Radar Overlay (US, Experimental)

Enable **Settings -> Experiments -> Weather Radar** to add a NEXRAD base-reflectivity overlay on top of the Parks & Summits map. A cloud-rain button in the map toolbar toggles the layer on and off; an opacity picker (25 / 50 / 75 / 100 %) sets how dominant the radar reads against the basemap. The overlay pans and zooms in lockstep with park polygons, trail polylines, and pins — there is no separate "radar mode."

Active NWS alerts for the visible area surface as a severity-tinted chip in the corner; tap to open the full alert list with event headline, area, and timeline.

The radar tile feed is Iowa State's Mesonet cache (refreshed roughly every five minutes, no API key required). Coverage is the contiguous US only — Hawaii, Alaska, and outside-US users will see an empty layer.

## See Also

- [Logger](/reference/logger/) - Record contacts and start sessions
- [POTA Activations](/reference/pota/) - Park activation workflow
- [Activity Programs](/reference/activations/) - SOTA summits and WWFF references
- [Home](/reference/dashboard/) - Aggregate statistics and drill-down views
