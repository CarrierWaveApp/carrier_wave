// Weather Panel View for Logger
//
// Displays current weather conditions from NOAA
// based on user's location or grid square.

import CarrierWaveData
import CoreLocation
import SwiftUI

// MARK: - WeatherPanelView

struct WeatherPanelView: View {
    // MARK: Internal

    let grid: String?
    let onDismiss: () -> Void

    var body: some View {
        let _ = useMetricUnits // Trigger re-render when unit preference changes
        VStack(spacing: 0) {
            header
            Divider()

            if isLoading {
                loadingView
            } else if let error = errorMessage {
                errorView(error)
            } else if let conditions {
                conditionsView(conditions)
            }
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.1), radius: 8, y: 2)
        .task {
            await loadData()
        }
    }

    // MARK: Private

    @AppStorage("useMetricUnits") private var useMetricUnits = false

    @State private var conditions: WeatherConditions?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var locationManager = LocationManager()

    private let noaaClient = NOAAClient()

    // MARK: - Header

    private var header: some View {
        HStack {
            Image(systemName: "cloud.sun.fill")
                .foregroundStyle(.cyan)

            Text("Weather")
                .font(.headline)

            Spacer()

            if let grid, !grid.isEmpty {
                Text(grid)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button {
                Task { await loadData() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 14))
            }
            .buttonStyle(.borderless)

            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
        }
        .padding()
    }

    // MARK: - Content Views

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Loading weather data...")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 120)
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "cloud.bolt")
                .font(.title2)
                .foregroundStyle(.orange)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Retry") {
                Task { await loadData() }
            }
            .font(.caption)
            .buttonStyle(.bordered)
        }
        .padding()
        .frame(maxWidth: .infinity, minHeight: 120)
    }

    private func conditionsView(_ conditions: WeatherConditions) -> some View {
        VStack(spacing: 16) {
            // Main temperature and condition
            HStack(spacing: 20) {
                // Temperature
                VStack(spacing: 4) {
                    Text(UnitFormatter.temperature(conditions.temperature))
                        .font(.system(size: 48, weight: .light))

                    Text(UnitFormatter.temperatureSecondary(conditions.temperature))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Divider()
                    .frame(height: 60)

                // Condition
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        weatherIcon(conditions.description)
                        Text(conditions.description)
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }

                    if let wind = conditions.formattedWind {
                        HStack(spacing: 4) {
                            Image(systemName: "wind")
                                .font(.caption)
                            Text(wind)
                                .font(.caption)
                        }
                        .foregroundStyle(.secondary)
                    }

                    if let humidity = conditions.humidity {
                        HStack(spacing: 4) {
                            Image(systemName: "humidity")
                                .font(.caption)
                            Text("\(humidity)%")
                                .font(.caption)
                        }
                        .foregroundStyle(.secondary)
                    }
                }
            }

            // Operating conditions for radio
            operatingConditions(conditions)

            // Last updated
            Text("Updated: \(conditions.timestamp.formatted(date: .omitted, time: .shortened))")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding()
    }

    private func operatingConditions(_ conditions: WeatherConditions) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Operating Conditions")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)

            HStack(spacing: 16) {
                conditionIndicator(
                    title: "Outdoor",
                    isGood: isGoodForOutdoor(conditions),
                    icon: "figure.hiking"
                )

                conditionIndicator(
                    title: "Antenna",
                    isGood: isGoodForAntenna(conditions),
                    icon: "antenna.radiowaves.left.and.right"
                )

                conditionIndicator(
                    title: "Equipment",
                    isGood: isGoodForEquipment(conditions),
                    icon: "radio"
                )
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 12)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func conditionIndicator(title: String, isGood: Bool, icon: String) -> some View {
        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .fill(isGood ? Color.green.opacity(0.2) : Color.orange.opacity(0.2))
                    .frame(width: 36, height: 36)

                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundStyle(isGood ? .green : .orange)
            }

            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func weatherIcon(_ description: String) -> some View {
        let iconName: String
        let color: Color

        let desc = description.lowercased()

        if desc.contains("sunny") || desc.contains("clear") {
            iconName = "sun.max.fill"
            color = .yellow
        } else if desc.contains("partly") && desc.contains("cloud") {
            iconName = "cloud.sun.fill"
            color = .cyan
        } else if desc.contains("cloud") {
            iconName = "cloud.fill"
            color = .gray
        } else if desc.contains("rain") || desc.contains("shower") {
            iconName = "cloud.rain.fill"
            color = .blue
        } else if desc.contains("thunder") || desc.contains("storm") {
            iconName = "cloud.bolt.fill"
            color = .purple
        } else if desc.contains("snow") {
            iconName = "snowflake"
            color = .cyan
        } else if desc.contains("fog") || desc.contains("mist") {
            iconName = "cloud.fog.fill"
            color = .gray
        } else if desc.contains("wind") {
            iconName = "wind"
            color = .teal
        } else {
            iconName = "cloud.fill"
            color = .gray
        }

        return Image(systemName: iconName)
            .foregroundStyle(color)
    }

    // MARK: - Condition Checks

    private func isGoodForOutdoor(_ conditions: WeatherConditions) -> Bool {
        let desc = conditions.description.lowercased()
        let noRain = !desc.contains("rain") && !desc.contains("storm") && !desc.contains("thunder")
        let tempOK = conditions.temperature > 32 && conditions.temperature < 95
        return noRain && tempOK
    }

    private func isGoodForAntenna(_ conditions: WeatherConditions) -> Bool {
        let desc = conditions.description.lowercased()
        let noStorm = !desc.contains("thunder") && !desc.contains("storm")
        let windOK = (conditions.windSpeed ?? 0) < 25
        return noStorm && windOK
    }

    private func isGoodForEquipment(_ conditions: WeatherConditions) -> Bool {
        let humidity = conditions.humidity ?? 50
        let tempOK = conditions.temperature > 40 && conditions.temperature < 85
        return humidity < 80 && tempOK
    }

    // MARK: - Data Loading

    private func loadData() async {
        isLoading = true
        errorMessage = nil

        do {
            // Try grid first if provided
            if let grid, !grid.isEmpty {
                conditions = try await noaaClient.fetchWeather(grid: grid)
                isLoading = false
                return
            }

            // Fall back to current location
            locationManager.requestLocation()

            // Wait for location (with timeout)
            for _ in 0 ..< 20 {
                if let location = locationManager.location {
                    conditions = try await noaaClient.fetchWeather(
                        latitude: location.coordinate.latitude,
                        longitude: location.coordinate.longitude
                    )
                    isLoading = false
                    return
                }

                if locationManager.authorizationStatus == .denied {
                    errorMessage = "Location access denied. Set grid in settings."
                    isLoading = false
                    return
                }

                try? await Task.sleep(nanoseconds: 250_000_000)
            }

            errorMessage = "Could not determine location"
            isLoading = false
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }
}

// MARK: - LocationManager

@Observable
private class LocationManager: NSObject, CLLocationManagerDelegate {
    // MARK: Lifecycle

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    // MARK: Internal

    var location: CLLocation?
    var authorizationStatus: CLAuthorizationStatus = .notDetermined

    func requestLocation() {
        manager.requestWhenInUseAuthorization()
        manager.requestLocation()
    }

    nonisolated func locationManager(
        _ manager: CLLocationManager,
        didUpdateLocations locations: [CLLocation]
    ) {
        Task { @MainActor in
            self.location = locations.last
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Silently handle location errors
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.authorizationStatus = status
        }
    }

    // MARK: Private

    private let manager = CLLocationManager()
}

#Preview {
    WeatherPanelView(grid: "FN31pr") {}
        .padding()
}
