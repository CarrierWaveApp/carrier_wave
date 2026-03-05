//
//  FT8SessionView.swift
//  CarrierWave
//

import CarrierWaveData
import SwiftUI

struct FT8SessionView: View {
    // MARK: Internal

    let ft8Manager: FT8SessionManager

    let parkReference: String?

    var body: some View {
        Group {
            if verticalSizeClass == .compact {
                landscapeLayout
            } else {
                portraitLayout
            }
        }
        .overlay(alignment: .top) {
            if showSessionSummary, let summary = sessionSummary {
                summary
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .onAppear {
                        Task {
                            try? await Task.sleep(for: .seconds(5))
                            withAnimation { showSessionSummary = false }
                        }
                    }
            }
        }
        .animation(.spring(duration: 0.3, bounce: 0.0), value: isDebugExpanded)
        .animation(.spring(duration: 0.3, bounce: 0.0), value: showSessionSummary)
        .task {
            try? await ft8Manager.start()
            sessionStartTime = Date()
        }
    }

    // MARK: Private

    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @State private var isDebugExpanded = false
    @State private var sessionStartTime: Date?
    @State private var showSessionSummary = false
    @State private var sessionSummary: FT8SessionSummaryToast?

    private var currentQSODistanceMiles: Int? {
        guard let theirGrid = ft8Manager.qsoStateMachine.theirGrid else {
            return nil
        }
        return CarrierWaveCore.MaidenheadConverter.distanceMiles(
            from: ft8Manager.qsoStateMachine.myGrid,
            to: theirGrid
        ).map(Int.init)
    }

    private var currentQSOEntity: String? {
        guard let call = ft8Manager.qsoStateMachine.theirCallsign else {
            return nil
        }
        let entity = DescriptionLookup.entityDescription(for: call)
        return entity == "Unknown" ? nil : entity
    }

    // MARK: - Layouts

    private var portraitLayout: some View {
        VStack(spacing: 0) {
            bandAndStatusRow

            if isDebugExpanded {
                FT8DebugPanel(ft8Manager: ft8Manager)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            FT8WaterfallView(
                data: ft8Manager.waterfallData,
                currentDecodes: ft8Manager.currentCycleDecodes
            )
            .frame(height: 48)

            FT8CycleIndicatorView(
                isTransmitting: ft8Manager.isTransmitting,
                timeRemaining: ft8Manager.cycleTimeRemaining
            )

            Divider()

            conversationCard

            decodeList
                .frame(minHeight: 120)

            Divider()

            controlBar
        }
    }

    private var landscapeLayout: some View {
        VStack(spacing: 0) {
            bandAndStatusRow
            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    FT8WaterfallView(
                        data: ft8Manager.waterfallData,
                        currentDecodes: ft8Manager.currentCycleDecodes
                    )
                    .frame(height: 140)

                    conversationCard

                    Spacer()

                    controlBar
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                Divider()

                VStack(spacing: 0) {
                    FT8CycleIndicatorView(
                        isTransmitting: ft8Manager.isTransmitting,
                        timeRemaining: ft8Manager.cycleTimeRemaining
                    )

                    decodeList
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    // MARK: - Shared Components

    private var decodeList: some View {
        FT8DecodeListView(
            enrichedDecodes: ft8Manager.enrichedDecodes,
            currentCycleIDs: Set(ft8Manager.currentCycleEnriched.map(\.id)),
            onCallStation: { ft8Manager.callStation($0) }
        )
    }

    private var controlBar: some View {
        FT8ControlBar(
            isReceiving: ft8Manager.isReceiving,
            operatingMode: Binding(
                get: { ft8Manager.operatingMode },
                set: { ft8Manager.setMode($0) }
            ),
            qsoCount: ft8Manager.qsoCount,
            parkReference: parkReference,
            onStart: {
                Task {
                    try? await ft8Manager.start()
                    sessionStartTime = Date()
                }
            },
            onStop: {
                showSummaryAndStop()
            }
        )
    }

    private var bandAndStatusRow: some View {
        HStack(spacing: 6) {
            Menu {
                ForEach(FT8Constants.supportedBands, id: \.self) { band in
                    Button(band) {
                        ft8Manager.selectedBand = band
                    }
                }
            } label: {
                HStack(spacing: 2) {
                    Text(ft8Manager.selectedBand)
                        .font(.body.bold())
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2)
                }
                .foregroundStyle(.primary)
            }

            Text("\u{00B7}")
                .foregroundStyle(.secondary)

            Text("\(ft8Manager.selectedFrequency, specifier: "%.3f") MHz")
                .font(.body.monospacedDigit())

            Text("\u{00B7}")
                .foregroundStyle(.secondary)

            Text("FT8")
                .font(.caption.bold())
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.orange.opacity(0.2))
                .clipShape(Capsule())

            Spacer()

            Button {
                isDebugExpanded.toggle()
            } label: {
                FT8StatusPillView(
                    audioLevel: ft8Manager.audioLevel,
                    decodeCount: ft8Manager.currentCycleDecodes.count,
                    cyclesSinceLastDecode: ft8Manager.cyclesSinceLastDecode
                )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color(.systemBackground))
    }

    private var conversationCard: some View {
        FT8ConversationCard(
            stateMachine: ft8Manager.qsoStateMachine,
            txEvents: ft8Manager.txEvents,
            rxMessages: ft8Manager.currentCycleDecodes.filter {
                $0.message.isDirectedTo(ft8Manager.qsoStateMachine.myCallsign)
            },
            distanceMiles: currentQSODistanceMiles,
            dxccEntity: currentQSOEntity,
            txAudioFrequency: ft8Manager.txAudioFrequency,
            isTXHalted: ft8Manager.isTXHalted,
            onHaltResume: {
                if ft8Manager.isTXHalted {
                    ft8Manager.resumeTX()
                } else {
                    ft8Manager.haltTX()
                }
            },
            onAbort: {
                ft8Manager.setMode(.listen)
            },
            onOverride: { _ in
                // Override wiring — future enhancement
            }
        )
    }

    private func showSummaryAndStop() {
        let duration = sessionStartTime.map { Date().timeIntervalSince($0) } ?? 0
        sessionSummary = FT8SessionSummaryToast(
            band: ft8Manager.selectedBand,
            qsoCount: ft8Manager.qsoCount,
            duration: duration
        )
        Task { await ft8Manager.stop() }
        withAnimation { showSessionSummary = true }
    }
}
