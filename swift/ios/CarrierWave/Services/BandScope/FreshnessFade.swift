import UIKit

// MARK: - FreshnessFade

/// Scope-only age fade (spec §7): full ink ≤ 2 min, linear to a 0.4 floor
/// by 30 min, never below. Do NOT apply in Heard — list position already
/// encodes time there.
enum FreshnessFade {
    static func opacity(ageSeconds: TimeInterval) -> Double {
        let full = BandScopeTunables.fadeFullSeconds
        let floorAt = BandScopeTunables.fadeFloorSeconds
        let floor = BandScopeTunables.fadeFloorOpacity
        if ageSeconds <= full {
            return 1.0
        }
        if ageSeconds >= floorAt {
            return floor
        }
        let progress = (ageSeconds - full) / (floorAt - full)
        return 1.0 - progress * (1.0 - floor)
    }

    static func opacity(spotted: Date, now: Date = Date()) -> Double {
        opacity(ageSeconds: now.timeIntervalSince(spotted))
    }
}
