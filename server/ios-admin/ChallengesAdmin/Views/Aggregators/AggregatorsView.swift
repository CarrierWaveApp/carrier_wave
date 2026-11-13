import SwiftUI

// MARK: - AggregatorsView

struct AggregatorsView: View {
    // MARK: Internal

    @EnvironmentObject var config: ServerConfig

    var body: some View {
        NavigationStack {
            List {
                if let error {
                    Section {
                        ErrorBanner(message: error)
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }

                if let pota = potaStatus {
                    potaSection(pota)
                }

                if let boundaries = boundaryStatus {
                    boundariesSection(boundaries)
                }

                if let trails = trailStatus {
                    trailsSection(trails)
                }

                spotAggregatorSection

                rbnProxySection

                if let programs {
                    programsSection(programs)
                }
            }
            .navigationTitle("Aggregators")
            .refreshable { await loadAll() }
            .task { await loadAll() }
            .overlay {
                if isLoading, potaStatus == nil {
                    ProgressView()
                }
            }
        }
    }

    // MARK: Private

    @State private var potaStatus: PotaSyncStatusResponse?
    @State private var boundaryStatus: ParkBoundariesStatusResponse?
    @State private var trailStatus: TrailStatusResponse?
    @State private var programs: ProgramListResponse?
    @State private var health: HealthResponse?
    @State private var error: String?
    @State private var isLoading = true

    private var api: APIClient {
        APIClient(config: config)
    }

    // MARK: - Loading

    private func loadAll() async {
        isLoading = true
        error = nil

        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                do {
                    potaStatus = try await api.getPotaSyncStatus()
                } catch {
                    if !error.isCancellation {
                        self.error = error.localizedDescription
                    }
                }
            }
            group.addTask {
                do {
                    boundaryStatus = try await api.getParkBoundariesStatus()
                } catch {
                    if !error.isCancellation, self.error == nil {
                        self.error = error.localizedDescription
                    }
                }
            }
            group.addTask {
                do {
                    trailStatus = try await api.getTrailStatus()
                } catch {
                    if !error.isCancellation, self.error == nil {
                        self.error = error.localizedDescription
                    }
                }
            }
            group.addTask {
                do { programs = try await api.getPrograms() } catch {}
            }
            group.addTask {
                do { health = try await api.getHealth() } catch {}
            }
        }

        isLoading = false
    }
}

// MARK: - AggregatorsView Sections

private extension AggregatorsView {
    // MARK: - Spot Aggregators

    var spotAggregatorSection: some View {
        Section {
            SpotAggregatorRow(name: "POTA Spots", icon: "tree", interval: "60s", source: "api.pota.app")
            SpotAggregatorRow(name: "SOTA Spots", icon: "mountain.2", interval: "90s", source: "api2.sota.org.uk")
            SpotAggregatorRow(name: "TTL Cleanup", icon: "trash", interval: "120s", source: "Removes expired spots")
        } header: {
            Label("Spot Aggregators", systemImage: "dot.radiowaves.left.and.right")
        } footer: {
            Text("Spot aggregators run continuously when enabled in server config.")
        }
    }

    // MARK: - RBN Proxy

    @ViewBuilder
    var rbnProxySection: some View {
        if let rbn = health?.rbn {
            Section {
                LabeledContent("Status") {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(rbn.connected ? .green : .red)
                            .frame(width: 8, height: 8)
                        Text(rbn.connected ? "Connected" : "Disconnected")
                            .foregroundStyle(rbn.connected ? .green : .red)
                    }
                }
                LabeledContent("Spots in Store") {
                    Text("\(rbn.spotsInStore)").fontDesign(.monospaced)
                }
                LabeledContent("Spots/min") {
                    Text(String(format: "%.1f", rbn.spotsPerMinute)).fontDesign(.monospaced)
                }
                if let oldest = rbn.oldestSpot {
                    LabeledContent("Oldest Spot") {
                        Text(oldest.formatted(.relative(presentation: .named))).foregroundStyle(.secondary)
                    }
                }
            } header: {
                Label("RBN Proxy", systemImage: "antenna.radiowaves.left.and.right")
            }
        }
    }

    // MARK: - POTA Stats

    func potaSection(_ pota: PotaSyncStatusResponse) -> some View {
        Section {
            LabeledContent("Completion") {
                Text(String(format: "%.1f%%", pota.completionPercentage))
                    .fontDesign(.monospaced)
                    .foregroundStyle(pota.completionPercentage >= 100 ? .green : .primary)
            }
            ProgressView(value: min(pota.completionPercentage / 100.0, 1.0))
                .tint(pota.completionPercentage >= 100 ? .green : .blue)
            LabeledContent("Total Parks") {
                Text("\(pota.totalParks)").fontDesign(.monospaced)
            }
            LabeledContent("Fetched") {
                Text("\(pota.parksFetched)").fontDesign(.monospaced).foregroundStyle(.green)
            }
            LabeledContent("Remaining") {
                Text("\(pota.parksPending)")
                    .fontDesign(.monospaced)
                    .foregroundStyle(pota.parksPending > 0 ? .orange : .green)
            }
            if let oldest = pota.oldestFetch {
                LabeledContent("Oldest Fetch") {
                    Text(oldest.formatted(.relative(presentation: .named))).foregroundStyle(.secondary)
                }
            }
            if let newest = pota.newestFetch {
                LabeledContent("Newest Fetch") {
                    Text(newest.formatted(.relative(presentation: .named))).foregroundStyle(.secondary)
                }
            }
        } header: {
            Label("POTA Stats Aggregator", systemImage: "tree.fill")
        }
    }

    // MARK: - Park Boundaries

    func boundariesSection(_ boundaries: ParkBoundariesStatusResponse) -> some View {
        Section {
            LabeledContent("Completion") {
                Text("\(boundaries.completionPercentage)%")
                    .fontDesign(.monospaced)
                    .foregroundStyle(boundaries.completionPercentage >= 100 ? .green : .primary)
            }
            ProgressView(value: min(Double(boundaries.completionPercentage) / 100.0, 1.0))
                .tint(boundaries.completionPercentage >= 100 ? .green : .blue)
            LabeledContent("Total Parks") {
                Text("\(boundaries.totalParks)").fontDesign(.monospaced)
            }
            boundariesCountryRows(boundaries)
            boundariesMatchRows(boundaries)
        } header: {
            Label("Park Boundaries Aggregator", systemImage: "map.fill")
        }
    }

    @ViewBuilder
    func boundariesCountryRows(_ boundaries: ParkBoundariesStatusResponse) -> some View {
        LabeledContent("US Parks") {
            Text("\(boundaries.byCountry.us.totalParks)").fontDesign(.monospaced)
        }
        LabeledContent("UK Parks") {
            Text("\(boundaries.byCountry.uk.totalParks)").fontDesign(.monospaced)
        }
        LabeledContent("Italian Parks") {
            Text("\(boundaries.byCountry.it.totalParks)").fontDesign(.monospaced)
        }
        LabeledContent("Polish Parks") {
            Text("\(boundaries.byCountry.pl.totalParks)").fontDesign(.monospaced)
        }
        LabeledContent("Cached") {
            Text("\(boundaries.totalCached)").fontDesign(.monospaced).foregroundStyle(.green)
        }
        LabeledContent("Unfetched") {
            Text("\(boundaries.unfetched)")
                .fontDesign(.monospaced)
                .foregroundStyle(boundaries.unfetched > 0 ? .orange : .green)
        }
    }

    @ViewBuilder
    func boundariesMatchRows(_ boundaries: ParkBoundariesStatusResponse) -> some View {
        LabeledContent("Exact Matches") {
            Text("\(boundaries.exactMatches)").fontDesign(.monospaced)
        }
        LabeledContent("Spatial Matches") {
            Text("\(boundaries.spatialMatches)").fontDesign(.monospaced)
        }
        if let oldest = boundaries.oldestFetch {
            LabeledContent("Oldest Fetch") { Text(oldest).foregroundStyle(.secondary) }
        }
        if let newest = boundaries.newestFetch {
            LabeledContent("Newest Fetch") { Text(newest).foregroundStyle(.secondary) }
        }
    }

    // MARK: - Historic Trails

    func trailsSection(_ trails: TrailStatusResponse) -> some View {
        Section {
            LabeledContent("Completion") {
                Text("\(trails.completionPercentage)%")
                    .fontDesign(.monospaced)
                    .foregroundStyle(trails.completionPercentage >= 100 ? .green : .primary)
            }
            ProgressView(value: min(Double(trails.completionPercentage) / 100.0, 1.0))
                .tint(trails.completionPercentage >= 100 ? .green : .blue)
            LabeledContent("Total Catalog") {
                Text("\(trails.totalCatalog)").fontDesign(.monospaced)
            }
            LabeledContent("Cached") {
                Text("\(trails.totalCached)").fontDesign(.monospaced).foregroundStyle(.green)
            }
            LabeledContent("Unfetched") {
                Text("\(trails.unfetched)")
                    .fontDesign(.monospaced)
                    .foregroundStyle(trails.unfetched > 0 ? .orange : .green)
            }
            LabeledContent("Exact Matches") {
                Text("\(trails.exactMatches)").fontDesign(.monospaced)
            }
            LabeledContent("Spatial Matches") {
                Text("\(trails.spatialMatches)").fontDesign(.monospaced)
            }
            if let oldest = trails.oldestFetch {
                LabeledContent("Oldest Fetch") { Text(oldest).foregroundStyle(.secondary) }
            }
            if let newest = trails.newestFetch {
                LabeledContent("Newest Fetch") { Text(newest).foregroundStyle(.secondary) }
            }
        } header: {
            Label("Historic Trails Aggregator", systemImage: "figure.hiking")
        }
    }

    // MARK: - Programs

    func programsSection(_ programs: ProgramListResponse) -> some View {
        Section {
            ForEach(programs.programs) { program in
                HStack {
                    VStack(alignment: .leading) {
                        Text(program.name).font(.subheadline.weight(.medium))
                        if !program.capabilities.isEmpty {
                            Text(program.capabilities.joined(separator: ", "))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    Spacer()
                    if program.isActive == true {
                        Text("Active")
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(.green.opacity(0.15))
                            .foregroundStyle(.green)
                            .clipShape(Capsule())
                    } else {
                        Text("Inactive")
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(.secondary.opacity(0.15))
                            .foregroundStyle(.secondary)
                            .clipShape(Capsule())
                    }
                }
            }
        } header: {
            Label("Programs (\(programs.programs.count))", systemImage: "list.bullet")
        }
    }
}

// MARK: - SpotAggregatorRow

struct SpotAggregatorRow: View {
    let name: String
    let icon: String
    let interval: String
    let source: String

    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundStyle(.blue)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.subheadline.weight(.medium))
                Text(source)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("every \(interval)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fontDesign(.monospaced)
        }
    }
}
