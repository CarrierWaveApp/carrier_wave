## Watch App (`swift/watch/`)

| File | Purpose |
|------|---------|
| `CarrierWaveWatchApp.swift` | Watch app entry point |
| `ContentView.swift` | Root view switching between idle and active session modes |
| `Views/IdleView.swift` | Idle mode TabView (solar, spots, stats, quick start pages) |
| `Views/SolarView.swift` | Solar conditions gauges (K-index, A-index, SFI) |
| `Views/SpotsListView.swift` | Recent POTA/RBN spots list |
| `Views/StatsView.swift` | Quick stats (streaks, QSO counts) |
| `Views/ActiveSessionView.swift` | Active session display (QSO count, callsign, activation progress) |
| `Views/ActivationProgressRing.swift` | POTA activation progress ring (X/10) |
| `Views/QuickStartView.swift` | Quick session start from Watch |
| `Services/SharedDataReader.swift` | Reads shared data from App Group UserDefaults + shared Codable types |
| `Services/WatchSessionDelegate.swift` | WCSessionDelegate for receiving session updates from iPhone |

