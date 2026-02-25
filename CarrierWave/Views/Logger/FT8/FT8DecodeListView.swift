//
//  FT8DecodeListView.swift
//  CarrierWave
//

import CarrierWaveCore
import SwiftUI

struct FT8DecodeListView: View {
    // MARK: Internal

    let decodes: [FT8DecodeResult]
    let currentCycleDecodes: [FT8DecodeResult]
    let myCallsign: String
    let onCallStation: (FT8DecodeResult) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(decodes.enumerated()), id: \.offset) { index, result in
                        decodeRow(result, isNew: currentCycleDecodes.contains(result))
                            .id(index)
                            .onTapGesture {
                                if result.message.isCallable {
                                    onCallStation(result)
                                }
                            }
                    }
                }
                .padding(.horizontal)
            }
            .onChange(of: decodes.count) {
                if let last = decodes.indices.last {
                    proxy.scrollTo(last, anchor: .bottom)
                }
            }
        }
    }

    // MARK: Private

    private func decodeRow(_ result: FT8DecodeResult, isNew: Bool) -> some View {
        HStack(spacing: 8) {
            Text("\(result.snr)")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 32, alignment: .trailing)

            Text(result.rawText)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(textColor(for: result))
                .fontWeight(isNew ? .bold : .regular)

            Spacer()
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }

    private func textColor(for result: FT8DecodeResult) -> Color {
        if result.message.isCallable {
            return .green
        }
        if result.message.isDirectedTo(myCallsign) {
            return .red
        }
        return .primary
    }
}
