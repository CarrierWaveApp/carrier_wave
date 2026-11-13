import CarrierWaveData
import SwiftUI

// MARK: - ActivationMapPane + Toolbar

extension ActivationMapPane {
    var toolbar: some View {
        HStack {
            Label("Activation Map", systemImage: "map")
                .font(.caption.bold())
                .foregroundStyle(.secondary)

            if case .lookupPending = mapState {
                Text("Looking up\u{2026}")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            modePicker
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.bar)
    }

    /// Single-select picker for which spots to draw. Mirrors the band
    /// scope's filter-mode menu so the two views feel consistent.
    var modePicker: some View {
        Menu {
            modeMenuButtons
            savedQuerySection
        } label: {
            modePickerLabel
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    @ViewBuilder
    var modeMenuButtons: some View {
        Button {
            spotMode = .off
        } label: {
            Label("Off", systemImage: "eye.slash")
        }
        Button {
            spotMode = .rbn
        } label: {
            Label("RBN — who heard me", systemImage: "antenna.radiowaves.left.and.right")
        }
        Button {
            spotMode = .allSpots
        } label: {
            Label("All Spots", systemImage: "mappin.and.ellipse")
        }
    }

    @ViewBuilder
    var savedQuerySection: some View {
        if !savedQueries.isEmpty {
            Divider()
            let usable = savedQueries.filter { validQueryIDs.contains($0.id) }
            let unusable = savedQueries.filter { !validQueryIDs.contains($0.id) }
            ForEach(usable) { query in
                Button("Query: \(query.name)") {
                    spotMode = .savedQuery(query.id)
                }
            }
            if !unusable.isEmpty {
                Divider()
                ForEach(unusable) { query in
                    Button {
                        openWindow(id: "query-workbench")
                    } label: {
                        Label(
                            "\(query.name)  —  ⚠ Missing spot_id (tap to fix)",
                            systemImage: "exclamationmark.triangle.fill"
                        )
                    }
                }
            }
            Divider()
            Button("Open Query Workbench…") {
                openWindow(id: "query-workbench")
            }
        }
    }

    var modePickerLabel: some View {
        HStack(spacing: 4) {
            Image(systemName: modeIcon)
                .font(.caption2)
            Text(modeLabel)
                .font(.caption2.bold())
            if shouldShowCount {
                Text("\(cachedRenderedCount)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(cachedRenderedCount == 0 ? .orange : .secondary)
            }
            Image(systemName: "chevron.down")
                .font(.system(size: 8))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(.quaternary.opacity(0.5), in: Capsule())
    }

    /// Always display the count for saved-query mode so the user can
    /// tell "the query is running but returned nothing" apart from
    /// "nothing's selected." For RBN / All Spots, only show when there
    /// are actually markers to draw.
    private var shouldShowCount: Bool {
        switch spotMode {
        case .off: false
        case .savedQuery: true
        case .rbn,
             .allSpots: cachedRenderedCount > 0
        }
    }

    var modeLabel: String {
        switch spotMode {
        case .off: "Off"
        case .rbn: "RBN"
        case .allSpots: "Spots"
        case let .savedQuery(uuid):
            if let query = savedQueries.first(where: { $0.id == uuid }) {
                "Query: \(query.name)"
            } else {
                "Query: (missing)"
            }
        }
    }

    var modeIcon: String {
        switch spotMode {
        case .off: "eye.slash"
        case .rbn: "antenna.radiowaves.left.and.right"
        case .allSpots: "mappin.and.ellipse"
        case .savedQuery: "tablecells"
        }
    }

    func queryErrorBanner(_ message: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
            Text(message)
                .font(.caption2)
                .foregroundStyle(.red)
                .lineLimit(2)
            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.red.opacity(0.08))
    }
}
