// DXCC Tracking View
//
// Displays DXCC award progress based solely on LoTW-confirmed QSOs.
// Shows a summary dashboard and band/mode matrix of confirmed entities.

import CarrierWaveCore
import CarrierWaveData
import SwiftData
import SwiftUI

// MARK: - DXCCTrackingView

struct DXCCTrackingView: View {
    // MARK: Internal

    @Environment(\.modelContext) var modelContext

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                summarySection
                bandMatrixSection
                entityListSection
            }
            .padding()
        }
        .task { await loadData() }
    }

    // MARK: Private

    private static let hfBands = [
        "160m", "80m", "60m", "40m", "30m",
        "20m", "17m", "15m", "12m", "10m", "6m",
    ]

    private static let challengeBands = [
        "160m", "80m", "40m", "30m",
        "20m", "17m", "15m", "12m", "10m", "6m",
    ]

    private static let primaryModes = ["CW", "SSB", "FT8"]

    @State private var confirmedEntities: [DXCCBandSlot] = []
    @State private var isLoading = true

    // MARK: - Summary

    private var uniqueEntities: Int {
        Set(confirmedEntities.map(\.dxcc)).count
    }

    private var challengeScore: Int {
        confirmedEntities
            .filter { Self.challengeBands.contains($0.band) }
            .count
    }

    private var summarySection: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "globe.americas")
                    .font(.system(size: 28))
                    .foregroundStyle(.blue)

                VStack(alignment: .leading, spacing: 2) {
                    Text("DXCC Progress")
                        .font(.title2.bold())
                    Text("Based on LoTW confirmations")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            if !isLoading {
                HStack(spacing: 24) {
                    dxccStatPill(
                        label: "Entities",
                        value: "\(uniqueEntities)",
                        icon: "flag.fill"
                    )
                    dxccStatPill(
                        label: "Band-Slots",
                        value: "\(confirmedEntities.count)",
                        icon: "square.grid.3x3.fill"
                    )
                    dxccStatPill(
                        label: "Challenge",
                        value: "\(challengeScore)",
                        icon: "trophy.fill"
                    )
                }
            }
        }
        .padding()
        .background(.background.secondary)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Band Matrix

    private var bandMatrixSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Confirmed by Band")
                .font(.headline)

            bandMatrixGrid
        }
        .padding()
        .background(.background.secondary)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var bandMatrixGrid: some View {
        let bandCounts = Dictionary(
            grouping: confirmedEntities, by: \.band
        ).mapValues { Set($0.map(\.dxcc)).count }

        return Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
            ForEach(Self.hfBands, id: \.self) { band in
                GridRow {
                    Text(band)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .frame(width: 40, alignment: .trailing)

                    let count = bandCounts[band] ?? 0
                    Text("\(count)")
                        .font(.body.monospacedDigit())
                        .frame(width: 40, alignment: .trailing)

                    bandBar(count: count, maxCount: uniqueEntities)
                }
            }
        }
    }

    // MARK: - Entity List

    private var entityListSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Confirmed Entities (\(uniqueEntities))")
                .font(.headline)

            let grouped = groupedByEntity()
            LazyVStack(spacing: 2) {
                ForEach(
                    grouped.sorted(by: { $0.key < $1.key }),
                    id: \.key
                ) { entity, slots in
                    entityRow(
                        entityName: entity,
                        slots: slots
                    )
                }
            }
        }
        .padding()
        .background(.background.secondary)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func dxccStatPill(
        label: String,
        value: String,
        icon: String
    ) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.caption)
                Text(value)
                    .font(.title3.monospacedDigit().bold())
            }
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func bandBar(count: Int, maxCount: Int) -> some View {
        GeometryReader { geo in
            let fraction = maxCount > 0
                ? Double(count) / Double(maxCount)
                : 0
            RoundedRectangle(cornerRadius: 3)
                .fill(.blue.opacity(0.6))
                .frame(width: geo.size.width * fraction)
        }
        .frame(height: 14)
    }

    private func entityRow(
        entityName: String,
        slots: [DXCCBandSlot]
    ) -> some View {
        HStack {
            Text(entityName)
                .font(.body)
                .lineLimit(1)

            Spacer()

            HStack(spacing: 4) {
                ForEach(Self.hfBands, id: \.self) { band in
                    let hasBand = slots.contains { $0.band == band }
                    Circle()
                        .fill(hasBand ? .green : .gray.opacity(0.2))
                        .frame(width: 8, height: 8)
                }
            }

            Text("\(Set(slots.map(\.band)).count)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 24, alignment: .trailing)
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 4)
    }

    // MARK: - Data Loading

    private func loadData() async {
        isLoading = true

        let context = ModelContext(modelContext.container)
        let predicate = #Predicate<QSO> {
            $0.lotwConfirmed && !$0.isHidden
        }

        var seen = Set<UUID>()
        var slots: [DXCCBandSlot] = []
        var offset = 0

        do {
            while true {
                let descriptor = BoundedDescriptor<QSO>(
                    predicate: predicate,
                    limit: BoundedDescriptor<QSO>.maxLimit,
                    offset: offset
                )
                let batch = try context.boundedFetch(descriptor)
                if batch.isEmpty {
                    break
                }

                for qso in batch {
                    guard seen.insert(qso.id).inserted else {
                        continue
                    }
                    guard let dxcc = qso.dxcc else {
                        continue
                    }

                    slots.append(DXCCBandSlot(
                        dxcc: dxcc,
                        band: qso.band,
                        mode: ModeEquivalence.canonicalName(qso.mode),
                        country: qso.country ?? "Unknown (#\(dxcc))"
                    ))
                }
                offset += batch.count
            }

            // Deduplicate band-slots
            var uniqueSlots = Set<String>()
            confirmedEntities = slots.filter { slot in
                let key = "\(slot.dxcc)|\(slot.band)"
                return uniqueSlots.insert(key).inserted
            }
        } catch {
            confirmedEntities = []
        }

        isLoading = false
    }

    private func groupedByEntity() -> [String: [DXCCBandSlot]] {
        Dictionary(grouping: confirmedEntities, by: \.country)
    }
}

// MARK: - DXCCBandSlot

struct DXCCBandSlot {
    let dxcc: Int
    let band: String
    let mode: String
    let country: String
}
