// Weather Alerts Banner
//
// Compact severity chip that opens a List-based sheet of active NWS
// alerts. Mirrors the Space Weather chip / sheet pattern used in the
// session controls bar.

import SwiftUI

// MARK: - WeatherAlertsBanner

/// Compact tappable chip summarising active NWS alerts (worst severity + count).
/// Renders nothing when there are no alerts. Tapping opens `WeatherAlertsSheet`.
struct WeatherAlertsBanner: View {
    // MARK: Internal

    let alerts: [NWSAlert]

    var body: some View {
        if let worst = alerts.first {
            Button {
                showingSheet = true
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: chipIcon(for: worst.severity))
                        .font(.system(size: 9))
                    Text(chipLabel)
                        .font(.caption2.weight(.semibold))
                }
                .foregroundStyle(chipForeground(for: worst.severity))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(chipBackground(for: worst.severity))
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(
                "\(alerts.count) active weather alert\(alerts.count == 1 ? "" : "s")"
            )
            .sheet(isPresented: $showingSheet) {
                WeatherAlertsSheet(alerts: alerts) { showingSheet = false }
            }
        }
    }

    // MARK: Private

    @State private var showingSheet = false

    private var chipLabel: String {
        if alerts.count == 1 {
            return alerts[0].event.split(separator: " ").first.map(String.init) ?? "Alert"
        }
        return "\(alerts.count) Alerts"
    }

    private func chipIcon(for severity: NWSAlertSeverity) -> String {
        switch severity {
        case .extreme,
             .severe: "exclamationmark.triangle.fill"
        case .moderate: "exclamationmark.circle.fill"
        case .minor,
             .unknown: "info.circle.fill"
        }
    }

    private func chipForeground(for severity: NWSAlertSeverity) -> Color {
        switch severity {
        case .extreme,
             .severe: .red
        case .moderate: .orange
        case .minor: .blue
        case .unknown: .secondary
        }
    }

    private func chipBackground(for severity: NWSAlertSeverity) -> Color {
        switch severity {
        case .extreme,
             .severe: Color.red.opacity(0.15)
        case .moderate: Color.orange.opacity(0.15)
        case .minor: Color.blue.opacity(0.15)
        case .unknown: Color.gray.opacity(0.15)
        }
    }
}

// MARK: - WeatherAlertsSheet

/// Sheet content shown when tapping `WeatherAlertsBanner`. Modeled on
/// `SpaceWeatherBannerView` — a tinted impact summary header followed
/// by a list of active alerts.
struct WeatherAlertsSheet: View {
    // MARK: Internal

    let alerts: [NWSAlert]
    var onDismiss: (() -> Void)?

    var body: some View {
        NavigationStack {
            List {
                if let worst = alerts.first {
                    impactSection(worst: worst, count: alerts.count)
                }
                eventsSection(alerts)
            }
            .navigationTitle("Active Alerts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if let onDismiss {
                        Button("Done", action: onDismiss)
                    }
                }
            }
        }
    }

    // MARK: Private

    private func impactSection(worst: NWSAlert, count: Int) -> some View {
        Section {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(bannerColor(worst.severity))
                    .font(.title3)

                VStack(alignment: .leading, spacing: 2) {
                    Text(impactLabel(worst.severity))
                        .font(.headline)
                    Text(impactDetail(worst.severity, count: count))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .listRowBackground(bannerColor(worst.severity).opacity(0.08))
        }
    }

    private func eventsSection(_ alerts: [NWSAlert]) -> some View {
        Section("Active Alerts") {
            ForEach(alerts) { alert in
                alertRow(alert)
            }
        }
    }

    private func alertRow(_ alert: NWSAlert) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Image(systemName: rowIcon(alert.severity))
                    .font(.system(size: 16))
                    .foregroundStyle(impactColor(alert.severity))
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(alert.event)
                        .font(.subheadline)
                        .fontWeight(.medium)

                    if let headline = alert.headline, !headline.isEmpty {
                        Text(headline)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                    }

                    if let area = alert.areaDescription, !area.isEmpty {
                        Text(area)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(2)
                    }
                }

                Spacer()
            }

            if let start = alert.sent, let expiry = alert.expires {
                EventTimelineBar(
                    startDate: start,
                    expiryDate: expiry,
                    accentColor: impactColor(alert.severity)
                )
                .padding(.leading, 38)
            }
        }
        .padding(.vertical, 2)
    }

    private func rowIcon(_ severity: NWSAlertSeverity) -> String {
        switch severity {
        case .extreme,
             .severe: "exclamationmark.triangle.fill"
        case .moderate: "exclamationmark.circle.fill"
        case .minor,
             .unknown: "info.circle.fill"
        }
    }

    private func bannerColor(_ severity: NWSAlertSeverity) -> Color {
        switch severity {
        case .extreme,
             .severe: .red
        case .moderate: .orange
        default: .yellow
        }
    }

    private func impactColor(_ severity: NWSAlertSeverity) -> Color {
        switch severity {
        case .extreme,
             .severe: .red
        case .moderate: .orange
        case .minor: .yellow
        case .unknown: .secondary
        }
    }

    private func impactLabel(_ severity: NWSAlertSeverity) -> String {
        switch severity {
        case .extreme: "Extreme Weather"
        case .severe: "Severe Weather"
        case .moderate: "Active Weather"
        default: "Weather Advisory"
        }
    }

    private func impactDetail(_ severity: NWSAlertSeverity, count: Int) -> String {
        let plural = count == 1 ? "alert" : "alerts"
        return switch severity {
        case .extreme: "\(count) extreme \(plural) — take action"
        case .severe: "\(count) severe \(plural) in effect"
        case .moderate: "\(count) \(plural) in effect"
        default: "\(count) \(plural) for your area"
        }
    }
}

#Preview("Chip") {
    WeatherAlertsBanner(alerts: [
        NWSAlert(
            id: "1",
            event: "Severe Thunderstorm Warning",
            headline: "Severe thunderstorm capable of 60 mph winds and quarter-size hail.",
            severity: .severe,
            areaDescription: "Travis County, TX",
            sent: Date(),
            expires: Date().addingTimeInterval(3_600)
        ),
        NWSAlert(
            id: "2",
            event: "Flood Watch",
            headline: "Flood watch in effect through tonight.",
            severity: .moderate,
            areaDescription: "Central Texas",
            sent: Date().addingTimeInterval(-1_800),
            expires: Date().addingTimeInterval(7_200)
        ),
    ])
    .padding()
}

#Preview("Sheet") {
    WeatherAlertsSheet(alerts: [
        NWSAlert(
            id: "1",
            event: "Severe Thunderstorm Warning",
            headline: "Severe thunderstorm capable of 60 mph winds and quarter-size hail.",
            severity: .severe,
            areaDescription: "Travis County, TX",
            sent: Date(),
            expires: Date().addingTimeInterval(3_600)
        ),
        NWSAlert(
            id: "2",
            event: "Flood Watch",
            headline: "Flood watch in effect through tonight.",
            severity: .moderate,
            areaDescription: "Central Texas",
            sent: Date().addingTimeInterval(-1_800),
            expires: Date().addingTimeInterval(7_200)
        ),
    ]) {}
}
