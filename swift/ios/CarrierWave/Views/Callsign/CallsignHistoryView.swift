import CarrierWaveCore
import CarrierWaveData
import SwiftData
import SwiftUI

// MARK: - CallsignHistoryView

/// Unified history page for any callsign — shows identity, QSOs, recordings, and friend activity.
struct CallsignHistoryView: View {
    // MARK: Internal

    let callsign: String

    @Environment(\.modelContext) var modelContext

    @State var qsos: [QSO] = []
    @State var friendship: Friendship?
    @State var callsignInfo: CallsignInfo?
    @State var clubs: [String] = []
    @State var ownProfile: UserProfile?
    @State var recordingItems: [RecordingWithRanges] = []
    @State var clipsByQSOId: [UUID: QSORecordingClip] = [:]
    @State var activityItems: [ActivityItem] = []
    @State var isLookingUp = true
    @State var activeRecording: WebSDRRecording?
    @State var playerEngine = RecordingPlaybackEngine()

    var uniqueBands: Set<String> {
        Set(qsos.map(\.band))
    }

    /// True when this view is showing the operator's own callsign — used
    /// to hide QSO history (already surfaced in the Logs tab and
    /// Dashboard) from one's own profile page.
    var isOwnProfile: Bool {
        guard
            let mine = try? KeychainHelper.shared.readString(
                for: KeychainHelper.Keys.currentCallsign
            )
        else {
            return false
        }
        return mine.uppercased() == callsign.uppercased()
    }

    var totalRecordedSeconds: Double {
        let recTotal = recordingItems.reduce(into: 0.0) {
            $0 += $1.recording.durationSeconds
        }
        let clipTotal = clipsByQSOId.values.reduce(into: 0.0) {
            $0 += ($1.endOffset - $1.startOffset)
        }
        return recTotal + clipTotal
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                CallsignHistoryHeader(
                    callsign: callsign,
                    callsignInfo: callsignInfo,
                    friendship: friendship,
                    isLookingUp: isLookingUp,
                    clubs: clubs,
                    ownProfile: isOwnProfile ? ownProfile : nil
                )

                BadgesStripCard(callsign: callsign)

                CallsignNotesSection(
                    callsign: callsign,
                    callsignInfo: callsignInfo
                )

                if !isOwnProfile {
                    CallsignStatsRow(
                        qsoCount: qsos.count,
                        uniqueBands: uniqueBands,
                        totalRecordedSeconds: totalRecordedSeconds
                    )
                }

                if let grid = callsignInfo?.grid, !grid.isEmpty {
                    CallsignMapSection(grid: grid, callsign: callsign)
                }

                if !isOwnProfile, uniqueBands.count >= 2 {
                    CallsignBandModeChart(qsos: qsos)
                }

                if !isOwnProfile {
                    CallsignQSOTimeline(
                        qsos: qsos,
                        clipsByQSOId: clipsByQSOId
                    )
                }

                if !recordingItems.isEmpty {
                    CallsignTuneInRecordings(
                        items: recordingItems,
                        onPlay: playRecording
                    )
                }

                if friendship?.isAccepted == true {
                    CallsignActivitySection(
                        callsign: callsign,
                        activityItems: activityItems
                    )
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(callsign)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                EnrichedShareButton(payload: sharePayload)
            }
        }
        .safeAreaInset(edge: .bottom) {
            miniPlayerOverlay
        }
        .task {
            await loadData()
        }
    }

    // MARK: - Mini Player

    @ViewBuilder
    var miniPlayerOverlay: some View {
        if let recording = activeRecording {
            CallsignMiniPlayer(
                recording: recording,
                engine: playerEngine,
                onClose: closeMiniPlayer
            )
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    func playRecording(
        _ recording: WebSDRRecording,
        seekOffset: TimeInterval?
    ) {
        // Load new recording if switching (load() calls stop() internally)
        if activeRecording?.id != recording.id {
            guard let fileURL = recording.fileURL else {
                return
            }
            try? playerEngine.load(
                fileURL: fileURL,
                qsoTimestamps: [],
                recordingStart: recording.startedAt,
                segments: recording.segments
            )
        }
        if let offset = seekOffset {
            playerEngine.seek(to: offset)
        }
        playerEngine.play()
        withAnimation(.easeInOut(duration: 0.25)) {
            activeRecording = recording
        }
    }

    func closeMiniPlayer() {
        playerEngine.stop()
        withAnimation(.easeInOut(duration: 0.25)) {
            activeRecording = nil
        }
    }

    // MARK: Private

    private var sharePayload: EnrichedLinkPayload {
        EnrichedLinkPayload.callsign(
            callsign,
            name: callsignInfo?.displayName,
            grid: callsignInfo?.grid,
            qth: callsignInfo?.qth,
            country: callsignInfo?.country,
            workedCount: qsos.isEmpty ? nil : qsos.count,
            lastWorked: qsos.first?.timestamp,
            lastBand: qsos.first?.band,
            lastMode: qsos.first?.mode
        )
    }
}

// MARK: - QSOMetadataHelper

// MARK: - Preview

#Preview {
    NavigationStack {
        CallsignHistoryView(callsign: "W1AW")
    }
    .modelContainer(
        for: [QSO.self, WebSDRRecording.self, ActivityItem.self],
        inMemory: true
    )
}
