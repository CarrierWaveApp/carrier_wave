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
    @AppStorage("ft8CompactMode") private var isCompactMode = false

    private var directedDecodes: [FT8EnrichedDecode] {
        enrichedDecodes.filter { $0.section == .directedAtYou }
    }

    private var cqDecodes: [FT8EnrichedDecode] {
        enrichedDecodes
            .filter { $0.section == .callingCQ }
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
                .id(enriched.id)
                .onTapGesture {
                    if enriched.decode.message.isCallable {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        onCallStation(enriched.decode)
                    }
                }
            }
        }
    }

    // MARK: - All Activity Section

    @ViewBuilder
    private var allActivitySection: some View {
        if !activityDecodes.isEmpty {
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
