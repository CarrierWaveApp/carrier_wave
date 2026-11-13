# Plan: Standardize Map Renderers

## Problem

9 distinct map rendering contexts across the iOS app duplicate annotation styles, geodesic arc drawing, camera configuration, and map style logic. Changes to map behavior require touching 5+ files.

## Current Inventory

| # | View | Type | Key Content |
|---|------|------|-------------|
| 1 | QSOMapView | `Map()` | Grid polygons, clustered annotations, arcs, filters |
| 2 | ParkSearchMapView | `Map()` + `MapReader` | Park boundary polygons with holes, tap-to-select, dynamic fetch |
| 3 | ActivationMapView | `Map()` | RST pins, rove stops, route line, arcs, share export |
| 4 | SessionMapPanelView | `Map()` | RST pins, rove stops, route line, arcs (phone logger) |
| 5 | SidebarMapView | `Map()` | RST pins, rove stops, route line, arcs (iPad logger) — **near-duplicate of #4** |
| 6 | TimelineMapView | `Map()` | Time-animated QSOs + RBN spots with decay |
| 7 | SpotsMiniMapView | `Map()` | SNR-colored spotter pins, arcs to target |
| 8 | CallsignMapSection | `Map()` / `ThemedMapImage` | Single pin, optional arc |
| 9 | SessionDetailView+Map | `Map()` / `ThemedMapImage` | RST pins + arcs (session header preview) |
| 10 | ClubMapView (ClusteredMapView) | `MKMapView` UIViewRepresentable | Native MKClusterAnnotation |
| — | FlatMapRenderer | CoreGraphics | Equirectangular static image (share cards) |
| — | AzimuthalMapRenderer | CoreGraphics | Azimuthal static image (share cards) |
| — | AzimuthalMapView | SwiftUI Canvas | Polar projection (antenna/spots) |

## What Can Be Unified

### Shared `@MapContentBuilder` Primitives

Extract reusable `MapContent`-returning functions into a single `MapContentBuilders.swift`:

```swift
// 1. QSO annotation pins (RST-colored)
@MapContentBuilder
static func qsoAnnotations(
    for qsos: [some QSORepresentable],
    showArcs: Bool = true,
    myCoordinate: CLLocationCoordinate2D? = nil
) -> some MapContent

// 2. Geodesic arc overlay (used in 8 call sites today)
@MapContentBuilder
static func geodesicArc(
    from: CLLocationCoordinate2D,
    to: CLLocationCoordinate2D,
    color: Color = .white.opacity(0.5),
    lineWidth: CGFloat = 2.5
) -> some MapContent

// 3. "Me" marker
@MapContentBuilder
static func myLocationMarker(
    coordinate: CLLocationCoordinate2D
) -> some MapContent

// 4. Rove stop overlay (numbered markers + dashed route line)
@MapContentBuilder
static func roveStopOverlay(
    stops: [(stop: RoveStop, coordinate: CLLocationCoordinate2D)]
) -> some MapContent
```

### Unified Map Configuration

Extract map style + globe logic into a shared modifier or helper:

```swift
extension View {
    func standardMapStyle(isWideSpan: Bool = false) -> some View
}
```

Today, 4 views independently compute `useGlobeStyle` via `ShareMapStyle.shouldUseGlobe`. One shared helper eliminates this.

### Merge SessionMapPanelView + SidebarMapView

These are functionally identical. Extract a shared `SessionQSOMap` view:

```swift
struct SessionQSOMap: View {
    let sessionQSOs: [QSO]
    let myGrid: String?
    var roveStops: [RoveStop] = []
}
```

Then `SessionMapPanelView` wraps it with a dismiss header, and `SidebarMapView` wraps it with a stats bar. Both become ~20 lines.

### Unify CallsignMapSection + SessionDetailView+Map Preview

Both are read-only "pins + arcs" previews with `ThemedMapImage` fallback. Extract:

```swift
struct QSOPreviewMap: View {
    let coordinates: [CLLocationCoordinate2D]
    let myCoordinate: CLLocationCoordinate2D?
    let labels: [String]  // annotation labels
    var isInteractive: Bool = false
}
```

## What Must Stay Separate (and Why)

| View | Reason |
|------|--------|
| **QSOMapView** | Grid square polygon overlay, filter UI, clustering logic, 1000+ annotation perf management |
| **ParkSearchMapView** | `MapReader` for tap-to-coordinate, dynamic boundary polygon fetch, `MKPolygon` with interior holes, selection state machine |
| **TimelineMapView** | Time-driven animation loop, spot decay/sizing, playback controls — fundamentally different interaction model |
| **ClusteredMapView** | `UIViewRepresentable` required for `MKClusterAnnotation` — SwiftUI `Map` doesn't support native clustering |
| **SpotsMiniMapView** | SNR-based color/size logic unique to spot sources — but could adopt shared arc builder |
| **AzimuthalMapView** | Canvas-based polar projection, not a geographic map |
| **FlatMapRenderer / AzimuthalMapRenderer** | CoreGraphics image renderers for offline share cards |

## Implementation Steps

### Phase 1: Extract shared MapContent builders (low risk)

1. Create `CarrierWave/Views/Map/MapContentBuilders.swift`
2. Move geodesic arc rendering into `MapContentBuilders.geodesicArc(from:to:)`
3. Move RST-colored QSO annotation into `MapContentBuilders.qsoAnnotation(_:coordinate:)`
4. Move "Me" marker into `MapContentBuilders.myLocationMarker(at:)`
5. Move rove stop overlay into `MapContentBuilders.roveStopOverlay(stops:)`
6. Adopt in all 8 call sites that use `ActivationMapHelpers.geodesicSegments` + `ForEach` + `MapPolyline`

### Phase 2: Merge duplicate views (medium risk)

7. Create `SessionQSOMap` shared view
8. Rewrite `SessionMapPanelView` as wrapper (header + `SessionQSOMap`)
9. Rewrite `SidebarMapView` as wrapper (stats bar + `SessionQSOMap`)
10. Create `QSOPreviewMap` shared view
11. Rewrite `CallsignMapSection` to use `QSOPreviewMap`
12. Rewrite `SessionDetailView+Map` to use `QSOPreviewMap`

### Phase 3: Standardize map style configuration (low risk)

13. Create `View` extension `.standardMapStyle(isWideSpan:)` that reads `ShareMapStyle` from `@AppStorage` and applies `.mapStyle()` + globe logic
14. Adopt in all `Map()` views, replacing 4 independent `useGlobeStyle` computed properties

### Phase 4: Adopt shared builders in remaining views (low risk)

15. Refactor `ActivationMapView` to use shared builders for its pin + arc content
16. Refactor `QSOMapView` to use shared builders for its annotation + arc layers
17. Refactor `SpotsMiniMapView` to use shared arc builder
18. Refactor `TimelineMapView` to use shared arc builder

## Result

**Before:** 9 interactive map views, each with inline annotation/arc/style logic
**After:** 5 distinct map views + 4 thin wrappers, all composing from `MapContentBuilders`

| Metric | Before | After |
|--------|--------|-------|
| Distinct map views | 9 | 5 (QSOMap, ParkSearch, Timeline, SpotsMini, ClusteredMap) |
| Thin wrappers | 0 | 4 (SessionMapPanel, SidebarMap, CallsignMap, SessionDetailMap) |
| Geodesic arc implementations | 8 inline `ForEach`+`MapPolyline` | 1 shared builder |
| RST color annotation patterns | 5 inline | 1 shared builder |
| Globe style computations | 4 inline | 1 shared modifier |
| Rove stop overlay implementations | 3 inline | 1 shared builder |

Files touched: ~12. No changes to CoreGraphics renderers, AzimuthalMapView, or ClusteredMapView.
