import CoreGraphics

// MARK: - SpotHitRects

/// Hit-test rectangles recorded by a spot Canvas during its last draw.
///
/// A plain reference type on purpose: the Canvas draw closure writes these on
/// every draw, and keeping them in `@State` (a non-Equatable array) made each
/// write invalidate the view and schedule another draw — a redraw loop that
/// pinned the main thread at ~100% CPU whenever a band scope or band map was
/// visible. Mutating this object's property doesn't invalidate anything.
@MainActor
final class SpotHitRects {
    var rects: [(CGRect, EnrichedSpot)] = []

    /// The spot drawn under `point`, if any.
    func spot(at point: CGPoint) -> EnrichedSpot? {
        rects.first { $0.0.contains(point) }?.1
    }
}
