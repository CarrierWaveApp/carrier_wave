import CarrierWaveData
import SwiftUI

// MARK: - LoggerView Landscape Layout

extension LoggerView {
    // MARK: - Two-Pane Layout

    /// Landscape layout: left pane (form) + divider + right pane (QSO list)
    var landscapeTwoPaneLayout: some View {
        HStack(spacing: 0) {
            // Left pane: compact header + form (scrollable)
            ScrollView {
                VStack(spacing: 8) {
                    if let session = sessionManager?.activeSession {
                        compactSessionHeader(session)
                    }

                    if sessionManager?.activeSession?.mode == "FT8",
                       let manager = ft8Manager
                    {
                        FT8SessionView(
                            ft8Manager: manager,
                            parkReference: sessionManager?.activeSession?.parkReference
                        )
                    } else {
                        callsignInputSection

                        // POTA duplicate/new band warning
                        if let status = potaDuplicateStatus {
                            POTAStatusBanner(status: status)
                                .transition(
                                    .asymmetric(
                                        insertion: .move(edge: .top).combined(with: .opacity),
                                        removal: .opacity
                                    )
                                )
                        }

                        callsignLookupDisplay

                        if !hideFieldEntryForm {
                            compactFieldsSection
                        }

                        if editingQSO != nil {
                            Button {
                                cancelEditingCallsign()
                            } label: {
                                Text("Cancel Edit")
                                    .font(.subheadline)
                            }
                            .buttonStyle(.bordered)
                            .accessibilityLabel("Cancel editing callsign")
                        }
                    }
                }
                .padding()
            }
            .frame(maxWidth: .infinity)

            Divider()

            // Right pane: QSO list (independently scrollable)
            landscapeQSOList
                .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Compact Session Header

    /// Single-line session header for landscape: title + freq/mode + QSO count + menu
    func compactSessionHeader(_ session: LoggingSession) -> some View {
        HStack(spacing: 8) {
            Text(session.displayTitle)
                .font(.subheadline.monospaced().weight(.medium))
                .lineLimit(1)
                .layoutPriority(1)

            if let freq = session.frequency {
                Text(
                    "\(FrequencyFormatter.format(freq)) \(session.band ?? "")"
                )
                .font(.caption.weight(.medium))
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Color.green.opacity(0.2))
                .clipShape(Capsule())
            }

            Text(session.mode)
                .font(.caption.weight(.medium))
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Color.blue.opacity(0.2))
                .clipShape(Capsule())

            Text("\(displayQSOs.count) QSOs")
                .font(.caption.weight(.medium))
                .foregroundStyle(.green)

            Spacer()

            Button {
                callsignFieldFocused = false
                handleEndSession()
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 7))
                    Text("End")
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.red)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(.secondarySystemGroupedBackground))
    }

    // MARK: - Landscape QSO List

    /// Independently scrollable QSO list for the right pane
    private var landscapeQSOList: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Session Log")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(displayQSOs.count) QSOs")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

            if sessionLogEntries.isEmpty {
                Text("No entries yet")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else {
                List {
                    ForEach(sessionLogEntries) { entry in
                        switch entry {
                        case let .qso(qso):
                            LoggerQSORow(
                                qso: qso,
                                utcDayQSOs: utcDayQSOs,
                                isPOTASession: sessionManager?.activeSession?
                                    .isPOTA ?? false,
                                onQSODeleted: { deletedQSO in
                                    sessionManager?.hideQSO(deletedQSO)
                                    refreshSessionQSOs()
                                },
                                onEditCallsign: { qsoToEdit in
                                    startEditingCallsign(qsoToEdit)
                                }
                            )
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    qsoToDelete = qso
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        case let .note(note):
                            LoggerNoteRow(note: note)
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                    .listRowBackground(Color.clear)
                    .listRowSeparatorTint(.secondary.opacity(0.2))
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(8)
    }
}
