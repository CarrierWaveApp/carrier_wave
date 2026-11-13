import CarrierWaveCore
import SwiftUI

// MARK: - DXpeditionsView

/// Main DXpeditions list with month navigation.
/// Shows on-air expeditions at top, then all active expeditions for the month.
struct DXpeditionsView: View {
    // MARK: Internal

    var isInNavigationContext = false

    var body: some View {
        if isInNavigationContext {
            content
        } else {
            NavigationStack {
                content
            }
        }
    }

    // MARK: Private

    private static let monthYearFormatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.dateFormat = "MMMM yyyy"
        return fmt
    }()

    @State private var expeditions: [Ham365DXpedition] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var selectedMonth: Int = Calendar.current.component(.month, from: Date())
    @State private var selectedYear: Int = Calendar.current.component(.year, from: Date())

    /// RBN spots keyed by callsign (only for ON AIR expeditions)
    @State private var onAirSpots: [String: [RBNSpot]] = [:]

    @State private var onAirExpeditions: [Ham365DXpedition] = []
    @State private var activeExpeditions: [Ham365DXpedition] = []

    private let client = Ham365Client()
    private let rbnClient = RBNClient()

    private var daysInMonth: Int {
        var components = DateComponents()
        components.month = selectedMonth
        components.year = selectedYear
        guard let date = Calendar.current.date(from: components),
              let range = Calendar.current.range(of: .day, in: .month, for: date)
        else {
            return 31
        }
        return range.count
    }

    private var monthYearLabel: String {
        var components = DateComponents()
        components.month = selectedMonth
        components.year = selectedYear
        components.day = 1
        guard let date = Calendar.current.date(from: components) else {
            return "\(selectedMonth)/\(selectedYear)"
        }
        return Self.monthYearFormatter.string(from: date)
    }

    private var content: some View {
        listContent
            .navigationTitle("DXpeditions")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await loadExpeditions() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(isLoading)
                }
            }
            .task {
                if expeditions.isEmpty {
                    await loadExpeditions()
                }
            }
            .onChange(of: expeditions) { _, _ in recomputeExpeditionLists() }
    }

    private var listContent: some View {
        List {
            monthPickerSection

            if isLoading {
                loadingSection
            } else if let errorMessage {
                errorSection(errorMessage)
            } else {
                if !onAirExpeditions.isEmpty {
                    onAirSection
                }

                if !activeExpeditions.isEmpty {
                    activeSection
                }

                if expeditions.isEmpty {
                    emptySection
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private var monthPickerSection: some View {
        Section {
            HStack {
                Button {
                    adjustMonth(by: -1)
                } label: {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.bordered)

                Spacer()

                Text(monthYearLabel)
                    .font(.headline)

                Spacer()

                Button {
                    adjustMonth(by: 1)
                } label: {
                    Image(systemName: "chevron.right")
                }
                .buttonStyle(.bordered)
            }
            .padding(.vertical, 4)
        }
    }

    private var loadingSection: some View {
        Section {
            HStack {
                Spacer()
                ProgressView("Loading DXpeditions…")
                Spacer()
            }
            .padding(.vertical, 20)
        }
    }

    private var onAirSection: some View {
        Section("On Air") {
            ForEach(onAirExpeditions) { expedition in
                NavigationLink {
                    DXpeditionDetailView(
                        expedition: expedition,
                        daysInMonth: daysInMonth
                    )
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        DXpeditionRow(
                            expedition: expedition,
                            daysInMonth: daysInMonth
                        )
                        if let spots = onAirSpots[expedition.callsign], !spots.isEmpty {
                            onAirSpotPills(spots)
                        }
                    }
                }
            }
        }
    }

    private var activeSection: some View {
        Section("Planned & Active") {
            ForEach(activeExpeditions) { expedition in
                NavigationLink {
                    DXpeditionDetailView(
                        expedition: expedition,
                        daysInMonth: daysInMonth
                    )
                } label: {
                    DXpeditionRow(
                        expedition: expedition,
                        daysInMonth: daysInMonth
                    )
                }
            }
        }
    }

    private var emptySection: some View {
        Section {
            VStack(spacing: 8) {
                Image(systemName: "globe")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                Text("No DXpeditions found for \(monthYearLabel)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
        }
    }

    /// Compact band/mode pills for an ON AIR expedition in the list.
    private func onAirSpotPills(_ spots: [RBNSpot]) -> some View {
        let grouped = DXpeditionSpotGrouper.group(spots)
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(grouped, id: \.label) { entry in
                    Text(entry.label)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.green)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(
                            Color.green.opacity(0.12),
                            in: RoundedRectangle(cornerRadius: 3)
                        )
                }
            }
        }
    }

    private func errorSection(_ message: String) -> some View {
        Section {
            VStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.title2)
                    .foregroundStyle(.orange)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("Retry") {
                    Task { await loadExpeditions() }
                }
                .buttonStyle(.bordered)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
        }
    }

    private func adjustMonth(by delta: Int) {
        var components = DateComponents()
        components.month = selectedMonth
        components.year = selectedYear
        components.day = 1
        guard let date = Calendar.current.date(from: components),
              let newDate = Calendar.current.date(byAdding: .month, value: delta, to: date)
        else {
            return
        }
        let newComponents = Calendar.current.dateComponents([.month, .year], from: newDate)
        selectedMonth = newComponents.month ?? selectedMonth
        selectedYear = newComponents.year ?? selectedYear
        Task { await loadExpeditions() }
    }

    private func recomputeExpeditionLists() {
        onAirExpeditions = expeditions.filter(\.isOnAir)
        activeExpeditions = expeditions.filter { !$0.activeDays.isEmpty && !$0.isOnAir }
    }

    private func loadExpeditions() async {
        isLoading = true
        errorMessage = nil
        do {
            expeditions = try await client.fetchDXpeditions(
                month: selectedMonth,
                year: selectedYear
            )
            recomputeExpeditionLists()
            await fetchOnAirSpots()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    /// Fetch RBN spots for each ON AIR DXpedition, searching all callsign variants.
    private func fetchOnAirSpots() async {
        let onAir = expeditions.filter(\.isOnAir)
        guard !onAir.isEmpty else {
            onAirSpots = [:]
            return
        }

        var spotsByCall: [String: [RBNSpot]] = [:]
        await withTaskGroup(of: (String, [RBNSpot]).self) { group in
            for expedition in onAir {
                group.addTask { [rbnClient] in
                    let spots = await (try? rbnClient.spots(
                        forVariants: expedition.searchCallsigns,
                        hours: 1, limit: 30
                    )) ?? []
                    return (expedition.callsign, spots)
                }
            }
            for await (callsign, spots) in group {
                spotsByCall[callsign] = spots
            }
        }
        onAirSpots = spotsByCall
    }
}
