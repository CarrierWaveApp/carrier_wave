//
//  FT8DecodeListView.swift
//  CarrierWave
//

import CarrierWaveData
import SwiftUI
import UIKit

struct FT8DecodeListView: View {
    /// Cycles a CQ row stays visible after the station's most recent activity (~2 minutes).
    static let cqLiveWindow = 8

    let enrichedDecodes: [FT8EnrichedDecode]
    let currentCycleIDs: Set<UUID>
    var isFocusMode = false
    /// Callsign of the station currently in QSO (auto-watched until the QSO ends).
    var qsoCallsign: String?
    let onCallStation: (FT8DecodeResult) -> Void

    @State var isAllActivityExpanded = true
    @State var confirmingCallID: UUID?
    @State var watchedCallsign: String?
    @AppStorage("ft8CompactMode") var isCompactMode = false

    var directedDecodes: [FT8EnrichedDecode] {
        // Defensive `isFromMe` filter — a parsed FT8 message can't actually
        // be directed at the operator from the operator, but skipping it
        // here means a future change to the directed-at-me logic can't
        // regress this guard.
        enrichedDecodes.filter { $0.section == .directedAtYou && !$0.isFromMe }
    }

    /// One row per callsign that has called CQ within our buffer and has had any activity
    /// (CQ or otherwise) within the last `Self.cqLiveWindow` cycles. Keeps stations visible
    /// while they're mid-exchange so they don't disappear the moment they answer someone.
    /// Sorted alphabetically by callsign.
    var cqDecodes: [FT8EnrichedDecode] {
        var mostRecentCQ: [String: FT8EnrichedDecode] = [:]
        var mostRecentActivityAge: [String: Int] = [:]

        for enriched in enrichedDecodes {
            // Skip our own transmission (audio loopback) — calling yourself is
            // never the right action, and the row would clutter the list while
            // we're calling CQ.
            if enriched.isFromMe {
                continue
            }
            guard let call = enriched.decode.message.callerCallsign else {
                continue
            }
            let key = call.uppercased()

            if enriched.section == .callingCQ {
                if let existing = mostRecentCQ[key] {
                    if enriched.cycleAge < existing.cycleAge {
                        mostRecentCQ[key] = enriched
                    }
                } else {
                    mostRecentCQ[key] = enriched
                }
            }

            let prev = mostRecentActivityAge[key] ?? Int.max
            mostRecentActivityAge[key] = min(prev, enriched.cycleAge)
        }

        return mostRecentCQ.values
            .filter { cq in
                guard let call = cq.decode.message.callerCallsign else {
                    return false
                }
                let key = call.uppercased()
                let recent = mostRecentActivityAge[key] ?? Int.max
                return recent < Self.cqLiveWindow && !(isFocusMode && cq.isDupe)
            }
            .sorted { lhs, rhs in
                let lhsCall = lhs.decode.message.callerCallsign?.uppercased() ?? ""
                let rhsCall = rhs.decode.message.callerCallsign?.uppercased() ?? ""
                return lhsCall < rhsCall
            }
    }

    /// One row per callsign currently mid-exchange with someone else (not in CQ list,
    /// not directed at us). Shows their most-recent decode, sorted alphabetically.
    var activityDecodes: [FT8EnrichedDecode] {
        let cqCalls = Set(cqDecodes.compactMap { $0.decode.message.callerCallsign?.uppercased() })
        var mostRecentByCall: [String: FT8EnrichedDecode] = [:]

        for enriched in enrichedDecodes {
            guard enriched.section == .allActivity,
                  !enriched.isFromMe,
                  enriched.cycleAge < Self.cqLiveWindow,
                  let call = enriched.decode.message.callerCallsign
            else {
                continue
            }
            let key = call.uppercased()
            if cqCalls.contains(key) {
                continue
            }
            if isFocusMode, enriched.isDupe {
                continue
            }

            if let existing = mostRecentByCall[key], enriched.cycleAge >= existing.cycleAge {
                continue
            }
            mostRecentByCall[key] = enriched
        }

        return mostRecentByCall.values.sorted { lhs, rhs in
            let lhsCall = lhs.decode.message.callerCallsign?.uppercased() ?? ""
            let rhsCall = rhs.decode.message.callerCallsign?.uppercased() ?? ""
            return lhsCall < rhsCall
        }
    }

    /// Active watched callsign — prefer the in-QSO callsign when set, otherwise the user's manual pick.
    var effectiveWatchedCallsign: String? {
        qsoCallsign ?? watchedCallsign
    }

    var watchedDecodes: [FT8EnrichedDecode] {
        guard let watched = effectiveWatchedCallsign else {
            return []
        }
        return enrichedDecodes.filter { $0.decode.message.involves(watched) }
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    directedSection
                    watchedCallsignSection
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
}
