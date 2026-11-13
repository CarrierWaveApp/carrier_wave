//
//  SessionAddQSOSheet.swift
//  CarrierWave
//
//  "Add QSO" for a session that has already ended. One text line, parsed by
//  the logger's `QuickEntryParser` (callsign, RST, park, grid, state, freq,
//  mode, Zulu time, notes, multiple callsigns), logged through
//  `SessionLateEntryService` with the logger's callsign-lookup enrichment.
//

import CarrierWaveCore
import CarrierWaveData
import SwiftData
import SwiftUI

// MARK: - SessionAddQSOSheet

struct SessionAddQSOSheet: View {
    // MARK: Internal

    let session: LoggingSession
    /// Visible QSOs already in the session, for the in-log duplicate badge.
    let existingQSOs: [QSO]
    let onLogged: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                entrySection
                if let info = lookupResult {
                    Section {
                        LoggerCallsignCard(info: info, myGrid: session.myGrid)
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }
                if !entries.isEmpty {
                    previewSection
                }
                helpSection
            }
            .navigationTitle("Add QSO")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(entries.count > 1 ? "Log \(entries.count)" : "Log") { logEntries() }
                        .disabled(entries.isEmpty || isLogging)
                }
            }
            .onChange(of: input) { _, newValue in
                scheduleLookup(for: newValue)
            }
            .onAppear { inputFocused = true }
            .onDisappear { lookupTask?.cancel() }
        }
    }

    // MARK: Private

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @AppStorage("rstParseOrder") private var rstParseOrderRaw = RSTOrder.receivedFirst.rawValue

    @State private var input = ""
    @State private var lookupResult: CallsignInfo?
    @State private var lookupTask: Task<Void, Never>?
    @State private var lastLookedUp = ""
    @State private var isLogging = false
    @FocusState private var inputFocused: Bool

    private var rstOrder: RSTOrder {
        RSTOrder(rawValue: rstParseOrderRaw) ?? .receivedFirst
    }

    private var entries: [QuickEntryResult] {
        SessionLateEntryService.parse(input, rstOrder: rstOrder)
    }

    private var tokens: [ParsedToken] {
        SessionLateEntryService.tokens(input, rstOrder: rstOrder)
    }

    private var entrySection: some View {
        Section {
            TextField("Callsign  599  K-1234  FN31  14.062  CW  1432", text: $input)
                .font(.body.monospaced())
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .focused($inputFocused)
                .onSubmit { logEntries() }
            if !tokens.isEmpty {
                QuickEntryPreview(tokens: tokens)
                    .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 8, trailing: 12))
            }
        } header: {
            Text(session.displayTitle)
        } footer: {
            Text("Logged into this ended session. Anything you leave out comes from the session.")
        }
    }

    private var previewSection: some View {
        Section("Will log") {
            ForEach(Array(entries.enumerated()), id: \.offset) { _, entry in
                SessionAddQSOPreviewRow(
                    entry: entry,
                    session: session,
                    isDuplicate: isDuplicate(entry)
                )
            }
        }
    }

    private var helpSection: some View {
        Section {
            Text(
                "Same shortcuts as the logger: RST (599 or 59/57), park (K-1234), "
                    + "grid (FN31), state (CA), frequency (14.062), mode (SSB), "
                    + "Zulu time (1432) on the session's day, notes in quotes, "
                    + "and several callsigns on one line."
            )
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
    }

    private func isDuplicate(_ entry: QuickEntryResult) -> Bool {
        let callsign = entry.callsign.uppercased()
        let band = SessionAddQSOPreviewRow.band(for: entry, session: session)
        return existingQSOs.contains { $0.callsign == callsign && $0.band == band }
    }

    /// Same debounced, streamed lookup the logger runs while typing. Only the
    /// single-callsign case gets a card; multi-callsign lines enrich after logging.
    private func scheduleLookup(for text: String) {
        let parsed = SessionLateEntryService.parse(text, rstOrder: rstOrder)
        guard parsed.count == 1,
              let callsign = parsed.first?.callsign,
              callsign.count >= 3
        else {
            lookupTask?.cancel()
            lastLookedUp = ""
            lookupResult = nil
            return
        }
        let primary = CallsignParsing.primaryCallsign(from: callsign.uppercased())
        guard primary != lastLookedUp else {
            return
        }
        lastLookedUp = primary
        lookupTask?.cancel()
        let service = CallsignLookupService(modelContext: modelContext)
        lookupTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else {
                return
            }
            for await result in service.lookupStream(primary) {
                guard !Task.isCancelled else {
                    return
                }
                await MainActor.run { lookupResult = result.info }
            }
        }
    }

    private func logEntries() {
        let toLog = entries
        guard !toLog.isEmpty, !isLogging else {
            return
        }
        isLogging = true
        var logged: [LoggedQSO] = []
        var failure: Error?
        for entry in toLog {
            do {
                let qso = try SessionLateEntryService.log(
                    entry, lookup: lookupResult, session: session, modelContext: modelContext
                )
                logged.append(qso)
                // No resolved lookup for this callsign yet — enrich after the fact
                // (the HUNT path's fire-and-forget fill).
                let primary = CallsignParsing.primaryCallsign(from: entry.callsign.uppercased())
                if lookupResult?.callsign != primary {
                    let context = modelContext
                    Task {
                        await SessionLateEntryService.enrich(
                            qsoId: qso.id, callsign: entry.callsign, modelContext: context
                        )
                        NotificationCenter.default.post(name: .sessionQSOsDidChange, object: session.id)
                    }
                }
            } catch {
                failure = error
                break
            }
        }
        isLogging = false
        finish(logged: logged, failure: failure)
    }

    private func finish(logged: [LoggedQSO], failure: Error?) {
        if !logged.isEmpty {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            NotificationCenter.default.post(name: .sessionQSOsDidChange, object: session.id)
            onLogged()
        }
        if let failure {
            ToastManager.shared.error(failure.localizedDescription)
            return
        }
        let names = logged.map(\.callsign).joined(separator: ", ")
        ToastManager.shared.success("Logged \(names) into \(session.displayTitle)")
        dismiss()
    }
}

// MARK: - SessionAddQSOPreviewRow

/// One resolved line of the "Will log" preview: callsign, resolved
/// frequency/mode/band, resolved time, RST, and an in-log duplicate badge.
struct SessionAddQSOPreviewRow: View {
    // MARK: Internal

    let entry: QuickEntryResult
    let session: LoggingSession
    let isDuplicate: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(entry.callsign.uppercased())
                    .font(.headline.monospaced())
                Spacer()
                if isDuplicate {
                    Text("Already in log")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.orange.opacity(0.2), in: Capsule())
                        .foregroundStyle(.orange)
                }
            }
            HStack(spacing: 8) {
                if let freq = entry.frequency ?? session.frequency {
                    Text(FrequencyFormatter.formatWithUnit(freq))
                } else if let band = Self.band(for: entry, session: session) {
                    Text(band)
                }
                Text(entry.mode ?? session.mode)
                Text(timeLabel)
                if let rst = rstLabel {
                    Text(rst)
                }
            }
            .font(.caption.monospaced())
            .foregroundStyle(.secondary)
            if let detail = detailLabel {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    static func band(for entry: QuickEntryResult, session: LoggingSession) -> String? {
        if let band = entry.band {
            return band
        }
        if let freq = entry.frequency {
            return LoggingSession.bandForFrequency(freq)
        }
        return session.band
    }

    // MARK: Private

    private var timeLabel: String {
        let date = SessionLateEntryService.timestamp(for: entry, session: session)
        let formatter = DateFormatter()
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "HHmm'z' d MMM"
        return formatter.string(from: date)
    }

    private var rstLabel: String? {
        guard entry.rstSent != nil || entry.rstReceived != nil else {
            return nil
        }
        return "\(entry.rstSent ?? "—")/\(entry.rstReceived ?? "—")"
    }

    private var detailLabel: String? {
        var parts: [String] = []
        if let park = entry.theirPark {
            parts.append(park)
        }
        if let grid = entry.theirGrid {
            parts.append(grid)
        }
        if let state = entry.state {
            parts.append(state)
        }
        if let notes = entry.notes {
            parts.append("“\(notes)”")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
