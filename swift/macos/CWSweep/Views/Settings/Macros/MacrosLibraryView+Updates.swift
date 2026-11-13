import CarrierWaveData
import SwiftData
import SwiftUI

// MARK: - MacrosLibraryUpdatesTab

/// Shows installed macros whose `registry.registryVersion` is older than
/// the latest server version, per the most recent
/// `MacrosRegistryHolder.snapshot`. Tapping a row opens the diff review
/// sheet.
struct MacrosLibraryUpdatesTab: View {
    // MARK: Internal

    let model: MacroLibraryModel

    var body: some View {
        Group {
            if rowsAvailable.isEmpty {
                emptyState
            } else {
                list
            }
        }
        .task {
            await holder.refreshNow()
        }
        .refreshable {
            await holder.refreshNow()
        }
    }

    // MARK: Private

    @Query(filter: #Predicate<RadioMacro> { !$0.tombstoned })
    private var installedMacros: [RadioMacro]

    @State private var reviewing: PendingUpdate?

    private var holder: MacrosRegistryHolder {
        .shared
    }

    private var rowsAvailable: [PendingUpdate] {
        let pending = holder.snapshot.pendingUpdates
        guard !pending.isEmpty else {
            return []
        }
        return installedMacros.compactMap { macro -> PendingUpdate? in
            guard let registry = macro.registry,
                  let info = pending[registry.slug],
                  info.version > registry.registryVersion
            else {
                return nil
            }
            return PendingUpdate(macro: macro, serverVersion: info.version, serverFormat: info.format)
        }
    }

    private var list: some View {
        List {
            ForEach(rowsAvailable) { row in
                Button {
                    reviewing = row
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: row.macro.icon ?? "wand.and.stars")
                            .foregroundStyle(.tint)
                            .frame(width: 28, alignment: .center)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(row.macro.name)
                                .font(.body)
                            Text("v\(row.macro.registry?.registryVersion ?? 0) → v\(row.serverVersion)")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .sheet(item: $reviewing) { row in
            NavigationStack {
                MacroUpdateReviewView(macro: row.macro)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.seal")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.secondary)
            Text("Everything's Up To Date")
                .font(.headline)
            Text("Updates show up here when the registry has a newer version of a macro you've installed.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            if let polledAt = holder.snapshot.polledAt {
                Text("Last checked \(polledAt, style: .relative) ago")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 48)
    }
}

// MARK: - PendingUpdate

private struct PendingUpdate: Identifiable {
    let macro: RadioMacro
    let serverVersion: Int
    let serverFormat: Int

    var id: UUID {
        macro.id
    }
}
