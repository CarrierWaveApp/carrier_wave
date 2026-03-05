//
//  FT8DecodeListView.swift
//  CarrierWave
//

import CarrierWaveData
import SwiftUI
import UIKit

struct FT8DecodeListView: View {
    // MARK: Internal

    let enrichedDecodes: [FT8EnrichedDecode]
    let currentCycleIDs: Set<UUID>
    var isFocusMode = false
    let onCallStation: (FT8DecodeResult) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    directedSection
                    callingCQSection
                    allActivitySection
                }
            }
            .onChange(of: directedDecodes.count) { oldCount, newCount in
                if newCount > oldCount, let first = directedDecodes.first {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    withAnimation {
                        proxy.scrollTo(first.id, anchor: .top)
                    }
                }
            }
        }
    }

    // MARK: Private

    @State private var isAllActivityExpanded = false
    @State private var confirmingCallID: UUID?
    @AppStorage("ft8CompactMode") private var isCompactMode = false

    private var directedDecodes: [FT8EnrichedDecode] {
        enrichedDecodes.filter { $0.section == .directedAtYou }
    }

    private var cqDecodes: [FT8EnrichedDecode] {
        enrichedDecodes
            .filter { decode in
                decode.section == .callingCQ
                    && decode.cycleAge < 4
                    && !(isFocusMode && decode.isDupe)
            }
            .sorted { lhs, rhs in
                if lhs.sortPriority != rhs.sortPriority {
                    return lhs.sortPriority < rhs.sortPriority
                }
                return lhs.decode.snr > rhs.decode.snr
            }
    }

    private var activityDecodes: [FT8EnrichedDecode] {
        enrichedDecodes.filter { $0.section == .allActivity }
    }

    // MARK: - Directed Section

    @ViewBuilder
    private var directedSection: some View {
        if !directedDecodes.isEmpty {
            sectionHeader("DIRECTED AT YOU", count: directedDecodes.count, accent: .orange)

            ForEach(directedDecodes) { enriched in
                FT8DirectedDecodeRow(enriched: enriched)
                    .id(enriched.id)
                    .onTapGesture { onCallStation(enriched.decode) }
            }
        }
    }

    // MARK: - CQ Section

    private var callingCQSection: some View {
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
                    .onTapGesture {
                        guard enriched.decode.message.isCallable else {
                            return
                        }
                        if confirmingCallID == enriched.id {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            onCallStation(enriched.decode)
                            confirmingCallID = nil
                        } else {
                            withAnimation(.spring(duration: 0.2, bounce: 0.0)) {
                                confirmingCallID = enriched.id
                            }
                        }
                    }

                    if confirmingCallID == enriched.id,
                       let call = enriched.decode.message.callerCallsign
                    {
                        callConfirmBar(call: call, decode: enriched.decode)
                    }
                }
                .id(enriched.id)
            }
        }
    }

    // MARK: - All Activity Section

    @ViewBuilder
    private var allActivitySection: some View {
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
                    compactActivityRow(enriched)
                        .id(enriched.id)
                }
            }
        }
    }

    // MARK: - Helpers

    private func sectionHeader(
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

    private func callConfirmBar(call: String, decode: FT8DecodeResult) -> some View {
        HStack {
            Button("Call \(call)") {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                onCallStation(decode)
                confirmingCallID = nil
            }
            .font(.caption.bold())
            .buttonStyle(.bordered)
            .tint(.accentColor)

            Spacer()

            Button("Cancel") {
                withAnimation(.spring(duration: 0.2, bounce: 0.0)) {
                    confirmingCallID = nil
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

    private func compactActivityRow(_ enriched: FT8EnrichedDecode) -> some View {
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
}
