// Session Detail View - Hero Section
//
// Unified Tier 1 hero card for both POTA activations and
// regular sessions. Consolidates summary, stats, band/mode
// pills, key details, shift windows, and upload actions.

import CarrierWaveCore
import CarrierWaveData
import SwiftUI

// MARK: - Unified Hero Section

extension SessionDetailView {
    /// Tier 1: Consolidated hero card for both POTA and regular sessions.
    var heroSection: some View {
        Section {
            heroHeader
                .listRowSeparator(.hidden)

            heroStatStrip
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))

            heroBandModePills
                .listRowSeparator(.hidden)

            heroDetailsLine
                .listRowSeparator(.hidden)

            if activation != nil {
                heroShiftAndConditions
                    .listRowSeparator(.hidden)

                if let activation {
                    QSOTimelineView(qsos: activation.qsos)
                        .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
                }
            }

            if shouldShowUpload {
                inlineUploadRow
                    .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
            } else if activation == nil, shouldShowQRZUpload {
                inlineUploadRow
                    .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
            }
        }
    }

    // MARK: - Hero Header

    @ViewBuilder
    private var heroHeader: some View {
        if let activation {
            VStack(alignment: .leading, spacing: 4) {
                if let parkName {
                    Text(parkName)
                        .font(.headline)
                }
                HStack {
                    Text(activation.displayDate)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(activation.callsign)
                        .font(.subheadline.monospaced().weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }
        } else if let session {
            VStack(alignment: .leading, spacing: 4) {
                Text(session.displayTitle)
                    .font(.title3.weight(.semibold))
                Text(session.startedAt, style: .date)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Hero Stat Strip

    private var heroStatStrip: some View {
        SessionStatStrip(cells: heroStatCells)
    }

    private var heroStatCells: [StatStripCell] {
        if let activation {
            return statCells(
                qsoCount: activation.qsoCount,
                duration: activation.formattedDuration,
                rate: heroRate
            )
        }
        if let session {
            return statCells(
                qsoCount: qsos.count,
                duration: session.formattedDuration,
                rate: qsos.isEmpty ? nil : formattedQSOsPerHour
            )
        }
        return []
    }

    private func statCells(
        qsoCount: Int, duration: String, rate: String?
    ) -> [StatStripCell] {
        var cells: [StatStripCell] = [
            StatStripCell(
                value: "\(qsoCount)", label: "QSOs",
                percentile: percentiles?.qsoCountPercentile
            ),
            StatStripCell(
                value: duration, label: "Duration",
                percentile: percentiles?.durationPercentile
            ),
        ]
        if let rate {
            cells.append(StatStripCell(
                value: rate, label: "QSOs/hr",
                percentile: percentiles?.ratePercentile
            ))
        }
        return cells
    }

    private var heroRate: String? {
        guard let activation, activation.duration > 0 else {
            return nil
        }
        let hours = activation.duration / 3_600
        guard hours > 0 else {
            return nil
        }
        let rate = Double(activation.qsoCount) / hours
        return String(format: "%.1f", rate)
    }
}

// MARK: - Band/Mode Pills

extension SessionDetailView {
    @ViewBuilder
    private var heroBandModePills: some View {
        let bands = heroBandCounts
        let modes = heroModeCounts
        if !bands.isEmpty || !modes.isEmpty {
            FlowLayout(spacing: 6) {
                ForEach(bands, id: \.name) { entry in
                    CountedPill(label: entry.name, count: entry.count, color: .blue)
                }
                ForEach(modes, id: \.name) { entry in
                    CountedPill(label: entry.name, count: entry.count, color: .green)
                }
            }
        }
    }

    private var heroBandCounts: [(name: String, count: Int)] {
        let source = displayQSOs
        var counts: [String: Int] = [:]
        for qso in source {
            counts[qso.band, default: 0] += 1
        }
        return counts.sorted { $0.key < $1.key }
            .map { (name: $0.key, count: $0.value) }
    }

    private var heroModeCounts: [(name: String, count: Int)] {
        let source = displayQSOs
        var counts: [String: Int] = [:]
        for qso in source {
            counts[qso.mode, default: 0] += 1
        }
        return counts.sorted { $0.key < $1.key }
            .map { (name: $0.key, count: $0.value) }
    }
}

// MARK: - Compact Details Line

extension SessionDetailView {
    @ViewBuilder
    private var heroDetailsLine: some View {
        let parts = heroDetailParts
        if !parts.isEmpty {
            FlowLayout(spacing: 8) {
                ForEach(
                    Array(parts.enumerated()), id: \.offset
                ) { _, part in
                    Label(part.label, systemImage: part.icon)
                        .labelStyle(.titleAndIcon)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
        }
    }

    private var heroDetailParts: [MetadataItem] {
        var items: [MetadataItem] = []
        if let activation {
            appendEquipmentDetails(to: &items)
            let ref = session?.activationReference ?? activation.parkReference
            items.insert(MetadataItem(icon: "leaf.fill", label: ref), at: 0)
        } else if let session {
            appendSessionDetails(session, to: &items)
        }
        return items
    }

    private func appendSessionDetails(
        _ session: LoggingSession, to items: inout [MetadataItem]
    ) {
        if let ref = session.activationReference {
            items.append(MetadataItem(icon: "leaf.fill", label: ref))
        }
        if session.activationType == .tota {
            appendTOTAHeroDetails(session, to: &items)
        }
        if let grid = sessionGridLabel(session) {
            items.append(MetadataItem(icon: "square.grid.3x3", label: grid))
        }
        if let power = session.power {
            items.append(MetadataItem(icon: "bolt.fill", label: "\(power)W"))
        }
        appendEquipmentItems(session, to: &items)
    }

    /// One-line tile name + score summary, mirroring POTA's parkReference line.
    /// Detailed ledger lives in the dedicated TOTA section below the hero.
    private func appendTOTAHeroDetails(
        _ session: LoggingSession, to items: inout [MetadataItem]
    ) {
        let tiles = session.tilesActivated
        if !tiles.isEmpty {
            items.append(
                MetadataItem(icon: "square.grid.3x3.fill", label: tiles.joined(separator: ", "))
            )
        }
        if let official = session.totaOfficialPoints {
            items.append(
                MetadataItem(
                    icon: "trophy.fill",
                    label: String(format: "%.1f pts", official)
                )
            )
        }
    }

    private func appendEquipmentDetails(to items: inout [MetadataItem]) {
        if let watts = activationMetadata?.watts {
            items.append(MetadataItem(icon: "bolt.fill", label: "\(watts)W"))
        }
        if let session = activationSession {
            appendEquipmentItems(session, to: &items)
        } else {
            // Fall back to QSO-level rig data when no session
            let radio = activation?.qsos.compactMap(\.myRig).first
            if let radio {
                items.append(MetadataItem(icon: "radio", label: radio))
            }
        }
    }

    private func appendEquipmentItems(
        _ session: LoggingSession, to items: inout [MetadataItem]
    ) {
        if let rig = session.myRig {
            items.append(MetadataItem(icon: "radio", label: rig))
        }
        if let antenna = session.myAntenna {
            items.append(MetadataItem(
                icon: "antenna.radiowaves.left.and.right", label: antenna
            ))
        }
        if let key = session.myKey {
            items.append(MetadataItem(icon: "pianokeys", label: key))
        }
        if let mic = session.myMic {
            items.append(MetadataItem(icon: "mic", label: mic))
        }
    }
}

// MARK: - Shift Windows + Conditions (POTA only)

extension SessionDetailView {
    @ViewBuilder
    private var heroShiftAndConditions: some View {
        let shiftCounts = heroShiftCounts
        let hasShifts = !shiftCounts.isEmpty
        let showConditions = activationMetadata?.hasSolarData == true
            || activationMetadata?.hasWeatherData == true
        if hasShifts || showConditions {
            VStack(alignment: .leading, spacing: 8) {
                if hasShifts {
                    HStack(spacing: 12) {
                        ForEach(shiftCounts, id: \.window.shift) { entry in
                            heroShiftPill(entry.window, count: entry.count)
                        }
                        Spacer()
                    }
                }
                if showConditions, let meta = activationMetadata {
                    ConditionsGaugeRow(
                        metadata: meta,
                        showingSheet: $showingConditions
                    )
                }
            }
            .sheet(isPresented: $showingConditions) {
                if let meta = activationMetadata {
                    ActivationConditionsSheet(metadata: meta)
                }
            }
        }
    }

    /// Shift windows filtered to only those with QSOs, paired with counts.
    private var heroShiftCounts: [(window: ShiftWindow, count: Int)] {
        let parkRef = activation?.parkReference ?? session?.parkReference
        guard let parkRef,
              let park = POTAParksCache.shared.parkSync(
                  for: ParkReference.split(parkRef).first ?? parkRef
              ),
              let longitude = park.longitude,
              let activation
        else {
            return []
        }
        let utcDate = activation.qsos.first?.timestamp ?? Date()
        let windows = POTAShift.windows(for: utcDate, longitude: longitude)
        let qsoTimestamps = displayQSOs.map(\.timestamp)
        return windows.compactMap { window in
            let count = qsoTimestamps.filter { window.contains($0) }.count
            guard count > 0 else {
                return nil
            }
            return (window: window, count: count)
        }
    }

    private func heroShiftPill(
        _ window: ShiftWindow, count: Int
    ) -> some View {
        let color: Color = window.shift == .late ? .indigo : .orange
        return HStack(spacing: 4) {
            Image(systemName: window.shift == .late ? "moon.fill" : "sunrise.fill")
                .font(.caption2)
            Text("\(window.shift.displayLabel): \(count)Q")
                .font(.caption2)
            Text(window.formattedRange)
                .font(.caption2)
                .foregroundStyle(color.opacity(0.7))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(0.15))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}
