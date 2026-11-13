import CarrierWaveCore
import SwiftUI

// MARK: - RemoteSweepConnectedView

//
// Five sub-screens (Radio / Scope / Waterfall / Spots / CW) selected via a
// horizontal chip strip mounted under the nav title. We deliberately avoid
// a nested `TabView` here because the iOS system tab bar (Dashboard /
// Sessions / Logs / Remote / More) lives at the screen's bottom edge — a
// second tab bar would stack on top of it. The chip strip frees the bottom
// for the system tabs and reads like a radio's function-key row, which fits
// the control-surface aesthetic of the rest of the Remote pane.

struct RemoteSweepConnectedView: View {
    // MARK: Internal

    enum Section: String, CaseIterable, Identifiable {
        case radio
        case scope
        case waterfall
        case spots
        case cw

        // MARK: Internal

        var id: String {
            rawValue
        }

        var label: String {
            switch self {
            case .radio: "Radio"
            case .scope: "Scope"
            case .waterfall: "Waterfall"
            case .spots: "Spots"
            case .cw: "CW"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            sectionPicker
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 14)
            Divider()
                .overlay(Color.white.opacity(0.06))
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color.black.ignoresSafeArea())
    }

    // MARK: Private

    @Environment(RemoteSweepCoordinator.self) private var coordinator
    @AppStorage("remoteSweepSection") private var selectedRaw: String = Section.radio.rawValue

    private var selected: Section {
        Section(rawValue: selectedRaw) ?? .radio
    }

    @ViewBuilder
    private var content: some View {
        switch selected {
        case .radio: RemoteSweepRadioPane()
        case .scope: RemoteSweepScopeView()
        case .waterfall: RemoteSweepWaterfallView()
        case .spots: RemoteSweepSpotsPane()
        case .cw: RemoteSweepCWPane()
        }
    }

    private var sectionPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Section.allCases) { section in
                    sectionChip(section)
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func sectionChip(_ section: Section) -> some View {
        let isSelected = selected == section
        return Button {
            selectedRaw = section.rawValue
        } label: {
            Text(section.label)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isSelected ? Color.blue : .secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? Color.blue.opacity(0.2) : Color.clear)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(section.label)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

// MARK: - RemoteSweepSpotsPane

struct RemoteSweepSpotsPane: View {
    // MARK: Internal

    var body: some View {
        List {
            if coordinator.spots.isEmpty {
                Section {
                    if coordinator.spotsLoading {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text("Loading spots from Sweep…")
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Text("No spots from Sweep yet.")
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                ForEach(coordinator.spots) { spot in
                    Button {
                        Task { await coordinator.tune(freqHz: spot.freqHz, mode: spot.mode) }
                    } label: {
                        spotRow(spot)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: Private

    @Environment(RemoteSweepCoordinator.self) private var coordinator

    private func spotRow(_ spot: RemoteSpot) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(spot.callsign)
                        .font(.headline)
                    if spot.needed {
                        Text("NEEDED")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.orange.opacity(0.2))
                            .foregroundStyle(.orange)
                            .clipShape(Capsule())
                    }
                }
                HStack(spacing: 6) {
                    Text(formatFrequency(spot.freqHz))
                        .font(.system(.subheadline, design: .monospaced))
                    if let mode = spot.mode {
                        Text(mode)
                    }
                    if let band = spot.band {
                        Text(band)
                    }
                }
                .foregroundStyle(.secondary)
                .font(.subheadline)
                if let comment = spot.comment, !comment.isEmpty {
                    Text(comment)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(spot.source.uppercased())
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                if let snr = spot.snr {
                    Text("\(snr) dB").font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func formatFrequency(_ hz: UInt64) -> String {
        let mhz = Double(hz) / 1_000_000
        return String(format: "%.5f", mhz)
    }
}
