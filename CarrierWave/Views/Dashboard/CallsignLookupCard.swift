import SwiftData
import SwiftUI

/// Dashboard card for quick callsign lookup, showing the callsign info card inline.
struct CallsignLookupCard: View {
    // MARK: Internal

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            headerRow
            searchField
            resultContent
        }
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: Private

    @Environment(\.modelContext) private var modelContext

    @State private var callsign = ""
    @State private var lookupResult: CallsignLookupResult?
    @State private var previousQSOCount = 0
    @State private var lastContactDate: Date?
    @State private var matchingClubs: [String] = []
    @State private var isSearching = false
    @State private var lookupService: CallsignLookupService?
    @State private var lookupTask: Task<Void, Never>?

    private var headerRow: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.blue)
            Text("Callsign Lookup")
                .font(.headline)
            Spacer()
        }
    }

    private var searchField: some View {
        HStack {
            TextField("Enter callsign", text: $callsign)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .font(.body.monospaced())
                .onSubmit { triggerLookup() }
                .onChange(of: callsign) { _, newValue in
                    debouncedLookup(newValue)
                }

            if isSearching {
                ProgressView()
                    .controlSize(.small)
            }

            if !callsign.isEmpty {
                Button {
                    clearResults()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(10)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private var resultContent: some View {
        if let result = lookupResult {
            if let info = result.info {
                LoggerCallsignCard(info: info, previousQSOCount: previousQSOCount)
                enrichmentSection
            } else if let error = result.error {
                CallsignLookupErrorBanner(error: error)
            }
        }
    }

    @ViewBuilder
    private var enrichmentSection: some View {
        if lastContactDate != nil || !matchingClubs.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                if let date = lastContactDate {
                    lastContactRow(date)
                }
                if !matchingClubs.isEmpty {
                    clubMembershipRow
                }
            }
            .padding(12)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private var clubMembershipRow: some View {
        HStack(spacing: 6) {
            Image(systemName: "person.3.fill")
                .font(.caption2)
                .foregroundStyle(.blue)
            Text(matchingClubs.joined(separator: ", "))
                .font(.caption)
                .foregroundStyle(.blue)
                .lineLimit(2)
        }
    }

    private func lastContactRow(_ date: Date) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "clock")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text("Last contact: \(date.formatted(date: .abbreviated, time: .omitted))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Lookup Logic

    private func clearResults() {
        callsign = ""
        lookupResult = nil
        previousQSOCount = 0
        lastContactDate = nil
        matchingClubs = []
        lookupTask?.cancel()
    }

    private func debouncedLookup(_ value: String) {
        lookupTask?.cancel()
        lookupResult = nil

        let trimmed = value.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 3 else {
            isSearching = false
            previousQSOCount = 0
            lastContactDate = nil
            matchingClubs = []
            return
        }

        lookupTask = Task {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else {
                return
            }
            await performLookup(trimmed)
        }
    }

    private func triggerLookup() {
        let trimmed = callsign.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 2 else {
            return
        }
        lookupTask?.cancel()
        lookupTask = Task { await performLookup(trimmed) }
    }

    private func performLookup(_ callsign: String) async {
        isSearching = true
        defer { isSearching = false }

        if lookupService == nil {
            lookupService = CallsignLookupService(modelContext: modelContext)
        }

        guard let service = lookupService else {
            return
        }

        let upper = callsign.uppercased()

        let result = await service.lookupWithResult(upper)
        let count = fetchQSOCount(for: upper)
        let lastDate = fetchLastContactDate(for: upper)
        let clubs = ClubsSyncService.shared.clubs(for: upper)

        guard !Task.isCancelled else {
            return
        }

        lookupResult = result
        previousQSOCount = count
        lastContactDate = lastDate
        matchingClubs = clubs
    }

    // MARK: - Data Fetching

    private func fetchQSOCount(for callsign: String) -> Int {
        (try? modelContext.fetchCount(
            FetchDescriptor<QSO>(
                predicate: #Predicate<QSO> { qso in
                    qso.callsign == callsign
                        && !qso.isHidden
                        && qso.mode != "WEATHER"
                        && qso.mode != "SOLAR"
                        && qso.mode != "NOTE"
                }
            )
        )) ?? 0
    }

    private func fetchLastContactDate(for callsign: String) -> Date? {
        var descriptor = FetchDescriptor<QSO>(
            predicate: #Predicate<QSO> { qso in
                qso.callsign == callsign
                    && !qso.isHidden
                    && qso.mode != "WEATHER"
                    && qso.mode != "SOLAR"
                    && qso.mode != "NOTE"
            },
            sortBy: [SortDescriptor(\QSO.timestamp, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return (try? modelContext.fetch(descriptor))?.first?.timestamp
    }
}
