import CarrierWaveCore
import SwiftUI

// MARK: - BandPlanSheet

/// Interactive band plan reference showing segments, license requirements, and activities
struct BandPlanSheet: View {
    // MARK: Internal

    let selectedMode: String

    @Binding var frequency: String

    var body: some View {
        NavigationStack {
            List {
                bandPicker
                segmentsSection
                activitiesSection
            }
            .navigationTitle("Band Plan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .landscapeAdaptiveDetents(portrait: [.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: Private

    @AppStorage("userLicenseClass") private var licenseClassRaw: String = LicenseClass.extra
        .rawValue
    @Environment(\.dismiss) private var dismiss

    @State private var selectedBand: String = "20m"

    // MARK: - Data

    private let bandList = [
        "160m", "80m", "60m", "40m", "30m", "20m", "17m", "15m", "12m", "10m",
        "6m", "2m", "70cm",
    ]

    private var userLicenseClass: LicenseClass {
        LicenseClass(rawValue: licenseClassRaw) ?? .extra
    }

    private var bandSegments: [BandSegment] {
        // Deduplicate overlapping segments — show the most restrictive first
        let segments = BandPlan.segments.filter { $0.band == selectedBand }
        // Group by frequency range to collapse duplicates
        var seen: Set<String> = []
        return segments.filter { seg in
            let key = "\(seg.startMHz)-\(seg.endMHz)-\(seg.modes.sorted())"
            if seen.contains(key) {
                return false
            }
            seen.insert(key)
            return true
        }
    }

    private var bandActivities: [FrequencyActivity] {
        BandPlan.activities.filter { $0.band == selectedBand }
    }

    // MARK: - Band Picker

    private var bandPicker: some View {
        Section {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(bandList, id: \.self) { band in
                        Button {
                            selectedBand = band
                        } label: {
                            Text(band)
                                .font(.subheadline.weight(.medium))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(
                                    selectedBand == band
                                        ? Color.accentColor.opacity(0.2)
                                        : Color(.tertiarySystemGroupedBackground)
                                )
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
        }
    }

    // MARK: - Segments

    private var segmentsSection: some View {
        Section {
            ForEach(bandSegments, id: \.startMHz) { segment in
                segmentRow(segment)
            }
        } header: {
            Text("Band Segments")
        } footer: {
            Text("Tap a segment to use its starting frequency")
        }
    }

    // MARK: - Activities

    private var activitiesSection: some View {
        Section("Activity Frequencies") {
            if bandActivities.isEmpty {
                Text("No notable activities on \(selectedBand)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(
                    Array(bandActivities.enumerated()),
                    id: \.offset
                ) { _, activity in
                    activityRow(activity)
                }
            }
        }
    }

    private func segmentRow(_ segment: BandSegment) -> some View {
        let hasPrivileges = userHasPrivileges(for: segment)
        let freqRange = formatRange(segment)

        return Button {
            let freq = suggestedFrequencyInSegment(segment)
            frequency = FrequencyFormatter.format(freq)
            dismiss()
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(freqRange)
                        .font(.subheadline.monospaced())
                    HStack(spacing: 4) {
                        modesBadge(segment.modes)
                        Text(segment.minimumLicense.abbreviation)
                            .font(.caption2.weight(.medium))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(licenseBadgeColor(segment.minimumLicense))
                            .clipShape(Capsule())
                    }
                }

                Spacer()

                if !hasPrivileges {
                    Image(systemName: "lock.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .buttonStyle(.plain)
        .opacity(hasPrivileges ? 1.0 : 0.5)
        .disabled(!hasPrivileges)
    }

    private func activityRow(_ activity: FrequencyActivity) -> some View {
        Button {
            frequency = FrequencyFormatter.format(activity.centerMHz)
            dismiss()
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(activity.description)
                        .font(.subheadline)
                    Text(FrequencyFormatter.formatWithUnit(activity.centerMHz))
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(activity.type.rawValue)
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(activityColor(activity.type).opacity(0.15))
                    .foregroundStyle(activityColor(activity.type))
                    .clipShape(Capsule())
            }
        }
        .buttonStyle(.plain)
    }

    private func modesBadge(_ modes: Set<String>) -> some View {
        let label = modes.contains("ALL") ? "All Modes" : modes.sorted().joined(separator: "/")
        let color = modesColor(modes)
        return Text(label)
            .font(.caption2)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }

    // MARK: - Helpers

    private func userHasPrivileges(for segment: BandSegment) -> Bool {
        let order: [LicenseClass] = [.technician, .general, .extra]
        let userIdx = order.firstIndex(of: userLicenseClass) ?? 0
        let reqIdx = order.firstIndex(of: segment.minimumLicense) ?? 0
        return userIdx >= reqIdx
    }

    private func suggestedFrequencyInSegment(_ segment: BandSegment) -> Double {
        // If there's a known activity frequency in this segment, use it
        if let activity = bandActivities.first(where: {
            segment.contains(frequencyMHz: $0.centerMHz)
        }) {
            return activity.centerMHz
        }
        // Otherwise use the segment start + small offset
        return segment.startMHz + 0.005
    }

    private func formatRange(_ segment: BandSegment) -> String {
        if segment.startMHz == segment.endMHz {
            return FrequencyFormatter.formatWithUnit(segment.startMHz)
        }
        return
            "\(FrequencyFormatter.format(segment.startMHz)) – \(FrequencyFormatter.formatWithUnit(segment.endMHz))"
    }

    private func modesColor(_ modes: Set<String>) -> Color {
        if modes.contains("ALL") {
            return .purple
        }
        if modes.contains("SSB") || modes.contains("PHONE") {
            return .green
        }
        if modes.contains("CW") {
            return .blue
        }
        return .orange
    }

    private func licenseBadgeColor(_ license: LicenseClass) -> Color {
        switch license {
        case .technician: Color.green.opacity(0.15)
        case .general: Color.blue.opacity(0.15)
        case .extra: Color.purple.opacity(0.15)
        }
    }

    private func activityColor(_ type: FrequencyActivity.ActivityType) -> Color {
        switch type {
        case .qrpCW,
             .qrpSSB: .orange
        case .digitalFT,
             .digitalPSK,
             .rtty: .cyan
        case .ssbCalling,
             .amCalling,
             .fmSimplex: .green
        case .sstv: .purple
        case .cwtContest: .red
        case .net: .blue
        }
    }
}

// MARK: - Preview

#Preview {
    BandPlanSheet(
        selectedMode: "CW",
        frequency: .constant("")
    )
}
