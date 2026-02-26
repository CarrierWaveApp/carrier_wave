//
//  FT8SessionView.swift
//  CarrierWave
//

import CarrierWaveCore
import SwiftUI

struct FT8SessionView: View {
    // MARK: Internal

    let ft8Manager: FT8SessionManager

    let parkReference: String?

    var body: some View {
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

            activeQSOCard

            FT8DecodeListView(
                enrichedDecodes: ft8Manager.enrichedDecodes,
                currentCycleIDs: Set(ft8Manager.currentCycleEnriched.map(\.id)),
                onCallStation: { ft8Manager.callStation($0) }
            )
            .frame(minHeight: 120)

            Divider()

            FT8ControlBar(
                isReceiving: ft8Manager.isReceiving,
                operatingMode: Binding(
                    get: { ft8Manager.operatingMode },
                    set: { ft8Manager.setMode($0) }
                ),
                qsoCount: ft8Manager.qsoCount,
                parkReference: parkReference,
                onStart: {
                    Task { try? await ft8Manager.start() }
                },
                onStop: {
                    Task { await ft8Manager.stop() }
                }
            )
        }
        .animation(.spring(duration: 0.3, bounce: 0.0), value: isDebugExpanded)
        .task {
            try? await ft8Manager.start()
        }
    }

    // MARK: Private

    @State private var isDebugExpanded = false

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

    private var activeQSOCard: some View {
        FT8ActiveQSOCard(
            stateMachine: ft8Manager.qsoStateMachine,
            distanceMiles: currentQSODistanceMiles,
            dxccEntity: currentQSOEntity,
            onAbort: {
                ft8Manager.setMode(.listen)
            }
        )
    }
}
