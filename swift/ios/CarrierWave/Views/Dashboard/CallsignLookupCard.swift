import CarrierWaveCore
import CarrierWaveData
import SwiftData
import SwiftUI

/// Dashboard card combining QRZ/HamDB callsign enrichment with live RBN spots.
/// Submitting a callsign shows both the enriched profile card and the
/// Reverse Beacon Network spots panel for that callsign.
struct CallsignLookupCard: View {
    // MARK: Internal

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            headerRow
            if submittedCallsign == nil {
                searchField
            }
            resultContent
        }
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: Private

    @Environment(\.modelContext) private var modelContext

    @AppStorage("loggerDefaultCallsign") private var defaultCallsign = ""

    @State private var callsign = ""
    @State private var submittedCallsign: String?
    @State private var lookupResult: CallsignLookupResult?
    @State private var previousQSOCount = 0
    @State private var lastContactDate: Date?
    @State private var matchingClubs: [String] = []
    @State private var isSearching = false
    @State private var lookupService: CallsignLookupService?
    @State private var lookupTask: Task<Void, Never>?
    @FocusState private var isFieldFocused: Bool

    private var trimmedDefaultCallsign: String {
        defaultCallsign.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    private var headerRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.blue)
            Text("Lookup & RBN Spots")
                .font(.headline)
            Spacer()
            if submittedCallsign != nil || !callsign.isEmpty {
                Button("Clear") { clearAll() }
                    .font(.caption)
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Clear lookup")
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            CallsignTextField(
                "Enter callsign",
                text: $callsign,
                isFocused: $isFieldFocused,
                fontSize: 17,
                showCommands: false,
                onSubmit: { submit(callsign) }
            )
            .padding(.horizontal, 8)
            .frame(height: 44)
            .background(Color(.tertiarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            if isSearching {
                ProgressView()
                    .controlSize(.small)
            }

            Button {
                submit(callsign)
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color(.systemBackground))
                    .frame(width: 44, height: 44)
                    .background(Color.accentColor)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            .disabled(!isCallsignValid(callsign))
            .accessibilityLabel("Search callsign")

            if !trimmedDefaultCallsign.isEmpty {
                Button {
                    callsign = trimmedDefaultCallsign
                    submit(callsign)
                } label: {
                    Text("ME")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color(.systemBackground))
                        .frame(width: 44, height: 44)
                        .background(Color.accentColor)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Look up my callsign \(trimmedDefaultCallsign)")
            }
        }
    }

    @ViewBuilder
    private var resultContent: some View {
        if let submitted = submittedCallsign {
            VStack(alignment: .leading, spacing: 8) {
                enrichedSection
                RBNPanelView(
                    embeddedCallsign: submitted,
                    targetCallsign: submitted,
                    showsCallsignInHeader: false
                )
            }
        }
    }

    @ViewBuilder
    private var enrichedSection: some View {
        if let result = lookupResult {
            if let info = result.info {
                NavigationLink {
                    CallsignHistoryView(callsign: info.callsign)
                } label: {
                    VStack(alignment: .leading, spacing: 0) {
                        LoggerCallsignCard(info: info, previousQSOCount: previousQSOCount)
                        enrichmentSection
                    }
                }
                .buttonStyle(.plain)

                actionsRow(info: info)
            } else if let error = result.error {
                CallsignLookupErrorBanner(error: error)
            }
        } else if isSearching {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("Looking up callsign…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 8)
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
            .padding(.vertical, 4)
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

    private func actionsRow(info: CallsignInfo) -> some View {
        HStack(spacing: 16) {
            Spacer()
            Label("View Profile", systemImage: "person.crop.circle")
                .font(.caption)
                .foregroundStyle(.tint)
            EnrichedShareButton(
                payload: EnrichedLinkPayload.callsign(
                    info.callsign,
                    name: info.displayName,
                    grid: info.grid,
                    qth: info.qth,
                    country: info.country,
                    workedCount: previousQSOCount > 0 ? previousQSOCount : nil,
                    lastWorked: lastContactDate
                ),
                label: "Share"
            )
            .font(.caption)
        }
        .padding(.top, 4)
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

    private func submit(_ raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard isCallsignValid(trimmed) else {
            return
        }
        callsign = trimmed
        submittedCallsign = trimmed
        isFieldFocused = false
        lookupTask?.cancel()
        lookupTask = Task { await performLookup(trimmed) }
    }

    private func clearAll() {
        callsign = ""
        submittedCallsign = nil
        lookupResult = nil
        previousQSOCount = 0
        lastContactDate = nil
        matchingClubs = []
        lookupTask?.cancel()
    }

    private func isCallsignValid(_ value: String) -> Bool {
        value.trimmingCharacters(in: .whitespacesAndNewlines).count >= 3
    }

    // MARK: - Lookup

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
        previousQSOCount = fetchQSOCount(for: upper)
        lastContactDate = fetchLastContactDate(for: upper)
        matchingClubs = ClubsSyncService.shared.clubs(for: upper)

        // Streamed lookup: yields the cached row immediately (instant from
        // disk), then a second emission once QRZ/HamDB enriches.
        for await result in service.lookupStream(upper) {
            guard !Task.isCancelled else {
                return
            }
            lookupResult = result
            isSearching = false
        }
    }

    private func fetchQSOCount(for callsign: String) -> Int {
        (try? modelContext.boundedCount(
            QSO.self,
            predicate: #Predicate<QSO> { qso in
                qso.callsign == callsign
                    && !qso.isHidden
                    && qso.mode != "WEATHER"
                    && qso.mode != "SOLAR"
                    && qso.mode != "NOTE"
            }
        )) ?? 0
    }

    private func fetchLastContactDate(for callsign: String) -> Date? {
        let descriptor = BoundedDescriptor<QSO>(
            predicate: #Predicate<QSO> { qso in
                qso.callsign == callsign
                    && !qso.isHidden
                    && qso.mode != "WEATHER"
                    && qso.mode != "SOLAR"
                    && qso.mode != "NOTE"
            },
            sortBy: [SortDescriptor(\QSO.timestamp, order: .reverse)],
            limit: 1
        )
        return (try? modelContext.boundedFetch(descriptor))?.first?.timestamp
    }
}

#Preview {
    ScrollView {
        CallsignLookupCard()
            .padding()
    }
    .background(Color(.systemGroupedBackground))
}
