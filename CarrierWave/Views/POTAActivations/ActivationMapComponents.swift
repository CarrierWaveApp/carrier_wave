// Activation Map Components
//
// RST coloring, annotations, markers, and callout views
// shared between ActivationMapView and share card rendering.

import MapKit
import SwiftUI
import UIKit

// MARK: - RSTAnnotation

/// Annotation with RST-based color information
struct RSTAnnotation: Identifiable {
    let qsoId: UUID
    let callsign: String
    let coordinate: CLLocationCoordinate2D
    let color: Color
    let rstSent: String?
    let rstReceived: String?

    var id: UUID {
        qsoId
    }
}

// MARK: - RSTMarkerView

struct RSTMarkerView: View {
    let annotation: RSTAnnotation
    var isSelected: Bool = false

    var body: some View {
        Circle()
            .fill(annotation.color)
            .frame(width: isSelected ? 16 : 12, height: isSelected ? 16 : 12)
            .overlay(
                Circle()
                    .stroke(isSelected ? Color.white : Color.clear, lineWidth: 2)
            )
            .shadow(radius: isSelected ? 4 : 2)
            .animation(.easeInOut(duration: 0.2), value: isSelected)
    }
}

// MARK: - RSTColorHelper

enum RSTColorHelper {
    /// Compute color based on average of RST sent and received
    /// Green: average >= 55 (excellent)
    /// Yellow: average >= 45 (good)
    /// Red: average < 45 (weak)
    static func color(rstSent: String?, rstReceived: String?) -> Color {
        let avg = averageRST(rstSent, rstReceived)
        if avg >= 55 {
            return .green
        } else if avg >= 45 {
            return .yellow
        } else {
            return .red
        }
    }

    /// UIColor variant for CoreGraphics map snapshot rendering
    static func uiColor(rstSent: String?, rstReceived: String?) -> UIColor {
        let avg = averageRST(rstSent, rstReceived)
        if avg >= 55 {
            return .systemGreen
        } else if avg >= 45 {
            return .systemYellow
        } else {
            return .systemRed
        }
    }

    /// Parse RST string and extract numeric value
    /// "599" -> 59, "59" -> 59, "579" -> 57, "449" -> 44
    static func parseRST(_ rst: String?) -> Int? {
        guard let rst, !rst.isEmpty else {
            return nil
        }

        let digits = rst.filter(\.isNumber)

        guard !digits.isEmpty else {
            return nil
        }

        // For 3-digit RST (CW/digital): take first two digits (RS portion)
        // For 2-digit RS (phone): take both digits
        if digits.count >= 2 {
            let rs = String(digits.prefix(2))
            return Int(rs)
        } else if digits.count == 1 {
            return Int(digits)! * 10
        }

        return nil
    }

    /// Calculate average of sent and received RST values
    /// Returns default of 55 if neither can be parsed
    static func averageRST(_ sent: String?, _ received: String?) -> Int {
        let sentValue = parseRST(sent)
        let receivedValue = parseRST(received)

        switch (sentValue, receivedValue) {
        case let (sent?, received?):
            return (sent + received) / 2
        case (let sent?, nil):
            return sent
        case (nil, let received?):
            return received
        case (nil, nil):
            return 55
        }
    }
}

// MARK: - ActivationQSOCallout

struct ActivationQSOCallout: View {
    let qso: QSO

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(qso.callsign)
                    .font(.headline)
                Spacer()
                Text(qso.band)
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.blue.opacity(0.2))
                    .clipShape(Capsule())
                Text(qso.mode)
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.green.opacity(0.2))
                    .clipShape(Capsule())
            }

            HStack {
                if let grid = qso.theirGrid {
                    Text(grid)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if let sent = qso.rstSent {
                    Text("S: \(sent)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let rcvd = qso.rstReceived {
                    Text("R: \(rcvd)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let name = qso.name {
                Text(name)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}
