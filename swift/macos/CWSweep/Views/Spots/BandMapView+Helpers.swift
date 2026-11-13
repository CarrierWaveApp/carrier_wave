import CarrierWaveCore
import SwiftUI

// MARK: - ResolvedSpotItem

/// A spot with its pre-measured label for layout
struct ResolvedSpotItem {
    let spot: EnrichedSpot
    let resolvedText: GraphicsContext.ResolvedText
    let labelWidth: CGFloat
    let xPos: CGFloat
    let isProminent: Bool
    let isInProximity: Bool
    let modeMatches: Bool
    let isSelected: Bool
}

// MARK: - BandMapView + Helpers

extension BandMapView {
    // MARK: - Priority & Sorting

    /// Priority score for lane assignment. Higher = more important = placed first.
    func spotPriority(_ spot: EnrichedSpot) -> Int {
        var score = 0

        switch spot.neededStatus {
        case .newEntity: score += 100
        case .newBandSlot: score += 80
        case .workedNotConfirmed: score += 20
        case .unknown: score += 40
        case .confirmed: score += 10
        }

        // Activators (POTA/SOTA/WWFF) get a bonus
        if spot.spot.referenceDisplay != nil {
            score += 30
        }

        // The operator's own spot always earns a prominent lane
        if isSelfSpot(spot) {
            score += 60
        }

        // Mode match bonus
        if modeMatchesRadio(spot.spot.mode) {
            score += 25
        }

        // Proximity bonus
        if isInProximityZone(spot.spot.frequencyKHz) {
            score += 15
        }

        // Recency bonus (newer = higher)
        let ageMinutes = Date().timeIntervalSince(spot.spot.timestamp) / 60
        if ageMinutes < 5 {
            score += 10
        } else if ageMinutes < 15 {
            score += 5
        }

        return score
    }

    /// Whether `spot` is the operator's own — same rule as the spots list.
    func isSelfSpot(_ spot: EnrichedSpot) -> Bool {
        SpotListOrdering.isSelfSpot(spot, userCallsign: myCallsign)
    }

    // MARK: - Mode Matching

    func modeMatchesRadio(_ spotMode: String) -> Bool {
        let radioMode = radioManager.mode
        guard !radioMode.isEmpty else {
            return true
        }
        let radioFamily = ModeEquivalence.family(for: radioMode)
        let spotFamily = ModeEquivalence.family(for: spotMode)
        return radioFamily == spotFamily
    }

    // MARK: - Proximity

    func proximityHalfWidthKHz() -> Double {
        let radioMode = radioManager.mode
        let family = ModeEquivalence.family(for: radioMode)
        switch family {
        case .cw: return 3.0
        case .digital: return 5.0
        case .phone: return 15.0
        case .other: return 10.0
        }
    }

    func isInProximityZone(_ freqKHz: Double) -> Bool {
        let radioFreqKHz = radioManager.frequency * 1_000
        let halfWidth = proximityHalfWidthKHz()
        return abs(freqKHz - radioFreqKHz) <= halfWidth
    }

    // MARK: - Label Resolution

    func resolveSpotLabels(
        context: inout GraphicsContext,
        band: BandEdge,
        size: CGSize
    ) -> [ResolvedSpotItem] {
        let radioFreqKHz = radioManager.frequency * 1_000
        let cursorOnBand = radioFreqKHz >= band.lowerKHz && radioFreqKHz <= band.upperKHz
        let selectedId = selectionState.selectedSpot?.id

        return prioritizedSpots.map { spot in
            let xPos = zoomedXPosition(frequencyKHz: spot.spot.frequencyKHz, band: band, width: size.width)
            let inProximity = cursorOnBand && isInProximityZone(spot.spot.frequencyKHz)
            let modeMatch = modeMatchesRadio(spot.spot.mode)
            let isProminent = spot.neededStatus == .newEntity || spot.neededStatus == .newBandSlot

            let fontSize: CGFloat = inProximity ? 10 : 9
            let weight: Font.Weight = isProminent ? .bold : .medium
            let text = Text(spot.spot.callsign)
                .font(.system(size: fontSize, weight: weight, design: .monospaced))
                .foregroundStyle(.white)
            let resolved = context.resolve(text)
            let measured = resolved.measure(in: CGSize(width: 200, height: 30))

            return ResolvedSpotItem(
                spot: spot,
                resolvedText: resolved,
                labelWidth: measured.width + chipPaddingH * 2,
                xPos: xPos,
                isProminent: isProminent,
                isInProximity: inProximity,
                modeMatches: modeMatch,
                isSelected: spot.id == selectedId
            )
        }
    }

    // MARK: - Lane Assignment

    func assignLanes(
        resolved: [ResolvedSpotItem],
        maxLanes: Int
    ) -> [[ResolvedSpotItem]] {
        var lanes: [[ResolvedSpotItem]] = []

        for item in resolved {
            var placed = false
            for laneIdx in lanes.indices where laneIdx < maxLanes {
                let overlaps = lanes[laneIdx].contains { existing in
                    let gap: CGFloat = 4
                    let halfA = item.labelWidth / 2
                    let halfB = existing.labelWidth / 2
                    return abs(item.xPos - existing.xPos) < (halfA + halfB + gap)
                }
                if !overlaps {
                    lanes[laneIdx].append(item)
                    placed = true
                    break
                }
            }
            if !placed, lanes.count < maxLanes {
                lanes.append([item])
            }
            // If no room, spot is dropped (lowest priority dropped first since we iterate by priority)
        }

        return lanes
    }

    // MARK: - Spot Aging

    /// Source-aware aging factor. Higher = ages faster.
    func ageFactor(for source: SpotSource) -> Double {
        switch source {
        case .rbn: 2.0
        case .cluster: 1.0
        case .pota,
             .sota,
             .wwff: 0.5
        case .dxSummit,
             .dxHeat,
             .dxWatch: 1.0
        }
    }

    /// Effective age in seconds, adjusted by source aging factor
    func effectiveAge(for spot: EnrichedSpot) -> Double {
        let actualAge = Date().timeIntervalSince(spot.spot.timestamp)
        return actualAge * ageFactor(for: spot.spot.source)
    }

    /// Opacity based on source-aware effective age and max age setting
    func ageOpacity(for spot: EnrichedSpot) -> Double {
        let maxSeconds = Double(maxAgeMinutes) * 60
        let effective = effectiveAge(for: spot)
        return max(0.2, 1.0 - (effective / maxSeconds) * 0.8)
    }

    /// Whether a spot has expired based on source-aware aging
    func isExpired(_ spot: EnrichedSpot) -> Bool {
        effectiveAge(for: spot) > Double(maxAgeMinutes) * 60
    }

    // MARK: - Chip Drawing

    func drawSpotChip(
        item: ResolvedSpotItem,
        yOffset: CGFloat,
        context: inout GraphicsContext,
        rects: inout [(CGRect, EnrichedSpot)]
    ) {
        let spot = item.spot
        let chipHeight = item.isProminent ? prominentMarkerHeight : markerHeight

        // Source-aware age-based opacity
        var opacity = ageOpacity(for: spot)

        // Dim non-mode-matching spots
        if !item.modeMatches {
            opacity *= 0.45
        }

        // Boost proximity spots slightly
        if item.isInProximity {
            opacity = min(1.0, opacity * 1.15)
        }

        let color = markerColor(for: spot)
        let chipWidth = item.labelWidth
        let rect = CGRect(
            x: item.xPos - chipWidth / 2,
            y: yOffset,
            width: chipWidth,
            height: chipHeight
        )
        let chipPath = Path(roundedRect: rect, cornerRadius: 4)

        // Draw chip based on needed status and mode match
        drawChipBackground(
            context: &context, path: chipPath,
            item: item, color: color, opacity: opacity
        )

        drawChipEmphasis(context: &context, rect: rect, item: item, opacity: opacity)

        // Label text with appropriate color
        let textColor = chipTextColor(for: spot, modeMatches: item.modeMatches, opacity: opacity)
        let fontSize: CGFloat = item.isInProximity ? 10 : 9
        let weight: Font.Weight = item.isProminent ? .bold : .medium
        let labelText = Text(spot.spot.callsign)
            .font(.system(size: fontSize, weight: weight, design: .monospaced))
            .foregroundStyle(textColor)
        context.draw(
            context.resolve(labelText),
            at: CGPoint(x: item.xPos, y: yOffset + chipHeight / 2),
            anchor: .center
        )

        rects.append((rect, spot))
    }

    /// Selection ring, own-spot ring and left-edge bar. Split out of
    /// `drawSpotChip` to keep that function under the lint body limit.
    private func drawChipEmphasis(
        context: inout GraphicsContext,
        rect: CGRect,
        item: ResolvedSpotItem,
        opacity: Double
    ) {
        let spot = item.spot

        // Selection highlight ring
        if item.isSelected {
            let selRect = rect.insetBy(dx: -2, dy: -2)
            let selPath = Path(roundedRect: selRect, cornerRadius: 5)
            context.stroke(selPath, with: .color(Color(nsColor: .systemYellow)), lineWidth: 2)
        }

        // Operator's own spot: accent ring + accent left bar, matching the
        // spots list (CAR-204). Selection ring (yellow) still wins on top.
        let isSelf = isSelfSpot(spot)
        if isSelf, !item.isSelected {
            let ringRect = rect.insetBy(dx: -1.5, dy: -1.5)
            let ringPath = Path(roundedRect: ringRect, cornerRadius: 5)
            context.stroke(ringPath, with: .color(Color.accentColor.opacity(opacity)), lineWidth: 1.5)
        }

        // Left-edge accent bar: accent for self, green for activators
        if isSelf || spot.spot.referenceDisplay != nil {
            let barColor = isSelf ? Color.accentColor : Color(nsColor: .systemGreen)
            let accentRect = CGRect(x: rect.minX, y: rect.minY, width: 3, height: rect.height)
            let accentPath = Path(roundedRect: accentRect, cornerRadius: 1.5)
            context.fill(accentPath, with: .color(barColor.opacity(opacity)))
        }
    }

    // MARK: - Chip Background Styles

    private func drawChipBackground(
        context: inout GraphicsContext,
        path: Path,
        item: ResolvedSpotItem,
        color: Color,
        opacity: Double
    ) {
        let fillMult: Double
        let strokeMult: Double
        let strokeWidth: CGFloat

        switch item.spot.neededStatus {
        case .newEntity:
            fillMult = 0.85; strokeMult = 1.0; strokeWidth = 1
        case .newBandSlot:
            fillMult = 0.75; strokeMult = 1.0; strokeWidth = 1
        case .workedNotConfirmed:
            fillMult = 0.08; strokeMult = 0.4; strokeWidth = 0.5
        case .confirmed:
            fillMult = 0.06; strokeMult = 0.3; strokeWidth = 0.5
        case .unknown:
            fillMult = item.modeMatches ? 0.35 : 0.1
            strokeMult = item.modeMatches ? 0.7 : 0.4
            strokeWidth = 0.5
        }

        context.fill(path, with: .color(color.opacity(opacity * fillMult)))
        context.stroke(
            path,
            with: .color(color.opacity(opacity * strokeMult)),
            lineWidth: strokeWidth
        )
    }

    // MARK: - Text Colors

    private func chipTextColor(for spot: EnrichedSpot, modeMatches: Bool, opacity: Double) -> Color {
        switch colorMode {
        case .source,
             .freshness:
            // Source/freshness modes: light text on colored backgrounds
            let baseColor = markerColor(for: spot)
            return baseColor.opacity(modeMatches ? opacity : opacity * 0.6)
        case .contest,
             .dxcc:
            // DXCC/contest modes: text adapts to needed status fill intensity
            switch spot.neededStatus {
            case .newEntity,
                 .newBandSlot:
                return .white.opacity(opacity)
            case .workedNotConfirmed:
                return Color(nsColor: .systemGray).opacity(opacity * 0.6)
            case .confirmed:
                return Color(nsColor: .systemGreen).opacity(opacity * 0.5)
            case .unknown:
                let baseColor = markerColor(for: spot)
                return baseColor.opacity(modeMatches ? opacity : opacity * 0.6)
            }
        }
    }

    // MARK: - Marker Colors

    func markerColor(for spot: EnrichedSpot) -> Color {
        SpotColorScheme.markerColor(
            for: spot,
            mode: colorMode,
            isWorkedToday: false
        )
    }

    func tooltipNeededColor(_ status: NeededStatus) -> Color {
        switch status {
        case .newEntity: Color(nsColor: .systemRed)
        case .newBandSlot: Color(nsColor: .systemOrange)
        case .confirmed: Color(nsColor: .systemGreen)
        case .workedNotConfirmed,
             .unknown: .primary
        }
    }

    func autoSwitchBand(frequency freqMHz: Double) {
        let freqKHz = freqMHz * 1_000
        if let band = BandEdges.band(for: freqKHz) {
            selectedBandId = band.id
        }
    }
}
