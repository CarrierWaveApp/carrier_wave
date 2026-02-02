import SwiftUI

// MARK: - P2PPanelView

/// Panel showing park-to-park opportunities from nearby RBN skimmers
struct P2PPanelView: View {
    // MARK: Lifecycle

    init(
        userCallsign: String,
        userGrid: String,
        initialBand: String? = nil,
        initialMode: String? = nil,
        onDismiss: @escaping () -> Void,
        onSelectOpportunity: ((P2POpportunity) -> Void)? = nil
    ) {
        self.userCallsign = userCallsign
        self.userGrid = userGrid
        self.onDismiss = onDismiss
        self.onSelectOpportunity = onSelectOpportunity
        _bandFilter = State(initialValue: BandFilter.from(bandName: initialBand))
        _modeFilter = State(initialValue: ModeFilter.from(modeName: initialMode))
    }

    // MARK: Internal

    let userCallsign: String
    let userGrid: String
    let onDismiss: () -> Void
    let onSelectOpportunity: ((P2POpportunity) -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            header
            filterBar
            Divider()

            if isLoading {
                loadingView
            } else if let error = errorMessage {
                errorView(error)
            } else if filteredOpportunities.isEmpty {
                emptyView
            } else {
                opportunitiesList
            }
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.1), radius: 8, y: 2)
        .task {
            await loadOpportunities()
        }
    }

    // MARK: Private

    @State private var allOpportunities: [P2POpportunity] = []
    @State private var isLoading = true
    @State private var loadingProgress: P2PProgress = .fetchingPOTASpots
    @State private var errorMessage: String?
    @State private var bandFilter: BandFilter
    @State private var modeFilter: ModeFilter
    @State private var showFilterSheet = false

    private var filteredOpportunities: [P2POpportunity] {
        allOpportunities.filter { opportunity in
            if let targetBand = bandFilter.bandName {
                guard opportunity.band == targetBand else {
                    return false
                }
            }
            guard modeFilter.matches(opportunity.mode) else {
                return false
            }
            return true
        }
    }

    private var opportunitiesByBand: [(band: String, opportunities: [P2POpportunity])] {
        let grouped = Dictionary(grouping: filteredOpportunities) { $0.band }
        return grouped.sorted { lhs, rhs in
            let lhsIdx = BandUtilities.bandOrder.firstIndex(of: lhs.key) ?? 999
            let rhsIdx = BandUtilities.bandOrder.firstIndex(of: rhs.key) ?? 999
            return lhsIdx < rhsIdx
        }.map {
            (band: $0.key, opportunities: $0.value)
        }
    }

    private var filterDisplayText: String {
        let bandText = bandFilter == .all ? "All Bands" : bandFilter.rawValue
        let modeText = modeFilter == .all ? "All Modes" : modeFilter.rawValue

        if bandFilter == .all, modeFilter == .all {
            return "All"
        } else if modeFilter == .all {
            return bandText
        } else if bandFilter == .all {
            return modeText
        } else {
            return "\(bandText) • \(modeText)"
        }
    }

    private var progressText: String {
        switch loadingProgress {
        case .fetchingPOTASpots:
            "Fetching POTA spots..."
        case let .queryingRBN(current, total):
            "Querying RBN (\(current)/\(total))..."
        case .filteringByDistance:
            "Finding nearby spotters..."
        case .complete:
            "Complete"
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Image(systemName: "arrow.left.arrow.right")
                .foregroundStyle(.orange)
            Text("P2P Opportunities")
                .font(.headline)
            Spacer()
            Button {
                Task { await loadOpportunities() }
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

    // MARK: - Filter Bar

    private var filterBar: some View {
        HStack {
            Button {
                showFilterSheet = true
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                        .font(.caption)
                    Text(filterDisplayText)
                        .font(.caption.weight(.medium))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.orange.opacity(0.15))
                .foregroundStyle(.orange)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .sheet(isPresented: $showFilterSheet) {
                filterSheet
            }

            Spacer()

            Text("\(filteredOpportunities.count) P2P")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal)
        .padding(.bottom, 6)
    }

    private var filterSheet: some View {
        NavigationStack {
            Form {
                Section("Band") {
                    Picker("Band", selection: $bandFilter) {
                        ForEach(BandFilter.allCases) { filter in
                            Text(filter.rawValue).tag(filter)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }

                Section("Mode") {
                    Picker("Mode", selection: $modeFilter) {
                        ForEach(ModeFilter.allCases) { filter in
                            Text(filter.rawValue).tag(filter)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }
            }
            .navigationTitle("Filter P2P")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        showFilterSheet = false
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Reset") {
                        bandFilter = .all
                        modeFilter = .all
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }

    // MARK: - Content Views

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text(progressText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 200)
    }

    private var emptyView: some View {
        VStack(spacing: 8) {
            Image(systemName: "arrow.left.arrow.right")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("No P2P opportunities right now")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("Try again in a few minutes")
                .font(.caption)
                .foregroundStyle(.tertiary)
            if bandFilter != .all || modeFilter != .all {
                Button("Clear Filters") {
                    bandFilter = .all
                    modeFilter = .all
                }
                .buttonStyle(.bordered)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, minHeight: 200)
    }

    private var opportunitiesList: some View {
        ScrollView {
            LazyVStack(spacing: 0, pinnedViews: .sectionHeaders) {
                ForEach(opportunitiesByBand, id: \.band) { section in
                    Section {
                        ForEach(section.opportunities) { opportunity in
                            P2POpportunityRow(opportunity: opportunity) {
                                onSelectOpportunity?(opportunity)
                            }
                            Divider()
                                .padding(.leading, 92)
                        }
                    } header: {
                        sectionHeader(section.band)
                    }
                }
            }
        }
        .frame(maxHeight: 400)
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .font(.title2)
                .foregroundStyle(.orange)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Retry") {
                Task { await loadOpportunities() }
            }
            .buttonStyle(.bordered)
        }
        .padding()
        .frame(maxWidth: .infinity, minHeight: 200)
    }

    private func sectionHeader(_ band: String) -> some View {
        HStack {
            Text(band)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(.secondarySystemGroupedBackground))
    }

    // MARK: - Data Loading

    private func loadOpportunities() async {
        isLoading = true
        errorMessage = nil
        loadingProgress = .fetchingPOTASpots

        do {
            let rbnClient = RBNClient()
            let potaClient = POTAClient(authService: POTAAuthService())
            let service = P2PService(rbnClient: rbnClient, potaClient: potaClient)

            allOpportunities = try await service.findOpportunities(
                userGrid: userGrid,
                userCallsign: userCallsign
            ) { @Sendable progress in
                Task { @MainActor in
                    loadingProgress = progress
                }
            }
            isLoading = false
        } catch let error as P2PError {
            errorMessage = error.errorDescription
            allOpportunities = []
            isLoading = false
        } catch {
            errorMessage = error.localizedDescription
            allOpportunities = []
            isLoading = false
        }
    }
}

// MARK: - P2POpportunityRow

/// A row displaying a single P2P opportunity
struct P2POpportunityRow: View {
    // MARK: Internal

    let opportunity: P2POpportunity
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 12) {
                // Frequency column
                VStack(alignment: .trailing, spacing: 2) {
                    frequencyDisplay
                    bandModeDisplay
                }
                .frame(width: 80, alignment: .trailing)

                // Callsign and park info
                VStack(alignment: .leading, spacing: 2) {
                    callsignRow
                    parkInfoRow
                }

                Spacer()

                // SNR and time
                VStack(alignment: .trailing, spacing: 2) {
                    snrDisplay
                    Text(opportunity.timeAgo)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Private

    private var snrColor: Color {
        switch opportunity.snr {
        case ..<10:
            .red
        case ..<20:
            .orange
        case ..<30:
            .yellow
        default:
            .green
        }
    }

    private var parkDisplayText: String {
        var parts: [String] = [opportunity.parkRef]

        if let loc = opportunity.locationDesc, !loc.isEmpty {
            let state = loc.components(separatedBy: "-").last ?? loc
            parts.append(state)
        }

        if let name = opportunity.parkName, !name.isEmpty {
            parts.append(name)
        }

        return parts.joined(separator: " - ")
    }

    // MARK: - Subviews

    private var frequencyDisplay: some View {
        Text(formatFrequency(opportunity.frequencyMHz))
            .font(.subheadline.monospaced())
    }

    private var bandModeDisplay: some View {
        HStack(spacing: 4) {
            Text(opportunity.band)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(opportunity.mode)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var callsignRow: some View {
        HStack(spacing: 4) {
            Text(opportunity.callsign)
                .font(.subheadline.weight(.semibold).monospaced())
                .foregroundStyle(.primary)

            Text("P2P")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.orange)
                .clipShape(Capsule())
        }
    }

    private var parkInfoRow: some View {
        HStack(spacing: 4) {
            Image(systemName: "tree.fill")
                .font(.caption2)
                .foregroundStyle(.green)

            Text(parkDisplayText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private var snrDisplay: some View {
        HStack(spacing: 2) {
            snrBar
            Text("\(opportunity.snr) dB")
                .font(.caption.weight(.medium).monospaced())
                .foregroundStyle(snrColor)
        }
    }

    private var snrBar: some View {
        // Visual SNR indicator (0-40 dB range typical)
        let normalizedSNR = min(max(Double(opportunity.snr), 0), 40) / 40.0
        return RoundedRectangle(cornerRadius: 2)
            .fill(snrColor)
            .frame(width: 30 * normalizedSNR, height: 8)
            .overlay(
                RoundedRectangle(cornerRadius: 2)
                    .stroke(snrColor.opacity(0.3), lineWidth: 1)
                    .frame(width: 30, height: 8),
                alignment: .leading
            )
    }

    private func formatFrequency(_ mhz: Double) -> String {
        let kHz = mhz * 1_000.0
        let rounded100Hz = (kHz * 10).rounded() / 10
        let wholekHz = Int(rounded100Hz)
        let subkHz = Int((rounded100Hz - Double(wholekHz)) * 10 + 0.5)

        let wholeMHz = wholekHz / 1_000
        let remainderkHz = wholekHz % 1_000

        if subkHz > 0 {
            return String(format: "%2d.%03d.%d", wholeMHz, remainderkHz, subkHz)
        } else {
            return String(format: "%2d.%03d  ", wholeMHz, remainderkHz)
        }
    }
}
