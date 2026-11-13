import AppKit
import CarrierWaveCore
import SwiftUI

// MARK: - Interaction

extension ContestBandScopeView {
    func handleKeyPress(_ keyPress: KeyPress) -> KeyPress.Result {
        switch keyPress.key {
        case .escape:
            if showHelp {
                showHelp = false
                return .handled
            }
            return .ignored
        case KeyEquivalent("j"):
            return navigateSpot(direction: .down, multsOnly: false)
        case KeyEquivalent("k"):
            return navigateSpot(direction: .upward, multsOnly: false)
        case KeyEquivalent("J"):
            return navigateSpot(direction: .down, multsOnly: true)
        case KeyEquivalent("K"):
            return navigateSpot(direction: .upward, multsOnly: true)
        case .return:
            if let spot = selectionState.selectedSpot {
                quickEntrySpot(spot)
                return .handled
            }
            return .ignored
        case KeyEquivalent("m"):
            if let freq = cursorFreqKHz {
                let bookmark = FrequencyBookmark(frequencyKHz: freq, bandId: selectedBandId)
                bookmarks.append(bookmark)
                return .handled
            }
            return .ignored
        case KeyEquivalent("?"):
            showHelp.toggle()
            return .handled
        case .downArrow,
             .upArrow,
             .leftArrow,
             .rightArrow:
            return .ignored
        default:
            return handleZoomKeyPress(keyPress)
        }
    }

    private func handleZoomKeyPress(_ keyPress: KeyPress) -> KeyPress.Result {
        switch keyPress.key {
        case KeyEquivalent("+"),
             KeyEquivalent("="):
            adjustZoom(by: 1.0)
            return .handled
        case KeyEquivalent("-"):
            adjustZoom(by: -1.0)
            return .handled
        case KeyEquivalent("0"):
            fitToSpots()
            return .handled
        case KeyEquivalent("h"):
            if zoomScale > 1.0 {
                panOffset = clampPan(panOffset - 0.05 / zoomScale)
                panBaseOffset = panOffset
                saveBandZoomState()
                return .handled
            }
            return .ignored
        case KeyEquivalent("l"):
            if zoomScale > 1.0 {
                panOffset = clampPan(panOffset + 0.05 / zoomScale)
                panBaseOffset = panOffset
                saveBandZoomState()
                return .handled
            }
            return .ignored
        default:
            return .ignored
        }
    }

    func handleMiniMapTap(at location: CGPoint, railHeight: CGFloat) {
        guard selectedBand != nil else {
            return
        }
        let plotTop: CGFloat = 16
        let plotBottom = railHeight - 16
        let plotHeight = plotBottom - plotTop
        guard plotHeight > 0 else {
            return
        }

        let frac = (location.y - plotTop) / plotHeight
        let clampedFrac = min(max(frac, 0), 1)
        panOffset = clampPan(clampedFrac)
        panBaseOffset = panOffset
        saveBandZoomState()
    }

    func handleTap(at location: CGPoint, canvasHeight: CGFloat) {
        if let tapped = hitRects.spot(at: location) {
            selectionState.selectedSpot = tapped
            selectionState.selectedQSOId = nil
            SpotEntryBridge.shared.pendingSpot = tapped
            return
        }

        guard let band = selectedBand else {
            return
        }

        let clickedFreq = freqForYPos(location.y, band: band, height: canvasHeight)

        let family = ModeEquivalence.family(for: radioManager.mode)
        let snapKHz = switch family {
        case .cw: 0.5
        case .digital: 2.0
        case .phone: 5.0
        case .other: 2.0
        }

        let nearest = sortedSpots.min(by: {
            abs($0.spot.frequencyKHz - clickedFreq) < abs($1.spot.frequencyKHz - clickedFreq)
        })
        if let nearest, abs(nearest.spot.frequencyKHz - clickedFreq) <= snapKHz {
            tuneToSpot(nearest)
        } else {
            Task {
                await radioManager.tuneToSpot(
                    frequencyMHz: clickedFreq / 1_000,
                    mode: radioManager.mode,
                    autoXITEnabled: autoXITEnabled,
                    autoXITOffsetHz: autoXITOffsetHz
                )
            }
        }
    }

    func tuneToSpot(_ spot: EnrichedSpot) {
        SpotEntryBridge.shared.pendingSpot = spot
        selectionState.selectedSpot = spot
        selectionState.selectedQSOId = nil
        Task {
            await radioManager.tuneToSpot(
                frequencyMHz: spot.spot.frequencyMHz,
                mode: spot.spot.mode,
                autoXITEnabled: autoXITEnabled,
                autoXITOffsetHz: autoXITOffsetHz
            )
        }
    }

    /// Tune to a spot and push its callsign/freq/mode into the quick-entry
    /// bar, focusing the field for immediate logging. Mirrors the
    /// `tuneAndLog` flow used by `SpotListView`.
    func quickEntrySpot(_ spot: EnrichedSpot) {
        let freqStr = String(format: "%.3f", spot.spot.frequencyMHz)
        let mode = spot.spot.mode
        selectionState.pendingSpotEntry = mode.isEmpty
            ? "\(spot.spot.callsign) \(freqStr)"
            : "\(spot.spot.callsign) \(freqStr) \(mode)"
        SpotEntryBridge.shared.pendingSpot = spot
        selectionState.selectedSpot = spot
        selectionState.selectedQSOId = nil
        Task {
            await radioManager.tuneToSpot(
                frequencyMHz: spot.spot.frequencyMHz,
                mode: spot.spot.mode,
                autoXITEnabled: autoXITEnabled,
                autoXITOffsetHz: autoXITOffsetHz
            )
        }
    }

    func handleDoubleTap(at location: CGPoint) {
        guard let tapped = hitRects.spot(at: location) else {
            return
        }
        quickEntrySpot(tapped)
    }

    enum NavDirection {
        case upward
        case down
    }

    func navigateSpot(direction: NavDirection, multsOnly: Bool) -> KeyPress.Result {
        let candidates = multsOnly
            ? sortedSpots.filter { $0.neededStatus == .newEntity || $0.neededStatus == .newBandSlot }
            : sortedSpots
        guard !candidates.isEmpty else {
            return .ignored
        }

        // Find current position: selected spot index, or nearest to VFO
        let currentIdx: Int?
        if let selected = selectionState.selectedSpot {
            currentIdx = candidates.firstIndex { $0.id == selected.id }
        } else {
            let radioFreqKHz = radioManager.frequency * 1_000
            if radioFreqKHz > 0 {
                currentIdx = candidates.firstIndex {
                    $0.spot.frequencyKHz > radioFreqKHz - 0.1
                }
            } else {
                // No radio, no selection — start from first/last
                currentIdx = nil
            }
        }

        let target: EnrichedSpot? = switch direction {
        case .down:
            if let idx = currentIdx, idx + 1 < candidates.count {
                candidates[idx + 1]
            } else {
                candidates.first
            }
        case .upward:
            if let idx = currentIdx, idx > 0 {
                candidates[idx - 1]
            } else {
                candidates.last
            }
        }

        return selectSpot(target)
    }

    private func selectSpot(_ spot: EnrichedSpot?) -> KeyPress.Result {
        guard let spot else {
            return .ignored
        }
        selectionState.selectedSpot = spot
        selectionState.selectedQSOId = nil
        SpotEntryBridge.shared.pendingSpot = spot
        // If radio connected, also tune
        if radioManager.frequency > 0 {
            Task {
                await radioManager.tuneToSpot(
                    frequencyMHz: spot.spot.frequencyMHz,
                    mode: spot.spot.mode,
                    autoXITEnabled: autoXITEnabled,
                    autoXITOffsetHz: autoXITOffsetHz
                )
            }
        }
        return .handled
    }

    func autoSwitchBand(frequency freqMHz: Double) {
        let freqKHz = freqMHz * 1_000
        if let band = BandEdges.band(for: freqKHz), band.id != selectedBandId {
            saveBandZoomState()
            selectedBandId = band.id
            restoreBandZoomState()
        }
    }
}

// MARK: - Context Menu

extension ContestBandScopeView {
    func spotContextMenuActions(for spot: EnrichedSpot) -> some View {
        Group {
            Button {
                tuneToSpot(spot)
            } label: {
                Label(
                    "Tune to \(String(format: "%.1f", spot.spot.frequencyKHz))",
                    systemImage: "antenna.radiowaves.left.and.right"
                )
            }

            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(spot.spot.callsign, forType: .string)
            } label: {
                Label("Copy Callsign", systemImage: "doc.on.doc")
            }

            Divider()

            Button {
                let callsign = spot.spot.callsign
                    .addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? spot.spot.callsign
                if let url = URL(string: "https://www.qrz.com/db/\(callsign)") {
                    NSWorkspace.shared.open(url)
                }
            } label: {
                Label("Lookup on QRZ", systemImage: "safari")
            }

            Button {
                if let freq = cursorFreqKHz {
                    let bookmark = FrequencyBookmark(frequencyKHz: freq, bandId: selectedBandId)
                    bookmarks.append(bookmark)
                } else {
                    let bookmark = FrequencyBookmark(
                        frequencyKHz: spot.spot.frequencyKHz,
                        bandId: selectedBandId
                    )
                    bookmarks.append(bookmark)
                }
            } label: {
                Label("Add Watch Marker", systemImage: "bookmark")
            }

            Button {
                selectionState.selectedSpot = spot
                selectionState.selectedQSOId = nil
            } label: {
                Label("Show in Spot List", systemImage: "list.bullet")
            }
        }
    }
}

// MARK: - Scroll & Zoom

extension ContestBandScopeView {
    func handleScrollWheel(event: ScrollWheelEvent) {
        if zoomScale > 1.01, !event.isShiftHeld {
            let panDelta = event.deltaY * 0.01 / zoomScale
            panOffset = clampPan(panOffset - panDelta)
            panBaseOffset = panOffset
        } else {
            let zoomDelta = 1.0 + event.deltaY * 0.05
            let newZoom = max(1.0, min(16.0, zoomScale * zoomDelta))
            zoomScale = newZoom
            zoomBaseScale = newZoom
            panOffset = clampPan(panOffset)
            panBaseOffset = panOffset
        }
        saveBandZoomState()
    }

    func adjustZoom(by delta: CGFloat) {
        let newZoom = max(1.0, min(16.0, zoomScale + delta))
        zoomScale = newZoom
        zoomBaseScale = newZoom
        panOffset = clampPan(panOffset)
        panBaseOffset = panOffset
        saveBandZoomState()
    }

    func resetZoom() {
        zoomScale = 1.0
        zoomBaseScale = 1.0
        panOffset = 0.5
        panBaseOffset = 0.5
        saveBandZoomState()
    }

    func fitToSpots() {
        let spots = sortedSpots
        guard let band = selectedBand,
              let first = spots.first,
              let last = spots.last
        else {
            resetZoom()
            return
        }
        let lowestKHz = first.spot.frequencyKHz
        let highestKHz = last.spot.frequencyKHz
        let spanKHz = max(highestKHz - lowestKHz, 5.0)
        let paddedSpan = spanKHz * 1.1
        let centerKHz = (lowestKHz + highestKHz) / 2
        let newZoom = band.widthKHz / paddedSpan
        let centerFrac = (centerKHz - band.lowerKHz) / band.widthKHz
        zoomScale = max(1.0, min(16.0, newZoom))
        zoomBaseScale = zoomScale
        panOffset = clampPan(centerFrac)
        panBaseOffset = panOffset
        saveBandZoomState()
    }

    func zoomToRegion(_ preset: ZoomRegionPreset) {
        guard let band = selectedBand, preset.bandId == band.id else {
            return
        }
        let regionWidth = preset.upperKHz - preset.lowerKHz
        let newZoom = band.widthKHz / regionWidth
        let centerFrac = ((preset.lowerKHz + preset.upperKHz) / 2 - band.lowerKHz) / band.widthKHz

        zoomScale = max(1.0, min(16.0, newZoom))
        zoomBaseScale = zoomScale
        panOffset = clampPan(centerFrac)
        panBaseOffset = panOffset
        saveBandZoomState()
    }

    func saveBandZoomState() {
        bandZoomStates[selectedBandId] = PerBandZoomState(zoom: zoomScale, pan: panOffset)
    }

    func restoreBandZoomState() {
        if let state = bandZoomStates[selectedBandId] {
            zoomScale = state.zoom
            zoomBaseScale = state.zoom
            panOffset = state.pan
            panBaseOffset = state.pan
        } else {
            zoomScale = 1.0
            zoomBaseScale = 1.0
            panOffset = 0.5
            panBaseOffset = 0.5
        }
    }
}
