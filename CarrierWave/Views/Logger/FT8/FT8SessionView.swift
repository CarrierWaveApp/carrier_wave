//
//  FT8SessionView.swift
//  CarrierWave
//

import CarrierWaveCore
import SwiftUI

struct FT8SessionView: View {
    // MARK: Internal

    @State var ft8Manager: FT8SessionManager

    let parkReference: String?

    var body: some View {
        VStack(spacing: 0) {
            bandSelector

            FT8WaterfallView(data: waterfallData)
                .frame(height: 80)

            FT8CycleIndicatorView(
                isTransmitting: ft8Manager.isTransmitting,
                timeRemaining: ft8Manager.cycleTimeRemaining
            )

            Divider()

            FT8DecodeListView(
                decodes: ft8Manager.decodeResults,
                currentCycleDecodes: ft8Manager.currentCycleDecodes,
                myCallsign: ft8Manager.qsoStateMachine.myCallsign,
                onCallStation: { ft8Manager.callStation($0) }
            )

            FT8ActiveQSOCard(stateMachine: ft8Manager.qsoStateMachine)

            Divider()

            FT8ControlBar(
                operatingMode: Binding(
                    get: { ft8Manager.operatingMode },
                    set: { ft8Manager.setMode($0) }
                ),
                qsoCount: ft8Manager.qsoCount,
                parkReference: parkReference,
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

    @State private var waterfallData = FT8WaterfallData()

    private var bandSelector: some View {
        HStack {
            Picker("Band", selection: $ft8Manager.selectedBand) {
                ForEach(FT8Constants.supportedBands, id: \.self) { band in
                    Text(band).tag(band)
                }
            }
            .pickerStyle(.menu)

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
