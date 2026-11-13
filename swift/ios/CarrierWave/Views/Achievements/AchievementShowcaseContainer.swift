import CarrierWaveData
import SwiftUI

// MARK: - AchievementShowcaseContainer

/// Loads the achievement catalog and the current user's awards, then renders
/// `AchievementShowcaseView`. This is the navigation destination wired into
/// AboutMeView; the underlying showcase view stays pure for previews/tests.
struct AchievementShowcaseContainer: View {
    // MARK: Internal

    let callsign: String

    var body: some View {
        ZStack(alignment: .top) {
            Group {
                switch loadState {
                case .idle,
                     .loading:
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .loaded:
                    AchievementShowcaseView(catalog: catalog, earnedIDs: earnedIDs)
                case let .failed(message):
                    errorView(message: message)
                }
            }
            if !newlyEarnedNames.isEmpty {
                unlockToast
                    .padding(.horizontal)
                    .padding(.top, 8)
            }
        }
        .navigationTitle("Badges")
        .task(id: callsign) {
            await load()
        }
        .refreshable {
            await load()
        }
    }

    // MARK: Private

    // MARK: - LoadState

    private enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    @State private var catalog: [Achievement] = []
    @State private var earnedIDs: Set<String> = []
    @State private var loadState: LoadState = .idle
    @State private var newlyEarnedNames: [String] = []

    private var seenIDsKey: String {
        "AchievementShowcase.seenIDs.\(callsign.uppercased())"
    }

    private var unlockToast: some View {
        HStack(spacing: 10) {
            Image(systemName: "rosette")
                .foregroundStyle(.yellow)
            VStack(alignment: .leading, spacing: 2) {
                Text("Badge unlocked")
                    .font(.subheadline.weight(.semibold))
                Text(newlyEarnedNames.joined(separator: ", "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer()
            Button {
                withAnimation { newlyEarnedNames = [] }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(radius: 4)
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    private func errorView(message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("Couldn't load badges")
                .font(.headline)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Retry") {
                Task { await load() }
            }
            .buttonStyle(.bordered)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @MainActor
    private func load() async {
        loadState = .loading
        let client = ActivitiesClient()
        let baseURL = ActivitiesClient.resolvedBaseURL
        do {
            async let catalogFetch = client.fetchAchievementCatalog(sourceURL: baseURL)
            async let awardsFetch = client.fetchUserAchievements(
                callsign: callsign,
                sourceURL: baseURL
            )
            let (loadedCatalog, loadedAwards) = try await (catalogFetch, awardsFetch)
            catalog = loadedCatalog
            earnedIDs = Set(loadedAwards.map(\.achievementId))
            detectNewlyEarned(in: loadedCatalog)
            loadState = .loaded
        } catch {
            loadState = .failed(error.localizedDescription)
        }
    }

    private func detectNewlyEarned(in catalog: [Achievement]) {
        let defaults = UserDefaults.standard
        let previouslySeen = Set(defaults.stringArray(forKey: seenIDsKey) ?? [])
        let newIDs = earnedIDs.subtracting(previouslySeen)
        if !newIDs.isEmpty, !previouslySeen.isEmpty {
            // Skip the toast on first-ever load — we have no notion of "new" yet.
            let lookup = Dictionary(uniqueKeysWithValues: catalog.map { ($0.id, $0.name) })
            withAnimation {
                newlyEarnedNames = newIDs.compactMap { lookup[$0] }.sorted()
            }
        }
        defaults.set(Array(earnedIDs), forKey: seenIDsKey)
    }
}
