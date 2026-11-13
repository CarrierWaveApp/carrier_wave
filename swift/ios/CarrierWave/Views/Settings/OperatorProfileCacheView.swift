import CarrierWaveData
import SwiftUI

// MARK: - OperatorProfileCacheView

/// Status surface for the offline operator-profile cache backed by
/// `OperatorProfileService`. Shows row count + backfill watermark and
/// exposes a manual rebuild for support cases where the cache drifts.
struct OperatorProfileCacheView: View {
    // MARK: Internal

    var body: some View {
        List {
            statusSection
            rebuildSection
            footerSection
        }
        .navigationTitle("Offline Operator Cache")
        .task { await refresh() }
        .refreshable { await refresh() }
    }

    // MARK: Private

    @State private var status: OperatorProfileService.Status?

    private var watermarkText: String {
        guard let watermark = status?.backfillWatermark else {
            return "Never"
        }
        return watermark.formatted(date: .abbreviated, time: .shortened)
    }

    private var statusSection: some View {
        Section {
            statusRow(
                "Cached Profiles",
                value: status.map { "\($0.cachedCount.formatted())" } ?? "—"
            )
            statusRow(
                "Backfill Up To",
                value: watermarkText
            )
            statusRow(
                "Service Started",
                value: status?.isStarted == true ? "Yes" : "No"
            )
        } header: {
            Text("Status")
        }
    }

    private var rebuildSection: some View {
        Section {
            Button {
                Task { await rebuild() }
            } label: {
                HStack {
                    if status?.isRebuilding == true {
                        ProgressView()
                            .controlSize(.small)
                            .padding(.trailing, 4)
                        Text("Rebuilding…")
                    } else {
                        Text("Rebuild Cache")
                    }
                }
            }
            .disabled(status?.isRebuilding == true || status == nil)
        } footer: {
            Text(
                "Resets the watermark and replays QSO history into the "
                    + "offline cache. QRZ-enriched rows are preserved."
            )
        }
    }

    private var footerSection: some View {
        Section {
            EmptyView()
        } footer: {
            Text(
                "The offline cache lets callsign lookups render instantly "
                    + "from disk while QRZ/HamDB enrichment runs in the "
                    + "background. New QSOs are folded in on each launch."
            )
        }
    }

    private func statusRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }

    private func refresh() async {
        status = await OperatorProfileService.shared.status()
    }

    private func rebuild() async {
        await OperatorProfileService.shared.rebuild()
        await refresh()
    }
}

#Preview {
    NavigationStack {
        OperatorProfileCacheView()
    }
}
