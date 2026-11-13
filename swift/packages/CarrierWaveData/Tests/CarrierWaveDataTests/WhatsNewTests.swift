import Foundation
import Testing
@testable import CarrierWaveData

@Test func versionComparison() {
    #expect(WhatsNewVersion("0.7.0") < WhatsNewVersion("0.8.0"))
    #expect(WhatsNewVersion("1.0.0") > WhatsNewVersion("0.99.99"))
    #expect(WhatsNewVersion("0.8.0") == WhatsNewVersion("0.8.0-beta.1"))
    #expect(WhatsNewVersion("0.8.1") > WhatsNewVersion("0.8.0"))
    #expect(WhatsNewVersion("2") > WhatsNewVersion("1.99.99"))
}

@Test func unseenEntriesFiltersByVersionAndPlatform() {
    let catalog = [
        WhatsNewEntry(
            version: "0.8.0",
            date: Date(),
            headline: "Eight",
            platforms: [.iOS, .macOS],
            items: [WhatsNewItem(kind: .feature, title: "Foo")]
        ),
        WhatsNewEntry(
            version: "0.7.0",
            date: Date(),
            headline: "Seven",
            platforms: [.iOS],
            items: [WhatsNewItem(kind: .feature, title: "Bar")]
        ),
    ]

    let iosUnseen = WhatsNewCatalog.unseenEntries(
        currentVersion: "0.8.0",
        lastSeenVersion: "0.6.0",
        platform: .iOS,
        catalog: catalog
    )
    #expect(iosUnseen.map(\.version) == ["0.8.0", "0.7.0"])

    let macUnseen = WhatsNewCatalog.unseenEntries(
        currentVersion: "0.8.0",
        lastSeenVersion: "0.6.0",
        platform: .macOS,
        catalog: catalog
    )
    #expect(macUnseen.map(\.version) == ["0.8.0"])
}

@Test func unseenEntriesEmptyWhenCaughtUp() {
    let catalog = [
        WhatsNewEntry(
            version: "0.8.0",
            date: Date(),
            headline: "Eight",
            items: [WhatsNewItem(kind: .feature, title: "Foo")]
        ),
    ]
    let result = WhatsNewCatalog.unseenEntries(
        currentVersion: "0.8.0",
        lastSeenVersion: "0.8.0",
        platform: .iOS,
        catalog: catalog
    )
    #expect(result.isEmpty)
}

@Test func unseenEntriesEmptyOnFreshInstall() {
    let catalog = [
        WhatsNewEntry(
            version: "0.8.0",
            date: Date(),
            headline: "Eight",
            items: [WhatsNewItem(kind: .feature, title: "Foo")]
        ),
    ]
    let result = WhatsNewCatalog.unseenEntries(
        currentVersion: "0.8.0",
        lastSeenVersion: nil,
        platform: .iOS,
        catalog: catalog
    )
    #expect(result.isEmpty)
}

@MainActor
@Test func serviceMarksFreshInstallAndAcksCurrentVersion() {
    let suiteName = "WhatsNewTests.\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: suiteName) else {
        Issue.record("Could not create test UserDefaults")
        return
    }
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let catalog = [
        WhatsNewEntry(
            version: "0.8.0",
            date: Date(),
            headline: "Eight",
            items: [WhatsNewItem(kind: .feature, title: "Foo")]
        ),
    ]
    let bundle = StubBundle(version: "0.8.0")
    let service = WhatsNewService(
        platform: .iOS,
        bundle: bundle,
        defaults: defaults,
        catalog: catalog
    )

    // Fresh install: nothing pending, mark seen so the next update triggers it.
    #expect(service.pendingEntries.isEmpty)
    service.markFreshInstallIfNeeded()
    #expect(defaults.string(forKey: WhatsNewService.lastSeenKey(for: .iOS)) == "0.8.0")

    // Simulate an upgrade by bumping the bundle version.
    bundle.version = "0.9.0"
    let nextCatalog = catalog + [
        WhatsNewEntry(
            version: "0.9.0",
            date: Date(),
            headline: "Nine",
            items: [WhatsNewItem(kind: .improvement, title: "Faster")]
        ),
    ]
    let nextService = WhatsNewService(
        platform: .iOS,
        bundle: bundle,
        defaults: defaults,
        catalog: nextCatalog
    )
    #expect(nextService.pendingEntries.map(\.version) == ["0.9.0"])

    nextService.markCurrentVersionSeen()
    #expect(nextService.pendingEntries.isEmpty)
}

// MARK: - StubBundle

private final class StubBundle: Bundle, @unchecked Sendable {
    // MARK: Lifecycle

    init(version: String) {
        self.version = version
        // Bundle has no public no-arg designated initializer; pass any
        // valid path so super.init succeeds and our object(forInfoDictionaryKey:)
        // override is what gets called by callers.
        super.init(path: Bundle.main.bundlePath)!
    }

    // MARK: Internal

    var version: String

    override func object(forInfoDictionaryKey key: String) -> Any? {
        key == "CFBundleShortVersionString" ? version : nil
    }
}
