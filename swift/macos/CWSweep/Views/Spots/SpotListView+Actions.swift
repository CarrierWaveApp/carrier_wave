import CarrierWaveCore
import CarrierWaveData
import SwiftData
import SwiftUI

// MARK: - SpotListView + Spot Table

extension SpotListView {
    var spotTable: some View {
        Table(of: EnrichedSpot.self, selection: $selection, sortOrder: $sortOrder) {
            identityColumns
            enrichmentColumns
        } rows: {
            ForEach(cachedFilteredSpots) { spot in
                TableRow(spot)
                    .contextMenu {
                        Button("Tune & Log") {
                            tuneAndLog(spot)
                        }
                        ForEach(RadioSlot.allCases) { slot in
                            if radioManager.slots[slot] != nil, slot != radioManager.focusedSlot {
                                Button("Tune \(slot.label)") {
                                    tuneSpot(spot, slot: slot)
                                }
                            }
                        }
                        Divider()
                        Button {
                            lookupOnQRZ(spot.spot.callsign)
                        } label: {
                            Label("Lookup \(spot.spot.callsign) on QRZ", systemImage: "safari")
                        }
                        if let footnote = spotTuneDestination.contextMenuFootnote {
                            Divider()
                            // Text in a menu renders as a disabled item: an
                            // explanation, not an action (CAR-121).
                            Text(footnote)
                        }
                    }
            }
        }
        .alternatingRowBackgrounds()
        .onChange(of: selection) { _, newSelection in
            if let selectedId = newSelection.first {
                selectionState.selectedSpot = cachedFilteredSpots.first { $0.id == selectedId }
                selectionState.selectedQSOId = nil
                selectionState.focusedPane = .spotList
            } else {
                selectionState.selectedSpot = nil
            }
        }
        .onChange(of: selectionState.selectedSpot?.id) { _, newId in
            guard let newId, selection.first != newId else {
                return
            }
            selection = [newId]
        }
        .onKeyPress(.return) {
            guard let selectedId = selection.first,
                  let spot = cachedFilteredSpots.first(where: { $0.id == selectedId })
            else {
                return .ignored
            }
            tuneAndLog(spot)
            return .handled
        }
        .onTableDoubleClick {
            guard let selectedId = selection.first,
                  let spot = cachedFilteredSpots.first(where: { $0.id == selectedId })
            else {
                return
            }
            tuneAndLog(spot)
        }
        .modifier(VimSpotNavigationModifier(
            selection: $selection,
            spots: cachedFilteredSpots,
            onTuneAndLog: tuneAndLog
        ))
    }

    // TableColumnBuilder caps a single block at 10 columns, so the columns are
    // split in two. Each half pins the table's sort comparator explicitly:
    // inside a bare `Group` an unsortable leading column makes the builder
    // infer `Never` and every sortable column after it fails to type-check.

    /// Leading gutter through Mode: identity and tuning columns.
    @TableColumnBuilder<EnrichedSpot, KeyPathComparator<EnrichedSpot>>
    private var identityColumns: some TableColumnContent<EnrichedSpot, KeyPathComparator<EnrichedSpot>> {
        // Narrow leading gutter: accent bar on the operator's own spot so
        // it reads as "you" before the eye reaches the callsign.
        TableColumn("") { (spot: EnrichedSpot) in
            selfSpotMarker(spot)
        }
        .width(6)

        TableColumn("Age", value: \.sortTimestamp) { spot in
            Text(spot.spot.timeAgo)
                .font(.caption.monospacedDigit())
                .foregroundStyle(ageColor(spot.spot.timestamp))
                .lineLimit(1)
        }
        .width(showAge ? 50 : 0)

        TableColumn("Source") { spot in
            Text(spot.spot.source.displayName)
                .font(.caption2)
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(SpotColorScheme.sourceColor(spot.spot.source).opacity(0.2))
                .clipShape(RoundedRectangle(cornerRadius: 3))
                .lineLimit(1)
        }
        .width(min: 30, ideal: 45)

        TableColumn("Callsign", value: \.sortCallsign) { spot in
            let isSelf = isSelfSpot(spot)
            HStack(spacing: 4) {
                if isSelf {
                    Image(systemName: "person.fill")
                        .font(.caption2)
                        .foregroundStyle(Color.accentColor)
                        .accessibilityHidden(true)
                }
                Text(spot.spot.callsign)
                    .fontWeight(isSelf ? .semibold : .medium)
                    .foregroundStyle(isSelf ? Color.accentColor : SpotColorScheme.neededColor(spot.neededStatus))
                    .lineLimit(1)
                // Badge budget is two per row (Status column + one here):
                // "You" wins over P2P — your own spot is never a P2P target.
                if isSelf {
                    youBadge
                } else if activeParkReference != nil, spot.spot.source == .pota {
                    p2pBadge
                }
            }
            .accessibilityLabel(isSelf ? "\(spot.spot.callsign), your spot" : spot.spot.callsign)
        }
        .width(min: 50, ideal: 80)

        TableColumn("Status") { spot in
            neededBadge(spot.neededStatus)
        }
        .width(min: showStatus ? 55 : 0, ideal: showStatus ? 75 : 0)

        TableColumn("Freq", value: \.sortFrequency) { spot in
            Text(String(format: "%.1f", spot.spot.frequencyKHz))
                .monospacedDigit()
                .lineLimit(1)
        }
        .width(min: 45, ideal: 60)

        TableColumn("Mode", value: \.sortMode) { spot in
            Text(spot.spot.mode)
                .font(.caption)
                .lineLimit(1)
        }
        .width(min: showSpotMode ? 25 : 0, ideal: showSpotMode ? 35 : 0)
    }

    /// Reference through DXCC: enrichment columns.
    @TableColumnBuilder<EnrichedSpot, KeyPathComparator<EnrichedSpot>>
    private var enrichmentColumns: some TableColumnContent<EnrichedSpot, KeyPathComparator<EnrichedSpot>> {
        TableColumn("Reference") { (spot: EnrichedSpot) in
            Text(spot.spot.referenceDisplay ?? "—")
                .foregroundStyle(
                    spot.spot.referenceDisplay != nil ? Color.accentColor : Color.secondary
                )
                .lineLimit(1)
        }
        .width(min: showReference ? 45 : 0, ideal: showReference ? 65 : 0)

        TableColumn("Name") { spot in
            let displayName = spot.operatorName ?? spot.spot.locationDisplay
            Text(displayName ?? "—")
                .foregroundStyle(displayName != nil ? Color.primary : Color.secondary)
                .lineLimit(1)
        }
        .width(min: showSpotName ? 45 : 0, ideal: showSpotName ? 80 : 0)

        TableColumn("Dist / Brg", value: \.sortDistance) { spot in
            Text(spot.formattedDistanceAndBearing() ?? "—")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .width(min: showDistBrg ? 40 : 0, ideal: showDistBrg ? 60 : 0)

        TableColumn("DXCC") { spot in
            Text(spot.dxccEntity ?? "—")
                .font(.caption)
                .foregroundStyle(
                    spot.dxccEntity != nil ? .primary : .secondary
                )
                .lineLimit(1)
        }
        .width(min: showDXCC ? 35 : 0, ideal: showDXCC ? 60 : 0)
    }
}

// MARK: - SpotListView + Filtering & Actions

extension SpotListView {
    func loadActiveParkReference() async {
        let descriptor = FetchDescriptor<LoggingSession>(
            predicate: #Predicate<LoggingSession> { session in
                session.statusRawValue == "active" && session.activationTypeRawValue != "casual"
            },
            sortBy: [SortDescriptor(\LoggingSession.startedAt, order: .reverse)]
        )
        activeParkReference = (try? modelContext.fetch(descriptor).first)?.parkReference
    }

    var p2pBadge: some View {
        Text("P2P")
            .font(.caption2.weight(.bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.green)
            .clipShape(Capsule())
    }

    /// Whether `spot` is the operator's own (matches `myCallsign`, ignoring
    /// case and any `/P`-style suffix). Same rule the activation map uses.
    func isSelfSpot(_ spot: EnrichedSpot) -> Bool {
        SpotListOrdering.isSelfSpot(spot, userCallsign: myCallsign)
    }

    /// Tinted "You" badge — accent-capsule style from the design language.
    var youBadge: some View {
        Text("You")
            .font(.caption2.weight(.bold))
            .foregroundStyle(Color.accentColor)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.accentColor.opacity(0.2))
            .clipShape(Capsule())
    }

    /// Leading accent bar for the operator's own spot; empty for everyone else
    /// so the gutter column keeps a fixed width.
    @ViewBuilder
    func selfSpotMarker(_ spot: EnrichedSpot) -> some View {
        if isSelfSpot(spot) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(Color.accentColor)
                .frame(width: 3)
                .frame(maxHeight: .infinity)
                .accessibilityHidden(true)
        } else {
            Color.clear.frame(width: 3)
        }
    }

    func refilter() {
        var result: [EnrichedSpot] = if filterMode != .widgets, let allowed = queryRunner.allowedSpotIDs {
            // SQL mode — the saved query is the only filter. Skip
            // every widget control (source / band / mode / region /
            // text / vim) so what the user sees matches what their
            // SELECT returned, no surprises.
            spotAggregator.spots.filter { allowed.contains($0.spot.id) }
        } else {
            applyWidgetFilters(spotAggregator.spots)
        }

        // Own spots float to the top under the default (time) sort so the
        // operator can confirm "I'm spotted" at a glance. Any explicit column
        // sort wins over pinning — the highlight alone carries it there.
        cachedFilteredSpots = SpotListOrdering.pinningSelfSpots(
            result.sorted(using: sortOrder),
            userCallsign: myCallsign,
            sortOrder: sortOrder
        )

        // Update park cache for QSO logging (callsign → parkRef)
        for spot in spotAggregator.spots {
            if let parkRef = spot.spot.parkRef {
                selectionState.spotParkCache[spot.spot.callsign.uppercased()] = parkRef
            }
        }
    }

    /// Applies the widget-mode filter stack: source / band / mode /
    /// continent / region / text search / vim search. Pulled out of
    /// `refilter` so the SQL path can short-circuit cleanly.
    private func applyWidgetFilters(_ spots: [EnrichedSpot]) -> [EnrichedSpot] {
        var result = applySourceBandModeFilters(spots)

        if !selectedContinents.isEmpty {
            result = result.filter { selectedContinents.contains($0.region.continent) }
        }
        if !selectedRegions.isEmpty {
            result = result.filter { selectedRegions.contains($0.region.group) }
        }

        if !filterText.isEmpty {
            let query = filterText.lowercased()
            result = result.filter {
                $0.spot.callsign.lowercased().contains(query) ||
                    ($0.spot.referenceDisplay?.lowercased().contains(query) ?? false) ||
                    ($0.spot.locationDisplay?.lowercased().contains(query) ?? false) ||
                    ($0.spot.spotter?.lowercased().contains(query) ?? false) ||
                    ($0.spot.comments?.lowercased().contains(query) ?? false)
            }
        }

        if let vimFilter = selectionState.vimFilterResult {
            result = result.filter { vimFilter.matches($0) }
        }
        return result
    }

    private func applySourceBandModeFilters(_ spots: [EnrichedSpot]) -> [EnrichedSpot] {
        var result = spots
        if compact {
            if !selectedSources.isEmpty {
                result = result.filter { spot in
                    selectedSources.contains { $0.rawValue == spot.spot.source.rawValue }
                }
            }
            if !selectedBands.isEmpty {
                result = result.filter { selectedBands.contains($0.spot.band) }
            }
            if !selectedModes.isEmpty {
                result = result.filter { spot in
                    selectedModes.contains { $0.matches(mode: spot.spot.mode) }
                }
            }
        } else {
            if selectedSource != .all {
                result = result.filter { $0.spot.source.rawValue == selectedSource.rawValue }
            }
            if selectedBand != "All" {
                result = result.filter { $0.spot.band == selectedBand }
            }
            if selectedMode != .all {
                result = result.filter { selectedMode.matches(mode: $0.spot.mode) }
            }
        }
        return result
    }

    func ageColor(_ date: Date) -> Color {
        let minutes = Date().timeIntervalSince(date) / 60
        if minutes < 5 {
            return Color(nsColor: .systemGreen)
        }
        if minutes < 15 {
            return .primary
        }
        return .secondary
    }

    @ViewBuilder
    func neededBadge(_ status: NeededStatus) -> some View {
        if status != .unknown {
            Text(status.label)
                .font(.system(size: 8, weight: .bold))
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(SpotColorScheme.neededColor(status).opacity(0.2))
                .foregroundStyle(SpotColorScheme.neededColor(status))
                .clipShape(RoundedRectangle(cornerRadius: 3))
        } else {
            Text("—")
                .foregroundStyle(.quaternary)
        }
    }

    /// Tune just the given slot to a spot's frequency/mode without touching
    /// the entry/log focus. Backs the per-slot context-menu items.
    /// Where "Tune & Log" will land right now, for the context-menu footer.
    var spotTuneDestination: SpotTuneDestination {
        SpotTuneDestination.resolve(
            isRadioConnected: radioManager.isConnected,
            radioName: radioManager.connectedRadioName,
            sdrWaterfallEnabled: radioManager.iqPanadapter.settings.enabled
        )
    }

    /// Open the callsign's QRZ page in the default browser. Same pattern as
    /// the contest band scope's context menu.
    func lookupOnQRZ(_ callsign: String) {
        let encoded = callsign.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? callsign
        if let url = URL(string: "https://www.qrz.com/db/\(encoded)") {
            NSWorkspace.shared.open(url)
        }
    }

    func tuneSpot(_ spot: EnrichedSpot, slot: RadioSlot) {
        Task {
            await radioManager.tuneToSpot(
                frequencyMHz: spot.spot.frequencyMHz,
                mode: spot.spot.mode,
                autoXITEnabled: autoXITEnabled,
                autoXITOffsetHz: autoXITOffsetHz,
                slot: slot
            )
        }
    }

    func tuneAndLog(_ spot: EnrichedSpot) {
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
}
