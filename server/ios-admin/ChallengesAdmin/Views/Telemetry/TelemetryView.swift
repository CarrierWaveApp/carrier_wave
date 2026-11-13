import Charts
import SwiftUI

// MARK: - TelemetryView

struct TelemetryView: View {
    // MARK: Internal

    @EnvironmentObject var config: ServerConfig

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if isLoading, summary == nil {
                        ProgressView("Loading telemetry...")
                            .padding(.top, 40)
                    } else {
                        if let error {
                            ErrorBanner(message: error)
                        }

                        filterSection

                        if let summary {
                            if summary.totalErrors == 0 {
                                noErrorsSection
                            } else {
                                overviewSection(summary)
                                trendChartSection(summary)
                                byServiceSection(summary)
                                byCategorySection(summary)
                                recentErrorsSection(summary)
                            }
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Upload Errors")
            .refreshable { await load() }
            .task { await load() }
        }
    }

    // MARK: Private

    @State private var summary: TelemetrySummaryResponse?
    @State private var selectedDays: TelemetryTimespan = .sevenDays
    @State private var serviceFilter: String?
    @State private var categoryFilter: String?
    @State private var error: String?
    @State private var isLoading = true

    private var api: APIClient {
        APIClient(config: config)
    }

    private func load() async {
        isLoading = true
        error = nil
        do {
            summary = try await api.getTelemetrySummary(
                days: selectedDays.days,
                service: serviceFilter,
                category: categoryFilter
            )
        } catch {
            if !error.isCancellation {
                self.error = error.localizedDescription
            }
        }
        isLoading = false
    }
}

// MARK: - TelemetryView Sections

private extension TelemetryView {
    var filterSection: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Time Range").font(.headline)
                Spacer()
                Picker("Timespan", selection: $selectedDays) {
                    ForEach(TelemetryTimespan.allCases) { span in Text(span.label).tag(span) }
                }
                .pickerStyle(.menu)
                .onChange(of: selectedDays) { Task { await load() } }
            }
            HStack(spacing: 12) {
                if serviceFilter != nil {
                    Button {
                        serviceFilter = nil; Task { await load() }
                    } label: {
                        Label(serviceFilter!.uppercased(), systemImage: "xmark.circle.fill").font(.caption)
                    }
                    .buttonStyle(.bordered).tint(.blue)
                }
                if categoryFilter != nil {
                    Button {
                        categoryFilter = nil; Task { await load() }
                    } label: {
                        Label(categoryDisplayName(categoryFilter!), systemImage: "xmark.circle.fill").font(.caption)
                    }
                    .buttonStyle(.bordered).tint(.purple)
                }
                if serviceFilter != nil || categoryFilter != nil {
                    Spacer()
                }
            }
        }
        .cardStyle()
    }

    var noErrorsSection: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill").font(.system(size: 48)).foregroundStyle(.green)
            Text("No Upload Errors").font(.title3.bold())
            Text("No errors reported in the last \(selectedDays.label.lowercased()).")
                .font(.subheadline).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 40).cardStyle()
    }

    func overviewSection(_ summary: TelemetrySummaryResponse) -> some View {
        VStack(spacing: 12) {
            HStack { Text("Overview").font(.headline); Spacer() }
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                TelemetryStatCard(title: "Errors", value: "\(summary.totalErrors)",
                                  icon: "exclamationmark.triangle.fill", color: .red)
                TelemetryStatCard(title: "QSOs Affected", value: "\(summary.totalAffectedQsos)",
                                  icon: "antenna.radiowaves.left.and.right", color: .orange)
                TelemetryStatCard(title: "Users", value: "\(summary.uniqueCallsigns)",
                                  icon: "person.2.fill", color: .blue)
            }
        }
        .cardStyle()
    }

    func trendChartSection(_ summary: TelemetrySummaryResponse) -> some View {
        VStack(spacing: 12) {
            HStack { Text("Daily Trend").font(.headline); Spacer() }
            if summary.dailyTrend.isEmpty {
                Text("No data for this period").font(.subheadline).foregroundStyle(.secondary)
                    .frame(height: 180).frame(maxWidth: .infinity)
            } else {
                Chart(summary.dailyTrend) { point in
                    BarMark(x: .value("Date", point.date), y: .value("Errors", point.errorCount))
                        .foregroundStyle(.red.opacity(0.7))
                }
                .chartYAxis { AxisMarks { _ in AxisGridLine(); AxisValueLabel() } }
                .frame(height: 180)
            }
        }
        .cardStyle()
    }

    func byServiceSection(_ summary: TelemetrySummaryResponse) -> some View {
        VStack(spacing: 12) {
            HStack { Text("By Service").font(.headline); Spacer() }
            ForEach(summary.byService) { item in
                Button {
                    serviceFilter = item.service; Task { await load() }
                } label: {
                    HStack {
                        Text(item.service.uppercased()).font(.subheadline.weight(.medium)).fontDesign(.monospaced)
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("\(item.errorCount) errors").font(.subheadline.bold())
                            Text("\(item.affectedQsos) QSOs").font(.caption).foregroundStyle(.secondary)
                        }
                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
                if item.id != summary.byService.last?.id {
                    Divider()
                }
            }
        }
        .cardStyle()
    }

    func byCategorySection(_ summary: TelemetrySummaryResponse) -> some View {
        VStack(spacing: 12) {
            HStack { Text("By Category").font(.headline); Spacer() }
            ForEach(summary.byCategory) { item in
                Button {
                    categoryFilter = item.category; Task { await load() }
                } label: {
                    HStack {
                        Image(systemName: categoryIcon(item.category))
                            .foregroundStyle(categoryColor(item.category)).frame(width: 24)
                        Text(categoryDisplayName(item.category)).font(.subheadline.weight(.medium))
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("\(item.errorCount)").font(.subheadline.bold())
                            Text("\(item.affectedQsos) QSOs").font(.caption).foregroundStyle(.secondary)
                        }
                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
                if item.id != summary.byCategory.last?.id {
                    Divider()
                }
            }
        }
        .cardStyle()
    }

    func recentErrorsSection(_ summary: TelemetrySummaryResponse) -> some View {
        VStack(spacing: 12) {
            HStack {
                Text("Recent Errors").font(.headline)
                Spacer()
                Text("\(summary.recentErrors.count) shown").font(.caption).foregroundStyle(.secondary)
            }
            ForEach(summary.recentErrors) { error in
                recentErrorRow(error)
                if error.id != summary.recentErrors.last?.id {
                    Divider()
                }
            }
        }
        .cardStyle()
    }

    func recentErrorRow(_ error: RecentError) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(error.service.uppercased())
                    .font(.caption.bold()).fontDesign(.monospaced)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(.blue.opacity(0.15)).clipShape(RoundedRectangle(cornerRadius: 4))
                Text(categoryDisplayName(error.category))
                    .font(.caption.bold())
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(categoryColor(error.category).opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                if error.isTransient {
                    Text("TRANSIENT")
                        .font(.caption2.bold()).foregroundStyle(.secondary)
                        .padding(.horizontal, 4).padding(.vertical, 1)
                        .background(.secondary.opacity(0.1)).clipShape(RoundedRectangle(cornerRadius: 3))
                }
                Spacer()
            }
            HStack {
                Text(error.callsign).font(.caption).fontDesign(.monospaced)
                Text("v\(error.appVersion)").font(.caption).foregroundStyle(.secondary)
                Text("iOS \(error.osVersion)").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text("\(error.affectedCount) QSO\(error.affectedCount == 1 ? "" : "s")").font(.caption.bold())
            }
            Text(error.createdAt.formatted(.relative(presentation: .named))).font(.caption2).foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }

    func categoryDisplayName(_ category: String) -> String {
        switch category {
        case "authentication": "Authentication"
        case "validation": "Validation"
        case "rate_limited": "Rate Limited"
        case "maintenance": "Maintenance"
        case "network_timeout": "Timeout"
        case "network_offline": "Offline"
        case "server_error": "Server Error"
        case "rejected": "Rejected"
        case "subscription_required": "Subscription"
        default: category.capitalized
        }
    }

    func categoryIcon(_ category: String) -> String {
        switch category {
        case "authentication": "key.fill"
        case "validation": "exclamationmark.circle.fill"
        case "rate_limited": "gauge.with.needle.fill"
        case "maintenance": "wrench.fill"
        case "network_timeout": "clock.fill"
        case "network_offline": "wifi.slash"
        case "server_error": "server.rack"
        case "rejected": "xmark.circle.fill"
        case "subscription_required": "creditcard.fill"
        default: "questionmark.circle.fill"
        }
    }

    func categoryColor(_ category: String) -> Color {
        switch category {
        case "authentication": .red
        case "validation": .orange
        case "rate_limited": .yellow
        case "maintenance": .blue
        case "network_timeout",
             "network_offline": .gray
        case "server_error": .red
        case "rejected": .purple
        case "subscription_required": .indigo
        default: .secondary
        }
    }
}

// MARK: - TelemetryTimespan

enum TelemetryTimespan: String, CaseIterable, Identifiable {
    case oneDay = "1d"
    case sevenDays = "7d"
    case thirtyDays = "30d"
    case ninetyDays = "90d"

    // MARK: Internal

    var id: String {
        rawValue
    }

    var label: String {
        switch self {
        case .oneDay: "24 Hours"
        case .sevenDays: "7 Days"
        case .thirtyDays: "30 Days"
        case .ninetyDays: "90 Days"
        }
    }

    var days: Int {
        switch self {
        case .oneDay: 1
        case .sevenDays: 7
        case .thirtyDays: 30
        case .ninetyDays: 90
        }
    }
}

// MARK: - TelemetryStatCard

struct TelemetryStatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)
            Text(value)
                .font(.title3.bold())
                .fontDesign(.monospaced)
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(color.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
