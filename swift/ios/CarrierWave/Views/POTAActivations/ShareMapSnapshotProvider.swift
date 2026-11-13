// Share Map Snapshot Provider
//
// Injectable seam around MKMapSnapshotter for the activation share card.
// The production provider wraps `MKMapSnapshotter.start()` in a hard
// timeout so an offline device never hangs the brag sheet; tests inject a
// failing provider to exercise the deterministic offline fallback.

import CoreLocation
import MapKit
import UIKit

// MARK: - ShareMapSnapshot

/// A captured map tile plus the coordinate→pixel mapping needed to draw
/// annotations on top of it. Mirrors the two pieces of
/// `MKMapSnapshotter.Snapshot` the renderer actually uses.
nonisolated struct ShareMapSnapshot {
    let image: UIImage
    let point: (CLLocationCoordinate2D) -> CGPoint
}

// MARK: - ShareMapSnapshotProvider

/// Produces a map snapshot for the given options, or throws when imagery
/// cannot be fetched (offline, tile server error, timeout).
nonisolated struct ShareMapSnapshotProvider: Sendable {
    // MARK: Internal

    enum Failure: Error {
        case timedOut
        case unavailable
    }

    /// How long the MapKit provider waits for tiles before giving up and
    /// letting the caller draw the offline fallback.
    static let mapKitTimeout: Duration = .seconds(8)

    /// Production provider: `MKMapSnapshotter` bounded by `mapKitTimeout`.
    /// The timeout cancels the snapshotter, which makes `start()` throw, so
    /// the caller falls through to the offline fallback instead of hanging.
    static let mapKit = ShareMapSnapshotProvider { options in
        let box = SnapshotterBox(MKMapSnapshotter(options: options))
        let timeout = Task {
            try await Task.sleep(for: mapKitTimeout)
            box.snapshotter.cancel()
        }
        defer { timeout.cancel() }

        let snapshot = try await box.snapshotter.start()
        return ShareMapSnapshot(image: snapshot.image) { coordinate in
            snapshot.point(for: coordinate)
        }
    }

    /// A provider that always fails — the offline case, and the test seam.
    static let unavailable = ShareMapSnapshotProvider { _ in
        throw Failure.unavailable
    }

    let snapshot: @Sendable (MKMapSnapshotter.Options) async throws -> ShareMapSnapshot

    // MARK: Private

    /// `MKMapSnapshotter` is not `Sendable`; the box lets the timeout task
    /// reach it to cancel. Only `cancel()`/`start()` are ever called, and
    /// MapKit documents both as callable from any thread.
    private final class SnapshotterBox: @unchecked Sendable {
        // MARK: Lifecycle

        init(_ snapshotter: MKMapSnapshotter) {
            self.snapshotter = snapshotter
        }

        // MARK: Internal

        let snapshotter: MKMapSnapshotter
    }
}
