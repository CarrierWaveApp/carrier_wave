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
                            sessionManager: sessionManager,
                            parkReference: sessionManager?.activeSession?.parkReference
                        )
                    } else {
                        callsignInputSection

                        // Duplicate/new band warning
                        if let status = duplicateStatus {
                            DuplicateStatusBanner(status: status)
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

    /// Compact two-row session header for landscape:
    /// Row 1: title + end button
    /// Row 2: scrollable chip bar (all controls)
    func compactSessionHeader(_ session: LoggingSession) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 6) {
                Text(session.displayTitle)
                    .font(.caption.monospaced().weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer()

                Button {
                    callsignFieldFocused = false
                    handleEndSession()
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 7))
                        Text("END")
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.red)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
            }

            landscapeChipRow(session)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    /// Scrollable chip bar with all session controls for landscape header
    func landscapeChipRow(_ session: LoggingSession) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                spotCommentsChip(session)
                qsoCountChip(session)
                if session.isPOTA, !session.isRove {
                    parkHeaderView(session)
                }
                activeShiftPill(session)
                freqBandCapsule(session)
                modeCapsule(session)
                equipmentCapsule(session)
                if session.isMultiOp {
                    multiOpPill(session)
                }
                durationChip(session)
                spaceWeatherChip
                sdrTitleBarPill
                webSDRBadgeIfNeeded(session)
                if !showRadioPanel {
                    radioInlineBadge
                }
            }
            .fixedSize()
        }
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
                                },
                                onRecall: { qsoToRecall in
                                    DispatchQueue.main.async {
                                        recallQSO(qsoToRecall)
                                    }
                                },
                                onRequestDelete: { qsoToConfirm in
                                    qsoToDelete = qsoToConfirm
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
                        case let .boundary(marker):
                            BoundaryMarkerRow(marker: marker)
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
