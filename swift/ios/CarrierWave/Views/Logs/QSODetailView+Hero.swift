import CarrierWaveCore
import CarrierWaveData
import SwiftUI

// MARK: - Hero, Key Facts, Stats Strip, Station Cards

/// Visual-hierarchy redesign of the QSO detail view. Replaces the old
/// label/value list with a scannable layout:
///
/// 1. Hero — big callsign + name + location
/// 2. Key Facts — band/mode/frequency pills, timestamp, RST exchange
/// 3. Stats Strip — distance, bearing, watts per km/mi
/// 4. Stations — side-by-side "They" vs "Me" cards
extension QSODetailView {
    // MARK: - Hero

    var heroSection: some View {
        Section {
            VStack(spacing: 6) {
                NavigationLink {
                    CallsignHistoryView(callsign: qso.callsign)
                } label: {
                    HStack(spacing: 8) {
                        Text(qso.callsign)
                            .font(.system(size: 36, weight: .bold, design: .monospaced))
                        Image(systemName: "person.crop.circle")
                            .font(.title2)
                            .foregroundStyle(.tint)
                    }
                }
                .buttonStyle(.plain)

                if let name = qso.name?.nonEmpty {
                    Text(name.capitalized)
                        .font(.headline)
                        .foregroundStyle(.primary)
                }

                if let locationLine {
                    Text(locationLine)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 6) {
                    if let licenseClass = qso.theirLicenseClass?.nonEmpty {
                        heroBadge(licenseClass, color: .accentColor)
                    }
                    if qso.isContestQSO, let contest = qso.contestName?.nonEmpty {
                        heroBadge(contest, color: .orange)
                    }
                }

                if let changeNote = qso.callsignChangeNote {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                        Text(changeNote)
                    }
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .padding(.top, 2)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .listRowBackground(Color.clear)
        }
    }

    func heroBadge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.2))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }

    // MARK: - Key Facts

    /// Band / Mode / Frequency as pills, timestamp, and RST as a
    /// "sent ↔ received" exchange line. Replaces the scattered rows in
    /// the old Contact section.
    var keyFactsSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                factPillRow
                timestampLine
                rstExchangeRow
            }
            .padding(.vertical, 4)
        } header: {
            Text("Contact")
        }
    }

    var factPillRow: some View {
        HStack(spacing: 6) {
            factPill(qso.band, tint: .blue)
            factPill(qso.mode, tint: .purple)
            if let freq = qso.frequency {
                factPill(FrequencyFormatter.formatWithUnit(freq), tint: .teal)
            }
            Spacer()
        }
    }

    var timestampLine: some View {
        HStack(spacing: 6) {
            Image(systemName: "clock")
                .foregroundStyle(.secondary)
            Text(Self.utcDateTimeFormatter.string(from: qso.timestamp) + "Z")
                .font(.subheadline.monospacedDigit())
        }
    }

    @ViewBuilder
    var rstExchangeRow: some View {
        if qso.rstSent != nil || qso.rstReceived != nil {
            HStack(spacing: 10) {
                rstStack(label: "Sent", value: qso.rstSent)
                Image(systemName: "arrow.left.arrow.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                rstStack(label: "Received", value: qso.rstReceived)
                Spacer()
            }
        }
    }

    func rstStack(label: String, value: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value ?? "—")
                .font(.title3.monospacedDigit().weight(.semibold))
        }
    }

    func factPill(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(.footnote.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(tint.opacity(0.18))
            .foregroundStyle(tint)
            .clipShape(Capsule())
    }

    // MARK: - Stats Strip

    /// Inline row of distance / bearing / efficiency badges. Only renders
    /// when we can compute at least one of them from the two grids.
    @ViewBuilder
    var statsStripSection: some View {
        if hasStatsStrip {
            Section {
                HStack(spacing: 12) {
                    if let km = distanceKm {
                        statChip(
                            icon: "globe",
                            primary: "\(kmFormatter.string(from: km)) km",
                            secondary: "\(kmFormatter.string(from: km * milesPerKm)) mi"
                        )
                    }
                    if let bearing = bearingDegrees {
                        statChip(
                            icon: "location.north",
                            primary: "\(Int(bearing.rounded()))°",
                            secondary: compassPoint(bearing)
                        )
                    }
                    if let efficiency = efficiencyLabel {
                        statChip(
                            icon: "bolt",
                            primary: efficiency.primary,
                            secondary: efficiency.secondary
                        )
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    func statChip(icon: String, primary: String, secondary: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(primary)
                    .font(.subheadline.weight(.semibold).monospacedDigit())
            }
            Text(secondary)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    var hasStatsStrip: Bool {
        distanceKm != nil || bearingDegrees != nil
    }

    /// Great-circle distance between operator and contact grid squares, in km.
    var distanceKm: Double? {
        guard let mine = qso.myGrid?.nonEmpty,
              let theirs = qso.theirGrid?.nonEmpty
        else {
            return nil
        }
        return MaidenheadConverter.distanceKm(from: mine, to: theirs)
    }

    var bearingDegrees: Double? {
        guard let mine = qso.myGrid?.nonEmpty,
              let theirs = qso.theirGrid?.nonEmpty
        else {
            return nil
        }
        return MaidenheadConverter.bearing(from: mine, to: theirs)
    }

    /// (watts/km, watts/mi) efficiency label, or nil if power/distance missing.
    var efficiencyLabel: (primary: String, secondary: String)? {
        guard let km = distanceKm, km > 0,
              let power = qso.power, power > 0
        else {
            return nil
        }
        let perKm = Double(power) / km
        let perMi = Double(power) / (km * milesPerKm)
        return (
            "\(efficiencyFormatter.string(from: perKm)) W/km",
            "\(efficiencyFormatter.string(from: perMi)) W/mi"
        )
    }

    func compassPoint(_ degrees: Double) -> String {
        let points = [
            "N", "NNE", "NE", "ENE",
            "E", "ESE", "SE", "SSE",
            "S", "SSW", "SW", "WSW",
            "W", "WNW", "NW", "NNW",
        ]
        let normalised = ((degrees.truncatingRemainder(dividingBy: 360)) + 360)
            .truncatingRemainder(dividingBy: 360)
        let idx = Int((normalised / 22.5).rounded()) % points.count
        return points[idx]
    }

    // MARK: - Side-by-side Stations

    /// "Them" and "Me" as two compact cards. Merges the old My Station /
    /// Their Location sections and enriches with StationProfile equipment.
    var stationsSection: some View {
        Section {
            HStack(alignment: .top, spacing: 12) {
                stationCard(
                    title: "THEY",
                    callsign: qso.callsign,
                    items: theirStationItems
                )
                stationCard(
                    title: "ME",
                    callsign: qso.myCallsign.nonEmpty ?? "—",
                    items: myStationItems
                )
            }
            .padding(.vertical, 4)
        }
    }

    func stationCard(title: String, callsign: String, items: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
            Text(callsign)
                .font(.body.monospaced().weight(.semibold))
            ForEach(items, id: \.0) { item in
                VStack(alignment: .leading, spacing: 0) {
                    Text(item.0)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Text(item.1)
                        .font(.caption)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.secondary.opacity(0.08))
        )
    }

    var theirStationItems: [(String, String)] {
        var items: [(String, String)] = []
        if let grid = qso.theirGrid?.nonEmpty {
            items.append(("Grid", grid))
        }
        let locationParts = [qso.qth, qso.state, qso.country].compactMap(\.?.nonEmpty)
        if !locationParts.isEmpty {
            items.append(("Location", locationParts.joined(separator: ", ")))
        }
        if let entity = qso.dxccEntity {
            items.append(("DXCC", "\(entity.name) (#\(entity.number))"))
        }
        if let park = qso.theirParkReference?.nonEmpty {
            items.append(("POTA", theirParkName.map { "\(park) — \($0)" } ?? park))
        }
        return items
    }

    var myStationItems: [(String, String)] {
        var items: [(String, String)] = []
        if let grid = qso.myGrid?.nonEmpty {
            items.append(("Grid", grid))
        }
        if let stationCall = qso.stationCallsign?.nonEmpty {
            items.append(("Club Call", stationCall))
        }
        if let rig = qso.myRig?.nonEmpty {
            items.append(("Rig", rig))
        }
        if let power = qso.power {
            items.append(("Power", "\(power) W"))
        }
        if let profile = qso.stationProfileName?.nonEmpty {
            items.append(("Profile", profile))
        }
        if let park = qso.parkReference?.nonEmpty {
            items.append(("POTA", myParkName.map { "\(park) — \($0)" } ?? park))
        }
        // Enrich with equipment from a matching StationProfile.
        if let matched = matchedStationProfile {
            if let antenna = matched.antenna?.nonEmpty {
                items.append(("Antenna", antenna))
            }
            if let key = matched.key?.nonEmpty {
                items.append(("Key", key))
            }
            if let mic = matched.mic?.nonEmpty {
                items.append(("Mic", mic))
            }
        }
        return items
    }

    /// Matching `StationProfile` for this QSO's `stationProfileName`, if any.
    var matchedStationProfile: StationProfile? {
        guard let name = qso.stationProfileName?.nonEmpty?.lowercased() else {
            return nil
        }
        return StationProfileStorage.load()
            .first { $0.name.lowercased() == name }
    }
}

// MARK: - Formatters & Constants

private let milesPerKm = 0.621371

private let kmFormatter: NumberFormatter = {
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    formatter.maximumFractionDigits = 0
    formatter.usesGroupingSeparator = true
    return formatter
}()

private let efficiencyFormatter: NumberFormatter = {
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    formatter.minimumFractionDigits = 2
    formatter.maximumFractionDigits = 3
    return formatter
}()

private extension NumberFormatter {
    func string(from value: Double) -> String {
        string(from: NSNumber(value: value)) ?? "\(value)"
    }
}
