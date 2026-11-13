import CarrierWaveCore
import SwiftUI

// MARK: - FrequencyScopeField

/// The Radio-section frequency control. Collapsed by default to a summary row
/// (frequency · band · live status) because the wizard auto-picks a clear
/// frequency; tapping it opens the band scope inline. Binds to the wizard's
/// `frequency` string so it drops in where the old text field lived.
struct FrequencyScopeField: View {
    // MARK: Internal

    @Binding var frequency: String

    let mode: String
    let license: LicenseClass
    let spots: [ScopeSpot]
    /// True while `frequency` is the wizard's auto-suggestion and untouched.
    let autoPicked: Bool
    /// True while the wizard is still auto-picking the starting frequency.
    let determining: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if showDetermining {
                determiningRow
            } else {
                summary
                if expanded {
                    expandedContent
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
        .onAppear {
            rebuildRows()
            syncFromFrequency()
        }
        .onChange(of: frequency) { _, _ in syncFromFrequency() }
        .onChange(of: centerHz) { _, _ in centerChanged() }
        .onChange(of: rebuildKey) { _, _ in rebuildRows() }
        .onChange(of: spots) { _, _ in rebuildRows() }
        .onChange(of: liveSpots) { _, _ in rebuildRows() }
        .task(id: "\(band)|\(mode)") { await loadSpots() }
    }

    // MARK: Private

    /// Ordered fine → coarse tuning steps, in Hz.
    private static let steps = [100, 1_000, 10_000]

    @State private var expanded = false
    @State private var centerHz = 14_290_000
    @State private var band = "20m"
    @State private var setText = ""
    @State private var touched = false
    /// Operator opened the scope; a later auto-pick landing must not collapse it.
    @State private var userOpened = false
    @State private var stepHz = 1_000
    /// Guards the auto-pick → `centerHz` write from being read as a user edit.
    @State private var programmatic = false
    /// Debounces writing `frequency` back to the wizard so a fling never
    /// re-renders the whole Form frame-by-frame (which would kill momentum).
    @State private var writeTask: Task<Void, Never>?
    /// Rows + their verdicts, rebuilt only when band/mode/license/step/spots
    /// change — never during scrolling.
    @State private var rows: [ScopeRowInfo] = []
    @State private var rowByHz: [Int: ScopeRowInfo] = [:]
    /// Live on-air stations for the current band+mode, loaded by the scope
    /// itself so it never depends on the wizard's (re-triggering) suggestion
    /// flow. Falls back to the injected `spots` (used by the preview).
    @State private var liveSpots: [ScopeSpot] = []
    @State private var isLoadingSpots = false

    /// Bumped on every rebuild so the scope re-centers without an O(n) array
    /// comparison on the scroll path.
    @State private var rowsVersion = 0
    /// Deliberate scroll jumps (find clear, auto-pick) — reads never scroll.
    @State private var scrollCommand: ScopeScrollCommand?
    @State private var scrollNonce = 0

    private var effectiveSpots: [ScopeSpot] {
        liveSpots.isEmpty ? spots : liveSpots
    }

    private var rebuildKey: String {
        "\(band)|\(mode)|\(license.rawValue)|\(stepHz)"
    }

    private var isDataMode: Bool {
        ["FT8", "FT4", "RTTY"].contains(mode.uppercased())
    }

    /// O(1) verdict for the centered row — no band-plan work on the scroll path.
    private var verdict: ScopeVerdict {
        if let info = rowByHz[centerHz] {
            return ScopeVerdict(isGood: info.isGood, message: info.advisory)
        }
        return FrequencyScopeLogic.evaluate(
            hz: centerHz,
            band: band,
            mode: mode,
            license: license,
            spots: effectiveSpots
        )
    }

    private var showAuto: Bool {
        autoPicked && !touched
    }

    /// Show the "finding a frequency" state until the wizard settles on one.
    private var showDetermining: Bool {
        determining && frequency.isEmpty && !touched
    }

    private var centerMHz: Double {
        Double(centerHz) / 1_000_000
    }

    private var stepLabel: String {
        switch stepHz {
        case 100: "100 Hz"
        case 10_000: "10 kHz"
        default: "1 kHz"
        }
    }

    /// Only until the wizard places *any* frequency — and never a dead end:
    /// "Set manually" claims the field so a slow spot source can't hold it.
    private var determiningRow: some View {
        HStack(spacing: 10) {
            ProgressView().controlSize(.small)
            Text("Finding an open frequency…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer(minLength: 4)
            Button("Set manually") { takeOverManually() }
                .font(.subheadline.weight(.semibold))
                .buttonStyle(.plain)
                .foregroundStyle(.blue)
        }
        .padding(.vertical, 8)
        .accessibilityLabel("Finding an open frequency")
    }

    // MARK: Summary (collapsed)

    private var summary: some View {
        Button {
            let willExpand = !expanded
            withAnimation(.easeInOut(duration: 0.22)) { expanded = willExpand }
            if willExpand {
                userOpened = true
                requestScroll(to: centerHz, animated: false) // land on the current freq, not the band edge
            } else {
                flushWrite() // commit the tuned frequency on close
            }
        } label: {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 8) {
                    Text(FrequencyFormatter.format(centerMHz))
                        .font(.title3.monospaced().weight(.semibold))
                        .foregroundStyle(.primary)
                    Text("MHz").font(.caption).foregroundStyle(.secondary)
                    bandPill
                    Spacer(minLength: 4)
                    HStack(spacing: 4) {
                        Text(expanded ? "Done" : "Change").font(.subheadline.weight(.semibold))
                        Image(systemName: expanded ? "chevron.up" : "chevron.down").font(.caption2.weight(.bold))
                    }
                    .foregroundStyle(.blue)
                }
                advisory
            }
            .padding(.vertical, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            "Frequency \(FrequencyFormatter.formatWithUnit(centerMHz)), \(expanded ? "tap to close" : "tap to change")"
        )
    }

    private var bandPill: some View {
        Text(band.replacingOccurrences(of: "m", with: " m"))
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 9).padding(.vertical, 3)
            .background(Color(.systemGray5), in: Capsule())
            .foregroundStyle(.secondary)
    }

    private var advisory: some View {
        HStack(spacing: 7) {
            if showAuto {
                Text("AUTO-PICKED")
                    .font(.system(size: 9.5, weight: .bold)).kerning(0.4)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Color.blue.opacity(0.15), in: Capsule())
                    .foregroundStyle(.blue)
            }
            ZStack {
                Circle().fill(verdict.isGood ? Color.green : Color.orange).frame(width: 16, height: 16)
                Image(systemName: verdict.isGood ? "checkmark" : "exclamationmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color(.systemBackground))
            }
            .accessibilityHidden(true)
            Text(verdict.attributed)
                .font(.footnote.weight(.medium))
                .foregroundStyle(verdict.isGood ? Color.green : Color.orange)
        }
    }

    // MARK: Expanded scope

    private var expandedContent: some View {
        VStack(spacing: 0) {
            bandStrip
            FrequencyScopeList(
                rows: rows, isGood: verdict.isGood, isDataMode: isDataMode,
                rowsVersion: rowsVersion, scrollCommand: scrollCommand, centerHz: $centerHz
            )
            .overlay(alignment: .top) { Divider() }
            .overlay(alignment: .bottom) { Divider() }
            .overlay {
                if isLoadingSpots, effectiveSpots.isEmpty {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Loading spots…").font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: Capsule())
                }
            }
            footer
        }
        .padding(.top, 8)
    }

    private var bandStrip: some View {
        HStack(spacing: 8) {
            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    ForEach(FrequencyScopeLogic.availableBands(), id: \.self) { option in
                        Button { switchBand(option) } label: {
                            Text(option)
                                .font(.subheadline.weight(.semibold))
                                .padding(.horizontal, 12).padding(.vertical, 6)
                                .background(
                                    option == band ? Color.blue : Color(.systemGray5),
                                    in: RoundedRectangle(cornerRadius: 9)
                                )
                                .foregroundStyle(option == band ? Color(.systemBackground) : .secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .scrollIndicators(.hidden)

            stepToggle
        }
        .padding(.bottom, 9)
    }

    /// 100 Hz ↔ 1 kHz ↔ 10 kHz tuning step — coarser sweeps the band faster,
    /// finer lands on the exact frequency.
    private var stepToggle: some View {
        Button(action: cycleStep) {
            HStack(spacing: 4) {
                Image(systemName: "arrow.up.arrow.down").font(.caption2.weight(.bold))
                Text(stepLabel).font(.caption.weight(.semibold)).monospacedDigit()
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(Color(.systemGray5), in: RoundedRectangle(cornerRadius: 9))
            .foregroundStyle(.blue)
        }
        .buttonStyle(.plain)
        .fixedSize()
        .accessibilityLabel("Tuning step \(stepLabel), tap to change")
    }

    private var footer: some View {
        HStack(spacing: 9) {
            HStack(spacing: 7) {
                Text("Set").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                TextField(FrequencyFormatter.format(centerMHz), text: $setText)
                    .keyboardType(.decimalPad)
                    .font(.body.monospaced().weight(.semibold))
                    .onSubmit(commitSetText)
                Text("MHz").font(.caption).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 11).padding(.vertical, 8)
            .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 9))

            Button(action: findClear) {
                Text("Find clear")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 12).padding(.vertical, 9)
                    .background(Color.blue.opacity(0.12), in: RoundedRectangle(cornerRadius: 9))
                    .foregroundStyle(.blue)
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 9)
    }

    /// Load on-air stations for this band (all sources/modes) directly, so the
    /// scope always reflects live activity regardless of the wizard's state.
    private func loadSpots() async {
        isLoadingSpots = true
        defer { isLoadingSpots = false }
        let stations = await ActiveSpotsLoader.load(mode: mode).filter { $0.band == band }
        liveSpots = stations.map(ScopeSpot.init(station:))
    }
}

// MARK: - FrequencyScopeField Behaviour

extension FrequencyScopeField {
    private func rebuildRows() {
        let built = FrequencyScopeLogic.buildRows(
            band: band,
            mode: mode,
            license: license,
            step: stepHz,
            spots: effectiveSpots
        )
        rows = built
        rowByHz = Dictionary(built.map { ($0.hz, $0) }, uniquingKeysWith: { first, _ in first })
        rowsVersion &+= 1
    }

    /// Ask the scope to scroll to a frequency (deliberate jumps only — scrolling
    /// itself never calls this).
    private func requestScroll(to hz: Int, animated: Bool) {
        scrollNonce &+= 1
        scrollCommand = ScopeScrollCommand(hz: hz, animated: animated, nonce: scrollNonce)
    }

    /// The last on-grid ruler row for the current band + step (band spans
    /// aren't always a multiple of the step).
    private func grid() -> (lo: Int, last: Int)? {
        guard let range = FrequencyScopeLogic.bandRangeHz(band) else {
            return nil
        }
        let last = range.lowerBound + ((range.upperBound - range.lowerBound) / stepHz) * stepHz
        return (range.lowerBound, last)
    }

    /// Snap a frequency onto the current step grid so it lands on a ruler row.
    private func snapped(_ hz: Int) -> Int {
        guard let grid = grid() else {
            return hz
        }
        let aligned = grid.lo + Int((Double(hz - grid.lo) / Double(stepHz)).rounded()) * stepHz
        return min(max(aligned, grid.lo), grid.last)
    }

    private func cycleStep() {
        let index = Self.steps.firstIndex(of: stepHz) ?? 1
        stepHz = Self.steps[(index + 1) % Self.steps.count]
        let target = snapped(centerHz)
        if target != centerHz {
            centerHz = target
        }
    }

    private func syncFromFrequency() {
        guard let mhz = FrequencyFormatter.parse(frequency) else {
            let fallback = snapped(FrequencyScopeLogic.defaultHz(band: band, mode: mode) ?? 14_290_000)
            if centerHz != fallback {
                programmatic = true; centerHz = fallback
            }
            return
        }
        if let matched = BandPlanService.bandFor(frequencyMHz: mhz) {
            band = matched
        }
        let hz = snapped(Int((mhz * 1_000_000).rounded()))
        if centerHz != hz {
            programmatic = true
            centerHz = hz
            if expanded {
                requestScroll(to: hz, animated: false)
            }
        }
        if !touched, !userOpened {
            expanded = false
        }
    }

    /// Escape hatch from the determining row: claim the field at the band's
    /// default, commit it to the wizard, and open the scope for tuning.
    private func takeOverManually() {
        touched = true
        userOpened = true
        if let target = FrequencyScopeLogic.defaultHz(band: band, mode: mode) {
            centerHz = snapped(target)
        }
        flushWrite()
        withAnimation(.easeInOut(duration: 0.22)) { expanded = true }
        requestScroll(to: centerHz, animated: false)
    }

    private func centerChanged() {
        if programmatic {
            programmatic = false
            return
        }
        touched = true
        scheduleWrite()
    }

    /// Debounced commit — writes `frequency` a beat after tuning settles.
    private func scheduleWrite() {
        writeTask?.cancel()
        writeTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(140))
            guard !Task.isCancelled else {
                return
            }
            writeFrequency()
        }
    }

    private func flushWrite() {
        writeTask?.cancel()
        writeFrequency()
    }

    private func writeFrequency() {
        let formatted = FrequencyFormatter.format(centerMHz)
        if frequency != formatted {
            frequency = formatted
        }
    }

    private func switchBand(_ option: String) {
        band = option
        touched = true
        if let target = FrequencyScopeLogic.defaultHz(band: option, mode: mode) {
            centerHz = snapped(target)
        }
    }

    private func commitSetText() {
        guard let mhz = FrequencyFormatter.parse(setText) else {
            return
        }
        setText = ""
        touched = true
        stepHz = 100 // exact entry deserves the finest grid
        if let matched = BandPlanService.bandFor(frequencyMHz: mhz) {
            band = matched
        }
        centerHz = snapped(Int((mhz * 1_000_000).rounded()))
    }

    /// Scroll (animated) to the nearest clear, in-plan frequency at the current
    /// step — a glide, not a jump. Uses the precomputed row verdicts.
    private func findClear() {
        guard let range = FrequencyScopeLogic.bandRangeHz(band) else {
            return
        }
        touched = true
        for delta in stride(from: 0, to: range.count, by: stepHz) {
            for candidate in [centerHz - delta, centerHz + delta] where range.contains(candidate) {
                if rowByHz[candidate]?.isGood == true {
                    centerHz = candidate
                    requestScroll(to: candidate, animated: true)
                    return
                }
            }
        }
    }
}

// MARK: - Preview

#Preview {
    struct Harness: View {
        @State private var frequency = "14.290"
        var body: some View {
            Form {
                Section {
                    FrequencyScopeField(
                        frequency: $frequency, mode: "SSB", license: .general,
                        spots: ScopeSpot.sample20m, autoPicked: true, determining: false
                    )
                } header: {
                    Text("Radio")
                }
            }
        }
    }
    return Harness()
}
