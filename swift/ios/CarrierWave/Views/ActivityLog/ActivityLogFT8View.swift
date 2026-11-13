//
//  ActivityLogFT8View.swift
//  CarrierWave
//
//  FT8 session view adapted for the Hunter Log workflow.
//  Reuses FT8 session components with QSOs routed through ActivityLogManager.
//

import CarrierWaveData
import SwiftUI

// MARK: - ActivityLogFT8View

/// FT8 session UI embedded in the Hunter Log.
/// Shows waterfall, decode list, conversation card, and control bar
/// with QSOs logged through ActivityLogManager instead of LoggingSessionManager.
struct ActivityLogFT8View: View {
    // MARK: Internal

    let ft8Manager: FT8SessionManager
    let onStop: () -> Void

    var body: some View {
        Group {
            if verticalSizeClass == .compact {
                landscapeLayout
            } else {
                portraitLayout
            }
        }
        .overlay {
            if ft8Manager.isTransmitting {
                RoundedRectangle(cornerRadius: 0)
                    .stroke(Color.red, lineWidth: 3)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }
        }
        .animation(reduceMotion ? .none : .easeInOut(duration: 0.2), value: ft8Manager.isTransmitting)
        .sheet(item: $channelPickerToken) { token in
            FT8ChannelPicker(
                recommendations: ft8Manager.recommendedChannels(),
                selectedFrequency: Binding(
                    get: { ft8Manager.txAudioFrequency },
                    set: { ft8Manager.setTXChannel($0) }
                ),
                onConfirm: {
                    ft8Manager.setMode(.callCQ(modifier: token.modifier))
                },
                onSwitchToWaterfall: {
                    pendingCQModifier = token.modifier
                    withAnimation(.spring(duration: 0.3, bounce: 0.0)) {
                        isWaterfallPickMode = true
                    }
                }
            )
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
        .animation(reduceMotion ? .none : .spring(duration: 0.3, bounce: 0.0), value: isDebugExpanded)
        .animation(reduceMotion ? .none : .spring(duration: 0.3, bounce: 0.0), value: isWaterfallPickMode)
        .task {
            try? await ft8Manager.start()
        }
    }

    // MARK: Private

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @State private var isDebugExpanded = false
    @State private var channelPickerToken: FT8ChannelPickerToken?
    @State private var isWaterfallPickMode = false
    /// Modifier preserved across the picker → waterfall-pick handoff. See
    /// `FT8SessionView` for the same pattern.
    @State private var pendingCQModifier: String?

    private var isCQMode: Bool {
        if case .callCQ = ft8Manager.operatingMode {
            return true
        }
        return false
    }

    private var currentCQModifier: String? {
        if case let .callCQ(modifier) = ft8Manager.operatingMode {
            return modifier
        }
        return nil
    }

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
                currentDecodes: ft8Manager.currentCycleDecodes,
                rxFrequency: ft8Manager.rxAudioFrequency,
                txFrequency: ft8Manager.txAudioFrequency,
                isInQSO: ft8Manager.qsoStateMachine.theirCallsign != nil,
                isInteractive: isWaterfallPickMode,
                onTapFrequency: { hz in
                    ft8Manager.setTXChannel(hz)
                }
            )
            .frame(height: 240)

            if isWaterfallPickMode {
                waterfallPickConfirmBar
            }

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
                        currentDecodes: ft8Manager.currentCycleDecodes,
                        rxFrequency: ft8Manager.rxAudioFrequency,
                        txFrequency: ft8Manager.txAudioFrequency,
                        isInQSO: ft8Manager.qsoStateMachine.theirCallsign != nil,
                        isInteractive: isWaterfallPickMode,
                        onTapFrequency: { hz in
                            ft8Manager.setTXChannel(hz)
                        }
                    )
                    .frame(height: isWaterfallPickMode ? 160 : 140)

                    if isWaterfallPickMode {
                        waterfallPickConfirmBar
                    }

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
            isFocusMode: ft8Manager.isFocusMode,
            qsoCallsign: ft8Manager.qsoStateMachine.theirCallsign,
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
            previousDayQSOCount: nil,
            txState: ft8Manager.txState,
            parkReference: nil,
            suggestedCQModifier: nil,
            onStart: {
                Task { try? await ft8Manager.start() }
            },
            onStop: {
                Task { await ft8Manager.stop() }
                onStop()
            },
            onRequestCQ: { modifier in
                channelPickerToken = FT8ChannelPickerToken(modifier: modifier)
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
                .badgePill(Color.orange.opacity(0.2))

            Spacer()

            if isCQMode {
                Button {
                    channelPickerToken = FT8ChannelPickerToken(modifier: currentCQModifier)
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.caption2)
                        Text("\(Int(ft8Manager.txAudioFrequency)) Hz")
                            .font(.caption.bold().monospacedDigit())
                    }
                    .foregroundStyle(.red)
                    .badgePill(Color.red.opacity(0.12), verticalPadding: 3)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    "Change TX channel, currently \(Int(ft8Manager.txAudioFrequency)) hertz"
                )
            }

            Button {
                withAnimation(.spring(duration: 0.3, bounce: 0.0)) {
                    ft8Manager.isFocusMode.toggle()
                }
            } label: {
                Image(systemName: ft8Manager.isFocusMode ? "scope" : "target")
                    .font(.caption)
                    .foregroundStyle(ft8Manager.isFocusMode ? .orange : .secondary)
            }
            .buttonStyle(.plain)

            Button {
                isDebugExpanded.toggle()
            } label: {
                FT8AudioLevelBar(
                    rms: ft8Manager.audioLevel.bandRMS,
                    peak: ft8Manager.audioLevel.bandPeak,
                    cyclesSinceLastDecode: ft8Manager.cyclesSinceLastDecode,
                    decodeCount: ft8Manager.currentCycleDecodes.count
                )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color(.systemBackground))
        .overlay(alignment: .top) {
            if ft8Manager.isFocusMode {
                Rectangle()
                    .fill(Color.orange)
                    .frame(height: 2)
            }
        }
    }
}

// MARK: - ActivityLogFT8View Helpers

extension ActivityLogFT8View {
    var waterfallPickConfirmBar: some View {
        HStack(spacing: 12) {
            Text("TX: \(Int(ft8Manager.txAudioFrequency)) Hz")
                .font(.subheadline.bold().monospacedDigit())

            Spacer()

            Button("Cancel") {
                withAnimation(.spring(duration: 0.3, bounce: 0.0)) {
                    isWaterfallPickMode = false
                }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)

            Button("Start CQ") {
                withAnimation(.spring(duration: 0.3, bounce: 0.0)) {
                    isWaterfallPickMode = false
                }
                startCQWithCurrentChannel()
            }
            .font(.subheadline.bold())
            .buttonStyle(.borderedProminent)
            .tint(.green)
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
        .background(Color(.secondarySystemGroupedBackground))
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    var conversationCard: some View {
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
            onOverride: { _ in }
        )
    }

    func startCQWithCurrentChannel() {
        ft8Manager.setMode(.callCQ(modifier: pendingCQModifier))
        pendingCQModifier = nil
    }
}
