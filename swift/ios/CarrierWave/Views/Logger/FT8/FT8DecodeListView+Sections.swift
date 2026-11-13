//
//  FT8DecodeListView+Sections.swift
//  CarrierWave
//

import CarrierWaveData
import SwiftUI
import UIKit

// MARK: - Sections

extension FT8DecodeListView {
    @ViewBuilder
    var directedSection: some View {
        if !directedDecodes.isEmpty {
            sectionHeader("DIRECTED AT YOU", count: directedDecodes.count, accent: .orange)

            ForEach(directedDecodes) { enriched in
                FT8DirectedDecodeRow(enriched: enriched)
                    .id(enriched.id)
                    .onTapGesture { onCallStation(enriched.decode) }
            }
        }
    }

    @ViewBuilder
    var watchedCallsignSection: some View {
        if let watched = effectiveWatchedCallsign {
            HStack {
                sectionHeader(
                    "\(watched) ACTIVITY",
                    count: watchedDecodes.count,
                    accent: .green
                )
                Spacer()
                if qsoCallsign == nil {
                    Button {
                        withAnimation(.spring(duration: 0.2, bounce: 0.0)) {
                            watchedCallsign = nil
                            confirmingCallID = nil
                        }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, 12)
                }
            }

            if watchedDecodes.isEmpty {
                Text("Waiting for next decode from \(watched)…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
            } else {
                ForEach(watchedDecodes) { enriched in
                    compactActivityRow(enriched)
                        .id("watched-\(enriched.id)")
                }
            }
        }
    }

    var callingCQSection: some View {
        Group {
            sectionHeader("CALLING CQ", count: cqDecodes.count, accent: .blue)
                .contextMenu {
                    Button {
                        isCompactMode.toggle()
                    } label: {
                        Label(
                            isCompactMode ? "Expanded View" : "Compact View",
                            systemImage: isCompactMode ? "list.bullet" : "list.dash"
                        )
                    }
                }

            ForEach(cqDecodes) { enriched in
                standardDecodeRow(enriched)
            }
        }
    }

    @ViewBuilder
    var allActivitySection: some View {
        if !isFocusMode, !activityDecodes.isEmpty {
            Button {
                withAnimation(.spring(duration: 0.3, bounce: 0.0)) {
                    isAllActivityExpanded.toggle()
                }
            } label: {
                sectionHeader(
                    "ALL ACTIVITY",
                    count: activityDecodes.count,
                    accent: .secondary,
                    chevron: isAllActivityExpanded ? "chevron.up" : "chevron.down"
                )
            }
            .buttonStyle(.plain)

            if isAllActivityExpanded {
                ForEach(activityDecodes) { enriched in
                    standardDecodeRow(enriched)
                }
            }
        }
    }
}

// MARK: - Row Helpers

extension FT8DecodeListView {
    func sectionHeader(
        _ title: String,
        count: Int,
        accent: Color,
        chevron: String? = nil
    ) -> some View {
        HStack {
            Text(title)
                .font(.caption2.weight(.bold))
                .foregroundStyle(accent)

            Text("(\(count))")
                .font(.caption2)
                .foregroundStyle(.tertiary)

            Spacer()

            if let chevron {
                Image(systemName: chevron)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    func callConfirmBar(call: String, decode: FT8DecodeResult) -> some View {
        HStack {
            Button("Call \(call)") {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                onCallStation(decode)
                confirmingCallID = nil
                watchedCallsign = nil
            }
            .font(.caption.bold())
            .buttonStyle(.bordered)
            .tint(.accentColor)

            Spacer()

            Button("Cancel") {
                withAnimation(.spring(duration: 0.2, bounce: 0.0)) {
                    confirmingCallID = nil
                    watchedCallsign = nil
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.accentColor.opacity(0.08))
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    /// Shared row used by both the CQ list and All Activity. Tap once to confirm,
    /// tap again (or press the Call button) to initiate the call. Works for any
    /// decode whose message has a caller callsign — including stations mid-QSO
    /// with someone else, so you can queue a call to them.
    func standardDecodeRow(_ enriched: FT8EnrichedDecode) -> some View {
        VStack(spacing: 0) {
            Group {
                if isCompactMode {
                    FT8CompactDecodeRow(enriched: enriched)
                } else {
                    FT8EnrichedDecodeRow(
                        enriched: enriched,
                        isCurrentCycle: currentCycleIDs.contains(enriched.id)
                    )
                }
            }
            .onTapGesture { handleRowTap(enriched) }

            if confirmingCallID == enriched.id,
               let call = enriched.decode.message.callerCallsign
            {
                callConfirmBar(call: call, decode: enriched.decode)
            }
        }
        .id(enriched.id)
    }

    func compactActivityRow(_ enriched: FT8EnrichedDecode) -> some View {
        HStack(spacing: 6) {
            if let from = enriched.decode.message.callerCallsign {
                Text(from)
                    .font(.caption.monospaced())
            }
            Image(systemName: "arrow.right")
                .font(.system(size: 8))
                .foregroundStyle(.tertiary)
            Text(enriched.decode.rawText)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer()
            Text("\(enriched.decode.snr)")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 2)
    }

    func handleRowTap(_ enriched: FT8EnrichedDecode) {
        guard let call = enriched.decode.message.callerCallsign else {
            return
        }
        if confirmingCallID == enriched.id {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            onCallStation(enriched.decode)
            confirmingCallID = nil
            watchedCallsign = nil
        } else {
            withAnimation(.spring(duration: 0.2, bounce: 0.0)) {
                confirmingCallID = enriched.id
                watchedCallsign = call
            }
        }
    }
}
