import CarrierWaveData
import Foundation
import Observation

// MARK: - MacroURLBridge

/// Observable singleton that bridges the URL-handling path (which runs
/// from `.onOpenURL`) to the SwiftUI view tree. The root window
/// observes `pending` and presents `MacroImportSheet` whenever it
/// changes.
@MainActor
@Observable
final class MacroURLBridge {
    // MARK: Lifecycle

    private init() {}

    // MARK: Internal

    static let shared = MacroURLBridge()

    /// Pending import document fetched from the registry or scheme. Set
    /// by `MacroURLHandler` and consumed by `FinderDropTarget`'s sheet.
    var pending: PendingMacroDocument?
}

// MARK: - PendingMacroDocument

/// Container with stable identity so SwiftUI's `.sheet(item:)` can
/// drive presentation off the bridge.
struct PendingMacroDocument: Identifiable {
    let id = UUID()
    let data: Data
    let provenance: MacroImportProvenance
}

// MARK: - MacroURLHandler

/// Parses `cwmacro://import?slug=<slug>` custom-scheme URLs and the
/// `https://carrierwave.app/m/<slug>` Universal Link, fetches the full
/// document from the registry, then publishes a `PendingMacroDocument`
/// for the SwiftUI sheet to pick up. Best-effort: failures (no network,
/// unknown slug) are swallowed because we have no toast surface in CW
/// Sweep yet.
@MainActor
enum MacroURLHandler {
    // MARK: Internal

    /// Returns true when the URL matched a macros route. The caller
    /// (`.onOpenURL`) can use the return value to short-circuit other
    /// routers like `EnrichedLinkRouter`.
    @discardableResult
    static func handle(_ url: URL) -> Bool {
        guard let slug = parseSlug(from: url) else {
            return false
        }
        Task {
            await fetchAndPublish(slug: slug)
        }
        return true
    }

    // MARK: Private

    private static func parseSlug(from url: URL) -> String? {
        if url.scheme == "cwmacro" {
            return URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?
                .first(where: { $0.name == "slug" })?
                .value
        }
        if let host = url.host, host == "carrierwave.app" {
            let components = url.pathComponents.filter { $0 != "/" }
            if components.count >= 2, components[0] == "m" {
                return components[1]
            }
        }
        return nil
    }

    private static func fetchAndPublish(slug: String) async {
        guard let client = MacrosRegistryHolder.shared.client else {
            return
        }
        do {
            let document = try await client.get(slug: slug)
            let data = try JSONEncoder().encode(document.toRadioMacroDocument())
            MacroURLBridge.shared.pending = PendingMacroDocument(
                data: data,
                provenance: .registry(slug: slug)
            )
        } catch {
            // No surface yet — registry fetch failures simply drop the
            // import. A future revision will route through a toast/banner.
        }
    }
}
