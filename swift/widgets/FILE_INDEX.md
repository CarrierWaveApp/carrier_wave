## Widget Extension (`swift/widgets/`)

| File | Purpose |
|------|---------|
| `CarrierWaveWidgetBundle.swift` | WidgetBundle entry point registering all widgets and Live Activity |
| `WidgetDataReader.swift` | Reads shared data from App Group UserDefaults + shared Codable types |
| `SolarWidget.swift` | Solar conditions widget (K-index, SFI, A-index) - fetches directly from HamQSL |
| `SolarWidgetTypes.swift` | Solar widget types: SolarBand, SolarMetric, SolarWidgetIntent, BandCondition, CircularMetricGauge |
| `SolarWidgetAccessoryViews.swift` | Lock screen accessory views: circular, rectangular, inline solar widgets |
| `SolarWidgetSpaceWeather.swift` | Space-storm summary row + impact-color helper used by Solar widget variants |
| `StatsWidget.swift` | Configurable streaks/counts widget with AppIntent configuration |
| `SpotsWidget.swift` | POTA/SOTA/RBN spots widget views with activity icons, band, mode, park/summit refs |
| `SpotsFetcher.swift` | Spots widget API fetcher for POTA, SOTA, and RBN spots |
| `NeedsWidget.swift` | Home screen widget showing spots matching operator needs |
| `SpotsWidgetTypes.swift` | Spots widget filter enums (source, band, mode), WidgetSpot model with activity metadata |
| `ActiveSessionWidget.swift` | Active logging session widget showing QSO count and session info |
| `HuntWidget.swift` | Hunter widget (small) — propagation rating, K/A/SFI gauges, band conditions, active spot count; deep links to Sessions Hunt panel |
| `LiveActivityAttributes.swift` | ActivityKit attributes mirror for widget extension compilation |
| `LiveActivityView.swift` | Live Activity views: lock screen, Dynamic Island compact/expanded/minimal |
| `SatellitePassActivityAttributes.swift` | ActivityKit attributes mirror for the satellite pass countdown (keep in sync with CarrierWave/Services/) |
| `SatellitePassLiveActivityView.swift` | Satellite pass-countdown Live Activity: date-driven AOS timer (lock screen + Dynamic Island), no mid-pass state updates, dims after LOS via staleDate |
| `CarrierWaveWidgets.entitlements` | App Group entitlement for shared data access |

