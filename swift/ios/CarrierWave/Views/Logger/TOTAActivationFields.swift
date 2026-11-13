// TOTA-specific activation inputs for SessionStartSheet.
//
// Layout: a two-column block (lat / lon / grid stack on the left, a small
// MapKit preview on the right) for the activation site, followed by the
// "Record GPS track" toggle and the bonus checkboxes.
//
// Lat/lon use local @State strings as the source of truth so partial typing
// (e.g. "47." or "-122.") doesn't get blown away by an unparseable round-trip
// through the parent's `Double?` bindings. The Detect button writes raw GPS
// (not the grid centre) so we keep sub-grid precision for distance scoring.

import CarrierWaveCore
import CarrierWaveData
import CoreLocation
import MapKit
import SwiftUI

// MARK: - TOTAActivationFields

struct TOTAActivationFields: View {
    // MARK: Internal

    @Binding var activationLatitude: Double?
    @Binding var activationLongitude: Double?
    @Binding var recordTrack: Bool
    /// Read-only — derived from `parsedPower` upstream. The view shows the
    /// status with an inline explanation; users change it by editing wattage.
    let parsedPower: Int?
    @Binding var withPets: Bool
    @Binding var withKids: Bool
    @Binding var winlinkSent: Bool
    @Binding var aprsSent: Bool
    @Binding var varacSent: Bool
    @Binding var adaptiveSport: Bool
    @Binding var ruckWeightPounds: Double?
    @Binding var category: TOTACategory
    @Binding var winterOverride: Bool?
    @Binding var personalEffortFactor: Int

    /// True when the parent auto-filled `ruckWeightPounds` from selected gear.
    /// Shown as a small "auto" hint and used by the parent to know whether to
    /// overwrite on subsequent changes.
    let ruckWeightAutoFilled: Bool
    /// Auto-detected winter flag for the operator to compare against / override.
    let autoDetectedWinter: Bool

    var body: some View {
        categoryRow
            .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
        siteRow
            .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
        if category == .standard {
            trackToggleRow
                .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
        }
        qrpRow
            .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
        if category == .standard {
            winterRow
                .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
            bonusRows
            ruckWeightRow
                .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
        }
        personalEffortRow
            .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
    }

    // MARK: Private

    @State private var latText: String = ""
    @State private var lonText: String = ""
    @State private var ruckText: String = ""
    @State private var hasSyncedFromBinding = false
    @State private var gridLocationService = GridLocationService()
    @AppStorage("useMetricUnits") private var useMetricUnits = false

    private var coordinate: CLLocationCoordinate2D? {
        guard let lat = activationLatitude, let lon = activationLongitude else {
            return nil
        }
        guard CLLocationCoordinate2DIsValid(CLLocationCoordinate2D(latitude: lat, longitude: lon)) else {
            return nil
        }
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    private var gridString: String {
        guard let coord = coordinate else {
            return "—"
        }
        return MaidenheadConverter.grid(from: coord)
    }

    private var isQRP: Bool {
        guard let watts = parsedPower else {
            return false
        }
        return watts <= 10
    }

    private var qrpReason: String {
        guard let watts = parsedPower else {
            return "Set a wattage above to determine QRP status. "
                + "TOTA awards a 2× multiplier for sessions held entirely at ≤ 10 W."
        }
        if watts <= 10 {
            return "Power \(watts) W is at or below TOTA's 10 W QRP threshold. "
                + "Drops automatically if you raise wattage above 10 W."
        }
        return "Power \(watts) W is above TOTA's 10 W QRP threshold. "
            + "Lower the wattage to ≤ 10 W to qualify for the 2× multiplier."
    }

    private var unitSuffix: String {
        useMetricUnits ? "kg" : "lb"
    }

    private var siteRow: some View {
        HStack(alignment: .top, spacing: 12) {
            siteFields
                .frame(maxWidth: 150, alignment: .leading)
            siteMap
        }
        .padding(.vertical, 4)
        .onAppear { syncFromBindings() }
        .onChange(of: gridLocationService.currentGrid) { _, _ in
            applyDetectedCoordinate(gridLocationService.currentCoordinate)
        }
        .onChange(of: latText) { _, value in
            activationLatitude = parseCoordinate(value)
        }
        .onChange(of: lonText) { _, value in
            activationLongitude = parseCoordinate(value)
        }
    }

    private var siteFields: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Activation site")
                .font(.subheadline.weight(.medium))
            coordinateField(label: "Lat", text: $latText)
            coordinateField(label: "Lon", text: $lonText)
            HStack(spacing: 4) {
                Text("Grid")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(gridString)
                    .font(.caption.monospaced())
                    .foregroundStyle(coordinate == nil ? .secondary : .primary)
            }
            Button {
                gridLocationService.requestGrid()
            } label: {
                if gridLocationService.isLocating {
                    ProgressView().controlSize(.small)
                } else {
                    Label("Detect", systemImage: "location.fill")
                        .font(.caption.weight(.medium))
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(gridLocationService.isLocating)
        }
    }

    @ViewBuilder
    private var siteMap: some View {
        if let coord = coordinate {
            Map(
                initialPosition: .region(
                    MKCoordinateRegion(
                        center: coord,
                        latitudinalMeters: 4_000,
                        longitudinalMeters: 4_000
                    )
                )
            ) {
                Marker("", systemImage: "antenna.radiowaves.left.and.right", coordinate: coord)
                    .tint(Color.accentColor)
            }
            .allowsHitTesting(false)
            .frame(maxWidth: .infinity)
            .frame(height: 130)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.tertiarySystemFill))
                VStack(spacing: 4) {
                    Image(systemName: "map")
                        .font(.title3)
                    Text("No coordinates")
                        .font(.caption2)
                }
                .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 130)
        }
    }

    private var trackToggleRow: some View {
        Toggle(isOn: $recordTrack) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Record GPS track")
                    .font(.subheadline.weight(.medium))
                Text("Auto-fills distance & elevation gain from your route.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var bonusRows: some View {
        Toggle("With kids (+20 %)", isOn: $withKids)
        Toggle("With pets (+15 %)", isOn: $withPets)
        Toggle("Winlink RF sent (+5)", isOn: $winlinkSent)
        Toggle("APRS RF sent (+5)", isOn: $aprsSent)
        Toggle("VarAC RF sent (+5)", isOn: $varacSent)
        Toggle("Adaptive sport", isOn: $adaptiveSport)
    }

    private var qrpRow: some View {
        let qrpActive = isQRP
        return HStack(alignment: .top, spacing: 10) {
            Image(systemName: qrpActive ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(qrpActive ? .green : .secondary)
                .font(.title3)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text("QRP — 2× multiplier")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(qrpActive ? .primary : .secondary)
                Text(qrpReason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private var ruckWeightRow: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text("Ruck weight")
                Spacer()
                TextField("0", text: $ruckText)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 70)
                Text(unitSuffix)
                    .foregroundStyle(.secondary)
                    .frame(width: 24, alignment: .leading)
            }
            ruckFooter
        }
        .onAppear { syncRuckTextFromPounds() }
        .onChange(of: ruckWeightPounds) { _, _ in
            syncRuckTextFromPounds()
        }
        .onChange(of: useMetricUnits) { _, _ in
            // Re-render the displayed value in the new unit. Pounds is the
            // canonical storage so we don't lose precision across toggles.
            syncRuckTextFromPounds()
        }
        .onChange(of: ruckText) { _, value in
            // Parse user input back into pounds. Empty → nil so the field
            // can be cleared.
            ruckWeightPounds = parseUserWeight(value)
        }
    }

    @ViewBuilder
    private var ruckFooter: some View {
        if ruckWeightAutoFilled, let pounds = ruckWeightPounds, pounds > 0 {
            Text("Estimated from your selected gear (\(formattedDisplay(forPounds: pounds))). "
                + "Edit to override.")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            Text("Optional: TOTA awards +5 % per 5 lb carried.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func coordinateField(label: String, text: Binding<String>) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(width: 24, alignment: .leading)
            TextField("—", text: text)
                .keyboardType(.numbersAndPunctuation)
                .multilineTextAlignment(.trailing)
                .font(.subheadline.monospaced())
                .textFieldStyle(.roundedBorder)
        }
    }

    /// User-edit → canonical pounds. Treats input as kg when metric is on.
    private func parseUserWeight(_ raw: String) -> Double? {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, let value = Double(trimmed), value > 0 else {
            return nil
        }
        if useMetricUnits {
            return Measurement(value: value, unit: UnitMass.kilograms)
                .converted(to: .pounds)
                .value
        }
        return value
    }

    /// Pounds (canonical) → string in the user's chosen unit, rounded to 0.1.
    private func syncRuckTextFromPounds() {
        guard let pounds = ruckWeightPounds, pounds > 0 else {
            if !ruckText.isEmpty {
                ruckText = ""
            }
            return
        }
        let displayed = displayedValue(forPounds: pounds)
        let formatted = String(format: "%g", displayed)
        // Avoid clobbering mid-edit if our re-format would just round to the
        // user's exact text — sparing the cursor a jump.
        if formatted != ruckText {
            ruckText = formatted
        }
    }

    private func displayedValue(forPounds pounds: Double) -> Double {
        if useMetricUnits {
            let kilograms = Measurement(value: pounds, unit: UnitMass.pounds)
                .converted(to: .kilograms)
                .value
            return (kilograms * 10).rounded() / 10
        }
        return (pounds * 10).rounded() / 10
    }

    private func formattedDisplay(forPounds pounds: Double) -> String {
        let value = displayedValue(forPounds: pounds)
        return "\(String(format: "%g", value)) \(unitSuffix)"
    }
}

// MARK: - Helpers (extension keeps the main struct body under SwiftLint's cap)

private extension TOTAActivationFields {
    /// One-time copy of any pre-existing binding values into the local strings.
    /// Re-running this on every appear would clobber active typing.
    func syncFromBindings() {
        guard !hasSyncedFromBinding else {
            return
        }
        hasSyncedFromBinding = true
        if let lat = activationLatitude {
            latText = Self.format(coordinate: lat)
        }
        if let lon = activationLongitude {
            lonText = Self.format(coordinate: lon)
        }
    }

    func applyDetectedCoordinate(_ coord: CLLocationCoordinate2D?) {
        guard let coord else {
            return
        }
        latText = Self.format(coordinate: coord.latitude)
        lonText = Self.format(coordinate: coord.longitude)
    }

    /// Permissive parse: empty → nil, anything not a number → leaves binding alone
    /// by returning the previous value. The user can still type `47.` mid-entry
    /// without losing their string.
    func parseCoordinate(_ raw: String) -> Double? {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            return nil
        }
        return Double(trimmed)
    }

    static func format(coordinate value: Double) -> String {
        String(format: "%.5f", value)
    }

    static func format(weight: Double?) -> String {
        guard let value = weight, value > 0 else {
            return ""
        }
        return String(format: "%g", value)
    }
}
