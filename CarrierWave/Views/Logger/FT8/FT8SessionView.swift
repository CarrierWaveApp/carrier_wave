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
            bandSelector

            FT8WaterfallView(data: ft8Manager.waterfallData)
                .frame(height: 80)

            FT8CycleIndicatorView(
                isTransmitting: ft8Manager.isTransmitting,
                timeRemaining: ft8Manager.cycleTimeRemaining
            )

            Divider()

            FT8DecodeListView(
                decodes: ft8Manager.decodeResults,
                currentCycleIDs: Set(ft8Manager.currentCycleDecodes.map(\.id)),
                myCallsign: ft8Manager.qsoStateMachine.myCallsign,
                onCallStation: { ft8Manager.callStation($0) }
            )
            .frame(minHeight: 120)

            FT8ActiveQSOCard(stateMachine: ft8Manager.qsoStateMachine)

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
        .task {
            try? await ft8Manager.start()
        }
    }

    // MARK: Private

    private var bandSelector: some View {
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
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color(.systemBackground))
    }
}
