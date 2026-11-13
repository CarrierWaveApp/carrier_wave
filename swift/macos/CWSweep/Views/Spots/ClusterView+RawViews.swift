import SwiftUI

// MARK: - All Spots Table + Raw Scrollback

extension ClusterView {
    // MARK: - All Spots (raw cluster spots, unfiltered)

    var spotTableView: some View {
        VStack(alignment: .leading, spacing: 0) {
            Table(of: DXClusterSpot.self) {
                TableColumn("Time") { spot in
                    Text(formatTime(spot.timestamp))
                        .font(.caption.monospacedDigit())
                }
                .width(min: 35, ideal: 45)

                TableColumn("Callsign") { spot in
                    allSpotsCallsignCell(for: spot)
                }
                .width(min: 70, ideal: 90)

                TableColumn("Freq") { spot in
                    Text(String(format: "%.1f", spot.frequencyKHz))
                        .monospacedDigit()
                }
                .width(min: 55, ideal: 70)

                TableColumn("Mode") { spot in
                    Text(spot.parsedMode)
                        .font(.caption)
                }
                .width(min: 35, ideal: 50)

                TableColumn("Spotter") { spot in
                    Text(spot.spotter)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .width(min: 60, ideal: 80)

                TableColumn("Comment") { spot in
                    Text(spot.comment)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .width(min: 80, ideal: 120)
            } rows: {
                ForEach(clusterManager.parsedSpots) { spot in
                    TableRow(spot)
                        .contextMenu {
                            clusterTuneAndLogButton(for: spot)
                        }
                }
            }
            .alternatingRowBackgrounds()
        }
    }

    // MARK: - Raw Scrollback

    var scrollbackView: some View {
        VStack(spacing: 0) {
            scrollbackContent
            if scrollbackPaused || !isScrolledToBottom {
                scrollbackStatusBar
            }
        }
        .background(.background.secondary)
    }

    // MARK: Private

    private var visibleLines: [ClusterLine] {
        if scrollbackPaused {
            return Array(clusterManager.scrollback.prefix(pausedAtCount))
        }
        return clusterManager.scrollback
    }

    private var bufferedCount: Int {
        guard scrollbackPaused else {
            return 0
        }
        return max(0, clusterManager.scrollback.count - pausedAtCount)
    }

    private var scrollbackContent: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(visibleLines) { line in
                        Text(line.text)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(
                                line.isSpot ? Color.primary : Color.secondary
                            )
                            .padding(.horizontal, 8)
                            .padding(.vertical, 1)
                            .id(line.id)
                    }
                }
            }
            .onChange(of: clusterManager.scrollback.count) { _, _ in
                guard !scrollbackPaused, isScrolledToBottom else {
                    return
                }
                if let last = clusterManager.scrollback.last {
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
        }
    }

    private var scrollbackStatusBar: some View {
        HStack(spacing: 8) {
            Button {
                togglePause()
            } label: {
                Label(
                    scrollbackPaused ? "Resume" : "Pause",
                    systemImage: scrollbackPaused
                        ? "play.fill" : "pause.fill"
                )
                .font(.caption)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            if scrollbackPaused {
                if bufferedCount > 0 {
                    Text("\(bufferedCount) new")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.orange)
                }

                if let pauseTime = pausedAtTime {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        let elapsed = Int(
                            context.date.timeIntervalSince(pauseTime)
                        )
                        Text("paused \(elapsed)s")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                Text("Scrolled up — new lines arriving below")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button("Jump to bottom") {
                    isScrolledToBottom = true
                }
                .buttonStyle(.borderless)
                .font(.caption)
            }

            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.ultraThinMaterial)
    }

    private func togglePause() {
        if scrollbackPaused {
            // Resume: show all lines
            scrollbackPaused = false
            pausedAtTime = nil
            isScrolledToBottom = true
        } else {
            // Pause: freeze visible lines
            scrollbackPaused = true
            pausedAtCount = clusterManager.scrollback.count
            pausedAtTime = Date()
        }
    }

    private func allSpotsCallsignCell(for spot: DXClusterSpot) -> some View {
        let isWorked = workedChecker.isWorked(
            callsign: spot.callsign,
            band: spot.band,
            mode: spot.parsedMode
        )

        return Text(spot.callsign)
            .fontWeight(.medium)
            .strikethrough(isWorked, color: .secondary)
            .foregroundStyle(isWorked ? .secondary : .primary)
    }
}
