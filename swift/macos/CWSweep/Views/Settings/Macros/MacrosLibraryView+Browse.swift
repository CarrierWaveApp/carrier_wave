import CarrierWaveData
import SwiftData
import SwiftUI

// MARK: - MacrosLibraryBrowseTab

/// Server-paged registry browse list. Hits `MacrosRegistryHolder.client`
/// (lazy-configured at app launch) and renders each entry with an
/// installed badge when a local `RadioMacro` already has the matching slug.
struct MacrosLibraryBrowseTab: View {
    // MARK: Internal

    let model: MacroLibraryModel

    var body: some View {
        @Bindable var boundModel = model
        Group {
            if let firstLoadError, entries.isEmpty {
                errorState(firstLoadError)
            } else if loading, entries.isEmpty {
                ProgressView("Loading registry…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if entries.isEmpty {
                emptyState
            } else {
                list
            }
        }
        .task(id: model.searchText) {
            try? await Task.sleep(nanoseconds: 250_000_000)
            if Task.isCancelled {
                return
            }
            await refresh()
        }
        .refreshable {
            await refresh()
        }
        .searchable(text: $boundModel.searchText)
    }

    // MARK: Private

    @Environment(\.modelContext) private var ctx

    @Query(filter: #Predicate<RadioMacro> { !$0.tombstoned })
    private var installedMacros: [RadioMacro]

    @State private var entries: [RegistryListEntry] = []
    @State private var loading = false
    @State private var firstLoadError: String?

    private var installedSlugs: Set<String> {
        Set(installedMacros.compactMap { $0.registry?.slug })
    }

    private var list: some View {
        List {
            ForEach(entries) { entry in
                NavigationLink {
                    MacroBrowseDetailView(
                        entry: entry,
                        isInstalled: installedSlugs.contains(entry.slug)
                    )
                } label: {
                    MacroBrowseRowLabel(entry: entry, isInstalled: installedSlugs.contains(entry.slug))
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "books.vertical")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.secondary)
            Text("No Macros Found")
                .font(.headline)
            Text(
                "Nothing matched your search. Try a different keyword, "
                    + "or browse the full registry by clearing the search."
            )
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 32)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 48)
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.orange)
            Text("Couldn't reach the registry")
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button("Try Again") {
                Task { await refresh() }
            }
            .buttonStyle(.borderedProminent)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 48)
    }

    private func refresh() async {
        guard let client = MacrosRegistryHolder.shared.client else {
            firstLoadError = "Registry not yet configured"
            return
        }
        loading = true
        defer { loading = false }
        let search = model.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            let response = try await client.list(
                maxFormat: RadioMacroDocument.currentFormat,
                search: search.isEmpty ? nil : search
            )
            entries = response.entries
            firstLoadError = nil
        } catch {
            if entries.isEmpty {
                firstLoadError = friendlyError(error)
            }
        }
    }

    private func friendlyError(_ error: Error) -> String {
        switch error {
        case let MacrosRegistryClientError.server(status, _):
            "Server returned status \(status)"
        case MacrosRegistryClientError.notAuthenticated:
            "Sign in to community features to browse the registry"
        case let MacrosRegistryClientError.transport(message):
            message
        default:
            String(describing: error)
        }
    }
}

// MARK: - MacroBrowseRowLabel

struct MacroBrowseRowLabel: View {
    let entry: RegistryListEntry
    let isInstalled: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: entry.icon ?? "wand.and.stars")
                .font(.system(size: 18))
                .foregroundStyle(.tint)
                .frame(width: 28, alignment: .center)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(entry.name)
                        .font(.body)
                    if isInstalled {
                        Text("Installed")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.tint)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(Color.accentColor.opacity(0.15), in: Capsule())
                    }
                }
                if let description = entry.description, !description.isEmpty {
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if let callsign = entry.authorCallsign {
                    Text("by \(callsign) · v\(entry.version)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
