//
//  FT8DecodeListView.swift
//  CarrierWave
//

import CarrierWaveCore
import SwiftUI

struct FT8DecodeListView: View {
    // MARK: Internal

    let decodes: [FT8DecodeResult]
    let currentCycleIDs: Set<FT8DecodeResult.ID>
    let myCallsign: String
    let onCallStation: (FT8DecodeResult) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(decodes) { result in
                        decodeRow(result, isNew: currentCycleIDs.contains(result.id))
                            .onTapGesture {
                                if result.message.isCallable {
                                    onCallStation(result)
                                }
                            }
                    }
                }
                .padding(.horizontal)
            }
            .onChange(of: decodes.count) { oldCount, newCount in
                guard newCount > oldCount else {
                    return
                }
                if let last = decodes.last {
                    proxy.scrollTo(last.id, anchor: .bottom)
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
