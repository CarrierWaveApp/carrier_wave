import Charts
import SwiftUI

// MARK: - DashboardView

struct DashboardView: View {
    // MARK: Internal

    @EnvironmentObject var config: ServerConfig

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if isLoading, health == nil, !serverDown {
                        ProgressView("Connecting to server...")
                            .padding(.top, 40)
                    } else if serverDown {
                        serverDownSection
                    } else {
                        if let error {
                            ErrorBanner(message: error)
                        }
                        serverStatusSection
                        countsSection
                        usersSection
                        userGrowthChartSection
                        aggregatorSummarySection
                        if let lastRefresh {
                            Text("Last refreshed \(lastRefresh.formatted(.relative(presentation: .named)))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.bottom)
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Dashboard")
            .refreshable { await loadAll() }
            .task { await loadAll() }
        }
    }

    // MARK: Private

    @State private var health: HealthResponse?
    @State private var challenges: ChallengesListResponse?
    @State private var potaStatus: PotaSyncStatusResponse?
    @State private var boundaryStatus: ParkBoundariesStatusResponse?
    @State private var trailStatus: TrailStatusResponse?
    @State private var spotsResponse: SpotsListResponse?
    @State private var clubs: [ClubAdminResponse]?
    @State private var adminStats: AdminStatsResponse?
    @State private var userCountsByHour: [UserCountByHour]?
    @State private var selectedTimespan: Timespan = .thirtyDays
    @State private var error: String?
    @State private var serverDown = false
    @State private var isLoading = true
    @State private var lastRefresh: Date?

    private var api: APIClient {
        APIClient(config: config)
    }

    // MARK: - Data Loading

    private func loadAll() async {
        isLoading = true
        error = nil
        serverDown = false

        await withTaskGroup(of: Void.self) { group in
            group.addTask { await loadHealth() }
            group.addTask { await loadChallenges() }
            group.addTask { await loadPotaStatus() }
            group.addTask { await loadBoundaryStatus() }
            group.addTask { await loadTrailStatus() }
            group.addTask { await loadClubs() }
            group.addTask { await loadAdminStats() }
            group.addTask { await loadUserCountsByHour() }
        }

        lastRefresh = Date()
        isLoading = false
    }

    private func loadHealth() async {
        do {
            health = try await api.getHealth()
            serverDown = false
        } catch {
            if !error.isCancellation {
                serverDown = true
                self.error = error.localizedDescription
            }
        }
    }

    private func loadChallenges() async {
        challenges = try? await api.getChallenges()
    }

    private func loadPotaStatus() async {
        potaStatus = try? await api.getPotaSyncStatus()
    }

    private func loadBoundaryStatus() async {
        boundaryStatus = try? await api.getParkBoundariesStatus()
    }

    private func loadTrailStatus() async {
        trailStatus = try? await api.getTrailStatus()
    }

    private func loadClubs() async {
        clubs = try? await api.getClubs()
    }

    private func loadAdminStats() async {
        adminStats = try? await api.getAdminStats()
    }

    private func loadUserCountsByHour() async {
        userCountsByHour = try? await api.getUserCountsByHour(days: selectedTimespan.days)
    }
}

// MARK: - DashboardView Sections

private extension DashboardView {
    var serverDownSection: some View {
        VStack(spacing: 16) {
            Spacer().frame(height: 40)
            Image(systemName: "exclamationmark.icloud.fill")
                .font(.system(size: 56))
                .foregroundStyle(.red)
            Text("Server Unreachable").font(.title2.bold())
            Text(config.baseURL)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fontDesign(.monospaced)
            if let error {
                Text(error)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            Button {
                Task { await loadAll() }
            } label: {
                Label("Retry", systemImage: "arrow.clockwise")
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
            .tint(.blue)
            .padding(.top, 8)
        }
    }

    var serverStatusSection: some View {
        VStack(spacing: 12) {
            HStack { Text("Server").font(.headline); Spacer() }
            HStack(spacing: 16) {
                StatusCard(
                    title: "Status",
                    value: health?.status.uppercased() ?? "UNKNOWN",
                    icon: health?.status == "ok" ? "checkmark.circle.fill" : "exclamationmark.triangle.fill",
                    color: health?.status == "ok" ? .green : .red
                )
                StatusCard(title: "Version", value: health?.version ?? "-", icon: "tag", color: .blue)
            }
            HStack {
                Image(systemName: "link").foregroundStyle(.secondary)
                Text(config.baseURL).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                Spacer()
            }
            .padding(.horizontal, 4)
        }
        .cardStyle()
    }

    var countsSection: some View {
        VStack(spacing: 12) {
            HStack { Text("At a Glance").font(.headline); Spacer() }
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                CountCard(title: "Challenges", count: challenges?.total, icon: "trophy.fill", color: .orange)
                CountCard(
                    title: "Active",
                    count: challenges?.challenges.filter(\.isActive).count,
                    icon: "bolt.fill",
                    color: .green
                )
                CountCard(title: "Clubs", count: clubs?.count, icon: "person.3.fill", color: .purple)
                CountCard(
                    title: "Total Members",
                    count: clubs?.reduce(0) { $0 + $1.memberCount },
                    icon: "person.fill",
                    color: .indigo
                )
            }
        }
        .cardStyle()
    }

    var usersSection: some View {
        VStack(spacing: 12) {
            HStack { Text("Users").font(.headline); Spacer() }
            VStack(spacing: 8) {
                CountCard(title: "Total", count: adminStats?.totalUsers, icon: "person.crop.circle.fill", color: .blue)
                CountCard(
                    title: "New in Last 7 Days",
                    count: adminStats?.usersLast7Days,
                    icon: "calendar.badge.plus",
                    color: .green
                )
                CountCard(
                    title: "New in Last 30 Days",
                    count: adminStats?.usersLast30Days,
                    icon: "calendar",
                    color: .teal
                )
            }
        }
        .cardStyle()
    }

    var userGrowthChartSection: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Active Users per Hour").font(.headline)
                Spacer()
                Picker("Timespan", selection: $selectedTimespan) {
                    ForEach(Timespan.allCases) { span in Text(span.label).tag(span) }
                }
                .pickerStyle(.menu)
                .onChange(of: selectedTimespan) { Task { await loadUserCountsByHour() } }
            }
            userGrowthChart
        }
        .cardStyle()
    }

    @ViewBuilder
    var userGrowthChart: some View {
        if let data = userCountsByHour, !data.isEmpty {
            let visibleDomain: TimeInterval = selectedTimespan.scrollWindowDays * 24 * 3_600
            Chart(data) { point in
                LineMark(x: .value("Hour", point.hour), y: .value("Users", point.count))
                    .foregroundStyle(.blue).interpolationMethod(.catmullRom)
                AreaMark(x: .value("Hour", point.hour), y: .value("Users", point.count))
                    .foregroundStyle(.blue.opacity(0.1)).interpolationMethod(.catmullRom)
            }
            .chartXAxis {
                if selectedTimespan == .oneDay {
                    AxisMarks(values: .stride(by: .hour, count: 3)) { _ in
                        AxisGridLine()
                        AxisValueLabel(format: .dateTime.hour())
                    }
                } else if selectedTimespan == .sevenDays {
                    AxisMarks(values: .stride(by: .hour, count: 12)) { _ in
                        AxisGridLine()
                        AxisValueLabel(format: .dateTime.weekday(.abbreviated).hour())
                    }
                } else {
                    AxisMarks(values: .stride(by: .day, count: selectedTimespan.xAxisStrideDays)) { _ in
                        AxisGridLine()
                        AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                    }
                }
            }
            .chartYAxis { AxisMarks { _ in AxisGridLine(); AxisValueLabel() } }
            .chartScrollableAxes(.horizontal)
            .chartXVisibleDomain(length: visibleDomain)
            .chartScrollPosition(initialX: data[data.count - 1].hour)
            .frame(height: 200)
        } else {
            Text("No data available")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(height: 200)
                .frame(maxWidth: .infinity)
        }
    }

    var aggregatorSummarySection: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Aggregators").font(.headline)
                Spacer()
                NavigationLink { AggregatorsView() } label: {
                    Text("Details").font(.subheadline)
                }
            }
            if let pota = potaStatus {
                AggregatorRow(
                    name: "POTA Stats",
                    progress: pota.completionPercentage / 100.0,
                    detail: "\(pota.parksFetched)/\(pota.totalParks) parks"
                )
            }
            if let boundaries = boundaryStatus {
                AggregatorRow(
                    name: "Park Boundaries",
                    progress: Double(boundaries.completionPercentage) / 100.0,
                    detail: "\(boundaries.totalCached)/\(boundaries.totalParks) parks"
                )
            }
            if let trails = trailStatus {
                AggregatorRow(
                    name: "Historic Trails",
                    progress: Double(trails.completionPercentage) / 100.0,
                    detail: "\(trails.totalCached)/\(trails.totalCatalog) trails"
                )
            }
        }
        .cardStyle()
    }
}

// MARK: - Timespan

enum Timespan: String, CaseIterable, Identifiable {
    case oneDay = "1d"
    case sevenDays = "7d"
    case thirtyDays = "30d"
    case ninetyDays = "90d"
    case oneYear = "1y"

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
        case .oneYear: "1 Year"
        }
    }

    var days: Int {
        switch self {
        case .oneDay: 1
        case .sevenDays: 7
        case .thirtyDays: 30
        case .ninetyDays: 90
        case .oneYear: 365
        }
    }

    /// How many days are visible at once before scrolling is needed.
    var scrollWindowDays: Double {
        switch self {
        case .oneDay: 1
        case .sevenDays: 7
        case .thirtyDays: 7
        case .ninetyDays: 14
        case .oneYear: 30
        }
    }

    var xAxisStrideDays: Int {
        switch self {
        case .oneDay: 1
        case .sevenDays: 1
        case .thirtyDays: 7
        case .ninetyDays: 14
        case .oneYear: 30
        }
    }
}

// MARK: - StatusCard

struct StatusCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)
            Text(value)
                .font(.headline)
                .fontDesign(.monospaced)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(color.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - CountCard

struct CountCard: View {
    let title: String
    let count: Int?
    let icon: String
    let color: Color

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(count.map { "\($0)" } ?? "-")
                    .font(.title3.bold())
                    .fontDesign(.monospaced)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(12)
        .background(color.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - AggregatorRow

struct AggregatorRow: View {
    let name: String
    let progress: Double
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(name)
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: min(progress, 1.0))
                .tint(progress >= 1.0 ? .green : .blue)
        }
    }
}

// MARK: - ErrorBanner

struct ErrorBanner: View {
    let message: String

    var body: some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
            Text(message)
                .font(.subheadline)
            Spacer()
        }
        .padding()
        .background(.red.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Card Style

extension View {
    func cardStyle() -> some View {
        padding()
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}
