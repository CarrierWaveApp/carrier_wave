import CarrierWaveCore
import SwiftUI

// MARK: - SessionQSORow

/// Compact QSO row used in session detail views.
/// Tap-to-edit and swipe-to-delete handled by parent.
struct SessionQSORow: View {
    // MARK: Internal

    let qso: QSO
    var isSpotted: Bool = false

    var body: some View {
        HStack(spacing: 8) {
            if isSpotted {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.caption)
                    .foregroundStyle(.teal)
            }

            Text(qso.callsign)
                .font(.subheadline.monospaced().weight(.semibold))

            Spacer()

            pill(qso.band, color: .blue)
            pill(qso.mode, color: .green)

            Text(Self.timeFormatter.string(from: qso.timestamp))
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
    }

    // MARK: Private

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()

    private func pill(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15))
            .clipShape(Capsule())
    }
}

// MARK: - SessionQSOExpandedDetail

/// Compact display of all populated QSO fields, shown when a row is expanded.
struct SessionQSOExpandedDetail: View {
    // MARK: Internal

    let qso: QSO

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Top row: time + frequency + RST
            topInfoRow
                .padding(.bottom, 8)

            Divider()

            // Contact info
            if hasContactInfo {
                contactInfoSection
                    .padding(.vertical, 8)
                Divider()
            }

            // Location & parks
            if hasLocationInfo {
                locationSection
                    .padding(.vertical, 8)
                Divider()
            }

            // Equipment & extras
            if hasExtras {
                extrasSection
                    .padding(.vertical, 8)
            }

            // Notes
            if let notes = qso.notes, !notes.isEmpty {
                if hasExtras {
                    Divider()
                }
                notesSection(notes)
                    .padding(.vertical, 8)
            }
        }
        .padding(.top, 4)
    }

    // MARK: Private

    private static let utcFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()

    private var hasContactInfo: Bool {
        qso.name != nil || qso.dxccEntity != nil || qso.theirLicenseClass != nil
    }

    private var hasLocationInfo: Bool {
        qso.myGrid != nil || qso.theirGrid != nil
            || qso.parkReference != nil || qso.theirParkReference != nil
            || qso.sotaRef != nil || qso.qth != nil || qso.state != nil
            || qso.country != nil
    }

    private var hasExtras: Bool {
        qso.power != nil || qso.myRig != nil
    }

    // MARK: - Top Info Row

    private var topInfoRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            iconRow(
                "clock", Self.utcFormatter.string(from: qso.timestamp) + "Z",
                color: .secondary
            )

            if let freq = qso.frequency {
                iconRow("waveform", FrequencyFormatter.formatWithUnit(freq), color: .blue)
            }

            if qso.rstSent != nil || qso.rstReceived != nil {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.left.arrow.right")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                        .frame(width: 16)
                    if let sent = qso.rstSent {
                        rstBadge(sent, label: "S")
                    }
                    if let rcvd = qso.rstReceived {
                        rstBadge(rcvd, label: "R")
                    }
                }
            }
        }
    }

    // MARK: - Contact Info

    private var contactInfoSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let name = qso.name {
                iconRow("person.fill", name.capitalized, color: .primary)
            }

            if let entity = qso.dxccEntity {
                iconRow("globe", "\(entity.name) (#\(entity.number))", color: .blue)
            }

            if let licenseClass = qso.theirLicenseClass {
                HStack(spacing: 6) {
                    Image(systemName: "person.text.rectangle")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(width: 16)
                    Text(licenseClass)
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.2))
                        .clipShape(Capsule())
                }
            }
        }
    }

    // MARK: - Location

    private var locationSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            // QTH / state / country
            let locationParts = [qso.qth, qso.state, qso.country].compactMap(\.self)
            if !locationParts.isEmpty {
                iconRow(
                    "mappin.and.ellipse", locationParts.joined(separator: ", "),
                    color: .secondary
                )
            }

            // Grids side by side
            if qso.myGrid != nil || qso.theirGrid != nil {
                HStack(spacing: 12) {
                    if let grid = qso.myGrid {
                        gridBadge("My", grid: grid)
                    }
                    if let grid = qso.theirGrid {
                        gridBadge("Their", grid: grid)
                    }
                }
            }

            // Park references
            if let park = qso.parkReference {
                iconRow("leaf.fill", park, color: .green)
            }
            if let park = qso.theirParkReference {
                iconRow("leaf", park, color: .green)
            }

            if let sotaRef = qso.sotaRef {
                iconRow("mountain.2.fill", sotaRef, color: .brown)
            }
        }
    }

    // MARK: - Extras

    private var extrasSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let power = qso.power {
                iconRow("bolt.fill", "\(power)W", color: .yellow)
            }
            if let rig = qso.myRig {
                iconRow("radio", rig, color: .secondary)
            }
        }
    }

    private func rstBadge(_ value: String, label: String) -> some View {
        HStack(spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Text(value)
                .font(.caption2.monospaced().weight(.medium))
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 1)
        .background(Color.orange.opacity(0.15))
        .clipShape(RoundedRectangle(cornerRadius: 3))
    }

    // MARK: - Notes

    private func notesSection(_ notes: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "note.text")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(width: 16)
            Text(notes)
                .font(.caption)
                .foregroundStyle(.secondary)
                .italic()
        }
    }

    // MARK: - Helpers

    private func iconRow(
        _ icon: String, _ text: String, color: Color
    ) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundStyle(color)
                .frame(width: 16)
            Text(text)
                .font(.caption)
        }
    }

    private func gridBadge(_ label: String, grid: String) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Text(grid)
                .font(.caption.monospaced().weight(.medium))
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(Color.purple.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 3))
        }
    }
}
