//
//  FT8SessionView.swift
//  CarrierWave
//

import CarrierWaveData
import SwiftUI

// MARK: - FT8ChannelPickerToken

/// Identifiable token that drives the channel-picker sheet. Carries the CQ
/// modifier the user picked from the menu so the sheet can start TX with the
/// right text. Using `.sheet(item:)` rather than `.sheet(isPresented:)` keeps
/// the modifier and the presentation in a single state mutation, which fixes
/// a race where the sheet was failing to present from a Menu button on iOS 18+.
struct FT8ChannelPickerToken: Identifiable, Equatable {
    let id = UUID()
    let modifier: String?
}

// MARK: - FT8SessionView

struct FT8SessionView: View {
    // MARK: Internal

    let ft8Manager: FT8SessionManager
    let sessionManager: LoggingSessionManager?

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
        .overlay {
            if ft8Manager.isTransmitting {
                RoundedRectangle(cornerRadius: 0)
                    .stroke(Color.red, lineWidth: 3)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }
        }
        .animation(reduceMotion ? .none : .easeInOut(duration: 0.2), value: ft8Manager.isTransmitting)
        .animation(reduceMotion ? .none : .spring(duration: 0.3, bounce: 0.0), value: isDebugExpanded)
        .animation(reduceMotion ? .none : .spring(duration: 0.3, bounce: 0.0), value: showSessionSummary)
        .animation(reduceMotion ? .none : .spring(duration: 0.3, bounce: 0.0), value: isWaterfallPickMode)
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
        .overlay(alignment: .top) {
            if let message = ft8Manager.startupError {
                FT8StartupErrorBanner(
                    message: message,
                    onRetry: {
                        Task {
                            await ft8Manager.retryStart()
                            if ft8Manager.startupError == nil {
                                sessionStartTime = Date()
                            }
                        }
                    }
                )
                .padding(.horizontal)
                .padding(.top, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(reduceMotion ? .none : .easeInOut(duration: 0.2), value: ft8Manager.startupError)
        .task {
            do {
                try await ft8Manager.start()
                sessionStartTime = Date()
            } catch {
                // ft8Manager.startupError is set inside start(); the overlay
                // above renders the user-facing banner with a retry action.
            }
        }
    }

    /// Called by FT8ControlBar when the user picks a CQ variant.
    func requestCQChannel(modifier: String?) {
        channelPickerToken = FT8ChannelPickerToken(modifier: modifier)
    }

    // MARK: Private

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @State private var isDebugExpanded = false
    @State private var sessionStartTime: Date?
    @State private var showSessionSummary = false
    @State private var sessionSummary: FT8SessionSummaryToast?
    @State private var channelPickerToken: FT8ChannelPickerToken?
    @State private var isWaterfallPickMode = false
    /// Modifier captured when the user switches from the channel picker into
    /// "tap on the waterfall to pick a frequency" mode, so the eventual
    /// `Start CQ` button still sends the right CQ text.
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
            previousDayQSOCount: sessionManager?.previousDayQSOCount,
            txState: ft8Manager.txState,
            parkReference: parkReference,
            suggestedCQModifier: suggestedCQModifier,
            onStart: {
                Task {
                    try? await ft8Manager.start()
                    sessionStartTime = Date()
                }
            },
            onStop: {
                showSummaryAndStop()
            },
            onRequestCQ: { modifier in
                requestCQChannel(modifier: modifier)
            }
        )
    }
}

// MARK: - FT8SessionView + Helpers

extension FT8SessionView {
    /// Moved out of the main struct body to keep it under SwiftLint's 300-line
    /// type_body_length cap. Same-file extensions retain access to @State and
    /// private properties.
    var bandAndStatusRow: some View {
        HStack(spacing: 6) {
            Menu {
                ForEach(FT8Constants.supportedBands, id: \.self) { band in
                    Button(band) {
                        ft8Manager.selectedBand = band
                        if let freq = FT8Constants.dialFrequency(forBand: band) {
                            _ = sessionManager?.updateFrequency(freq)
                        }
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
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.red.opacity(0.12))
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Change TX channel, currently \(Int(ft8Manager.txAudioFrequency)) hertz")
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
            .accessibilityHint("Tap to expand audio diagnostics")
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

    var suggestedCQModifier: String? {
        guard let session = sessionManager?.activeSession else {
            return nil
        }
        if session.isContest {
            return "TEST"
        }
        switch session.activationType {
        case .pota: return "POTA"
        case .sota: return "SOTA"
        case .wwff: return "WWFF"
        case .tota: return "TOTA"
        case .aoa,
             .casual: return nil
        }
    }

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
            onOverride: { _ in
                // Override wiring — future enhancement
            }
        )
    }

    func startCQWithCurrentChannel() {
        ft8Manager.setMode(.callCQ(modifier: pendingCQModifier))
        pendingCQModifier = nil
    }

    func showSummaryAndStop() {
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
