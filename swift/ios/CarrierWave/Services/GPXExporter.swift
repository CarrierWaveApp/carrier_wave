// Minimal GPX 1.1 writer for session tracks.
//
// Produces a single `<trk>` with one `<trkseg>` containing all points; that's
// what TOTA's "Import GPX" path expects, and it's what every consumer (Garmin
// Connect, Strava, Komoot, Gaia GPS) reads. Elevation is emitted only when the
// device captured it.

import CarrierWaveData
import Foundation

enum GPXExporter {
    // MARK: Internal

    /// Build a UTF-8 GPX 1.1 string from recorded points. Returns `nil` for an
    /// empty point set (TOTA rejects empty tracks).
    static func encode(
        points: [TrackPoint],
        creator: String = "Carrier Wave: Field",
        trackName: String? = nil
    ) -> String? {
        guard !points.isEmpty else {
            return nil
        }

        var output = ""
        output.append(#"<?xml version="1.0" encoding="UTF-8"?>"#)
        output.append("\n")
        output.append(
            #"<gpx version="1.1" creator="\#(escape(creator))" "#
                + #"xmlns="http://www.topografix.com/GPX/1/1">"#
        )
        output.append("\n")
        output.append("  <trk>\n")
        if let name = trackName, !name.isEmpty {
            output.append("    <name>\(escape(name))</name>\n")
        }
        output.append("    <trkseg>\n")

        for point in points {
            let lat = format(point.latitude)
            let lon = format(point.longitude)
            output.append(#"      <trkpt lat="\#(lat)" lon="\#(lon)">"#)
            output.append("\n")
            if let elevation = point.elevationMeters {
                output.append("        <ele>\(format(elevation))</ele>\n")
            }
            output.append("        <time>\(iso8601(point.timestamp))</time>\n")
            output.append("      </trkpt>\n")
        }

        output.append("    </trkseg>\n")
        output.append("  </trk>\n")
        output.append("</gpx>\n")
        return output
    }

    /// Default filename for GPX exports — UTC-stamped and program-tagged so
    /// users can tell several activations' tracks apart in Files.app.
    static func defaultFilename(for activationDate: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return "tota-track-\(formatter.string(from: activationDate)).gpx"
    }

    // MARK: Private

    private static func format(_ value: Double) -> String {
        // 6 decimal places ≈ 11 cm precision — plenty for any consumer GPS,
        // and a stable string format avoids locale/scientific-notation issues.
        String(format: "%.6f", value)
    }

    private static func iso8601(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }

    private static func escape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
