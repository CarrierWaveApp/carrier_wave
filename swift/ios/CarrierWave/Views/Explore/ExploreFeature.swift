import CarrierWaveData
import SwiftUI

// MARK: - ExploreFeature

/// A marquee feature surfaced in the Explore gallery (`ExploreView`).
///
/// Explore is the app's single "front door" for feature discovery
/// (docs/ux-north-star.md): every flagship capability gets a card with a
/// 5-second pitch and a "find it" hint, instead of relying on users to
/// excavate Settings, the Experiments hub, or dashboard customization.
///
/// Keep the catalog curated — roughly a dozen entries. If everything is
/// here, nothing is discoverable. When a feature graduates from
/// Experiments, keep its card and drop the `experiment` reference.
struct ExploreFeature: Identifiable {
    // MARK: Lifecycle

    init(
        id: String,
        title: String,
        icon: String,
        tint: Color,
        blurb: String,
        whereToFind: String,
        experiment: ExperimentalFeature? = nil
    ) {
        self.id = id
        self.title = title
        self.icon = icon
        self.tint = tint
        self.blurb = blurb
        self.whereToFind = whereToFind
        self.experiment = experiment
    }

    // MARK: Internal

    let id: String
    let title: String
    let icon: String
    let tint: Color
    /// One-sentence pitch — what's exciting, not how it works.
    let blurb: String
    /// Short navigation hint, e.g. "Home → On Air Now card".
    let whereToFind: String
    /// Set when the feature is still experiment-gated; drives the maturity
    /// badge and (for hidden experiments) the inline enable toggle.
    let experiment: ExperimentalFeature?
}

// MARK: - Catalog

extension ExploreFeature {
    /// Features that are on for everyone (possibly with an experimental
    /// badge) — tapping into them requires no setup.
    static let readyToUse: [ExploreFeature] = [
        ExploreFeature(
            id: "hunterLog",
            title: "Hunter Log",
            icon: "binoculars.fill",
            tint: .orange,
            blurb: "Live POTA, SOTA, and DX spots with one-tap logging, "
                + "worked-before badges, and friend alerts.",
            whereToFind: "Sessions tab → Hunt"
        ),
        ExploreFeature(
            id: "tuneIn",
            title: "Tune In",
            icon: "headphones",
            tint: .purple,
            blurb: "Hear any spot live through a nearby WebSDR receiver — "
                + "listen to the pileup before you call.",
            whereToFind: "Tap a spot, then Tune In",
            experiment: .tuneIn
        ),
        ExploreFeature(
            id: "bragSheet",
            title: "Brag Sheet",
            icon: "rosette",
            tint: .pink,
            blurb: "Shareable highlight cards of your stats, records, and "
                + "maps — for one outing or the whole year.",
            whereToFind: "Home → Brag Sheet card, or when ending a session"
        ),
        ExploreFeature(
            id: "sessionReplay",
            title: "Session Replay",
            icon: "play.circle",
            tint: .blue,
            blurb: "Scrub through an activation on a map and watch your "
                + "QSOs and RBN spots land in order.",
            whereToFind: "Any session detail → map insights"
        ),
        ExploreFeature(
            id: "videoExport",
            title: "Video Export",
            icon: "film",
            tint: .indigo,
            blurb: "Turn a session into an animated map video ready for "
                + "social media.",
            whereToFind: "Session detail → Export Video",
            experiment: .videoExport
        ),
        ExploreFeature(
            id: "awards",
            title: "Awards & Certificates",
            icon: "trophy.fill",
            tint: .yellow,
            blurb: "Track POTA award progress across eight categories and "
                + "see exactly what's left.",
            whereToFind: "Sessions tab → Awards & Certificates"
        ),
        ExploreFeature(
            id: "ft8",
            title: "FT8",
            icon: "waveform",
            tint: .teal,
            blurb: "Decode and work FT8 with just your phone's mic and "
                + "speaker next to the rig — no cables.",
            whereToFind: "Start a session with FT8 as the mode",
            experiment: .ft8
        ),
        ExploreFeature(
            id: "smartSpots",
            title: "Smart Spots",
            icon: "sparkles",
            tint: .mint,
            blurb: "Spots ranked by what you actually need — new states, "
                + "DXCC entities, and parks.",
            whereToFind: "Home → Customize → Smart Spots card",
            experiment: .needs
        ),
        ExploreFeature(
            id: "logScanning",
            title: "Log Scanning",
            icon: "doc.text.viewfinder",
            tint: .brown,
            blurb: "Point the camera at a handwritten paper log and import "
                + "it as QSOs.",
            whereToFind: "Logbook → toolbar → import"
        ),
        ExploreFeature(
            id: "dxpeditions",
            title: "DXpeditions",
            icon: "globe",
            tint: .cyan,
            blurb: "See which rare entities are on the air right now and "
                + "this month.",
            whereToFind: "Home → On Air Now card"
        ),
        ExploreFeature(
            id: "transcription",
            title: "CW Transcription",
            icon: "waveform.badge.mic",
            tint: .red,
            blurb: "Real-time CW decoding with chat-style conversation "
                + "bubbles and callsign detection.",
            whereToFind: "CW tab (add it from More → Customize)"
        ),
    ]

    /// Hidden experiments worth advertising — these need an explicit opt-in,
    /// which the Explore row offers inline.
    static let optIn: [ExploreFeature] = [
        ExploreFeature(
            id: "propagationCheck",
            title: "Propagation Check",
            icon: "dot.radiowaves.up.forward",
            tint: .blue,
            blurb: "How's my antenna? CQ while the app watches RBN and PSK "
                + "Reporter, then compare antennas or bands.",
            whereToFind: "More tab → Propagation Check once enabled",
            experiment: .propagationCheck
        ),
        ExploreFeature(
            id: "weatherRadar",
            title: "Weather Radar",
            icon: "cloud.rain",
            tint: .teal,
            blurb: "NEXRAD radar and NWS alerts for your operating spot "
                + "(US only) — know when to pack up.",
            whereToFind: "Logger → Weather panel once enabled",
            experiment: .weatherRadar
        ),
    ]
}
