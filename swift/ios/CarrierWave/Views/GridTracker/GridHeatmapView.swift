//
//  GridHeatmapView.swift
//  CarrierWave
//
//  Canvas-based Maidenhead grid heatmap showing worked/confirmed grid squares.
//  Renders a rectangular grid of Maidenhead fields and squares with color fill.
//

import CarrierWaveCore
import SwiftUI

// MARK: - GridHeatmapView

/// Interactive Maidenhead grid heatmap.
/// Shows a scrollable grid of 4-character Maidenhead squares colored by worked/confirmed status.
///
/// `Equatable` so callers can wrap with `.equatable()` and skip re-rendering
/// when the underlying summary data hasn't changed. Without this, every
/// parent body re-eval (e.g. typing in a sibling search field) would
/// re-create the Canvas and redraw up to ~32 000 grid cells, which makes
/// the keyboard lag noticeably. The closure parameter is intentionally
/// excluded from `==` — captured `@State` setters remain valid for the
/// lifetime of the view because `@State` is backed by stable storage.
struct GridHeatmapView: View, Equatable {
    // MARK: Internal

    let summary: GridTrackerSummary
    let compact: Bool
    var onGridTapped: ((String) -> Void)?

    var body: some View {
        if compact {
            compactHeatmap
        } else {
            fullHeatmap
        }
    }

    // Maidenhead fields span A–R for longitude (18 fields) and A–R for latitude (18 fields)
    // Each field contains 10×10 squares (0–9 × 0–9)
    // We show only fields that have worked grids, plus neighbors for context

    static func == (lhs: GridHeatmapView, rhs: GridHeatmapView) -> Bool {
        // Cheap, structural fingerprint of the summary. The full
        // `gridData` dictionary is stable for the lifetime of a load —
        // these counts only change when the underlying scan reruns,
        // which we already gate behind `loadData()`. Comparing them is
        // O(1) and good enough to detect "the data actually changed".
        lhs.compact == rhs.compact
            && lhs.summary.totalGridsWorked == rhs.summary.totalGridsWorked
            && lhs.summary.totalGridsConfirmed == rhs.summary.totalGridsConfirmed
            && lhs.summary.totalFields == rhs.summary.totalFields
    }

    // MARK: Private

    @ScaledMetric(relativeTo: .caption) private var cellSize: CGFloat = 14
    @State private var selectedGrid: String?
}

// MARK: - Compact Heatmap (Dashboard Card)

extension GridHeatmapView {
    /// Mini heatmap showing only fields with activity, rendered as small colored cells.
    private var compactHeatmap: some View {
        let fields = relevantFields
        let fieldBounds = computeFieldBounds(fields)

        return Canvas { context, size in
            let cols = fieldBounds.colRange.count
            let rows = fieldBounds.rowRange.count
            guard cols > 0, rows > 0 else {
                return
            }

            let cw = min(size.width / CGFloat(cols), size.height / CGFloat(rows))
            let actualWidth = CGFloat(cols) * cw
            let actualHeight = CGFloat(rows) * cw
            let xOffset = (size.width - actualWidth) / 2
            let yOffset = (size.height - actualHeight) / 2

            for (colIdx, lonField) in fieldBounds.colRange.enumerated() {
                for (rowIdx, latField) in fieldBounds.rowRange.reversed().enumerated() {
                    let field = fieldString(lon: lonField, lat: latField)
                    let rect = CGRect(
                        x: xOffset + CGFloat(colIdx) * cw,
                        y: yOffset + CGFloat(rowIdx) * cw,
                        width: cw - 1,
                        height: cw - 1
                    )

                    let gridCount = summary.fieldCounts[field] ?? 0
                    let color = fieldColor(gridCount: gridCount)
                    let path = Path(roundedRect: rect, cornerRadius: 2)
                    context.fill(path, with: .color(color))
                }
            }
        }
        .frame(height: 80)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "Grid heatmap: \(summary.totalGridsWorked) grids across \(summary.totalFields) fields"
        )
    }
}

// MARK: - Full Heatmap (Detail View)

extension GridHeatmapView {
    /// Full interactive heatmap showing individual grid squares within fields.
    private var fullHeatmap: some View {
        let fields = relevantFields
        let fieldBounds = computeFieldBounds(fields)

        return VStack(alignment: .leading, spacing: 8) {
            ScrollView([.horizontal, .vertical], showsIndicators: true) {
                fullHeatmapCanvas(fieldBounds: fieldBounds)
            }

            heatmapLegend
        }
    }

    private func fullHeatmapCanvas(fieldBounds: FieldBounds) -> some View {
        let cols = fieldBounds.colRange.count * 10
        let rows = fieldBounds.rowRange.count * 10
        let cw = cellSize
        let width = CGFloat(cols) * (cw + 1) + CGFloat(fieldBounds.colRange.count - 1) * 2
        let height = CGFloat(rows) * (cw + 1) + CGFloat(fieldBounds.rowRange.count - 1) * 2

        return Canvas { context, _ in
            for (fieldColIdx, lonField) in fieldBounds.colRange.enumerated() {
                for (fieldRowIdx, latField) in fieldBounds.rowRange.reversed().enumerated() {
                    drawFieldSquares(
                        context: &context,
                        lonField: lonField,
                        latField: latField,
                        fieldPosition: (col: fieldColIdx, row: fieldRowIdx),
                        cellWidth: cw
                    )
                }
            }
        }
        .frame(width: max(width, 100), height: max(height, 100))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Detailed grid square heatmap")
    }

    private func drawFieldSquares(
        context: inout GraphicsContext,
        lonField: Int,
        latField: Int,
        fieldPosition: (col: Int, row: Int),
        cellWidth: CGFloat
    ) {
        let fieldSpacing: CGFloat = 2
        let cellSpacing: CGFloat = 1

        for lonSquare in 0 ..< 10 {
            for latSquare in 0 ..< 10 {
                let gridKey = gridString(
                    lonField: lonField, latField: latField,
                    lonSquare: lonSquare, latSquare: latSquare
                )

                let xPos = CGFloat(fieldPosition.col) * (10 * (cellWidth + cellSpacing) + fieldSpacing)
                    + CGFloat(lonSquare) * (cellWidth + cellSpacing)
                let yPos = CGFloat(fieldPosition.row) * (10 * (cellWidth + cellSpacing) + fieldSpacing)
                    + CGFloat(9 - latSquare) * (cellWidth + cellSpacing)

                let rect = CGRect(x: xPos, y: yPos, width: cellWidth, height: cellWidth)
                let color = gridColor(for: gridKey)
                let path = Path(roundedRect: rect, cornerRadius: 1)
                context.fill(path, with: .color(color))
            }
        }
    }

    private var heatmapLegend: some View {
        HStack(spacing: 12) {
            legendItem(color: Color(.systemGray5), label: "Not worked")
            legendItem(color: Color.blue.opacity(0.5), label: "Worked")
            legendItem(color: Color.green.opacity(0.6), label: "Confirmed")
        }
    }

    private func legendItem(color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2)
                .fill(color)
                .frame(width: 10, height: 10)
                .accessibilityHidden(true)
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Grid Helpers

extension GridHeatmapView {
    /// Fields that contain at least one worked grid.
    private var relevantFields: Set<String> {
        Set(summary.fieldCounts.keys)
    }

    private func computeFieldBounds(_ fields: Set<String>) -> FieldBounds {
        guard !fields.isEmpty else {
            return FieldBounds(colRange: [], rowRange: [])
        }

        var minLon = 17, maxLon = 0, minLat = 17, maxLat = 0
        for field in fields {
            let chars = Array(field.uppercased())
            guard chars.count >= 2,
                  let lon = chars[0].asciiValue.map({ Int($0) - 65 }),
                  let lat = chars[1].asciiValue.map({ Int($0) - 65 })
            else {
                continue
            }
            minLon = min(minLon, lon)
            maxLon = max(maxLon, lon)
            minLat = min(minLat, lat)
            maxLat = max(maxLat, lat)
        }

        // Add 1 cell of padding around the edges
        let padLon = max(minLon - 1, 0) ... min(maxLon + 1, 17)
        let padLat = max(minLat - 1, 0) ... min(maxLat + 1, 17)

        return FieldBounds(colRange: Array(padLon), rowRange: Array(padLat))
    }

    private func fieldString(lon: Int, lat: Int) -> String {
        let lonChar = Character(UnicodeScalar(65 + lon)!)
        let latChar = Character(UnicodeScalar(65 + lat)!)
        return String([lonChar, latChar])
    }

    private func gridString(
        lonField: Int, latField: Int, lonSquare: Int, latSquare: Int
    ) -> String {
        let f1 = Character(UnicodeScalar(65 + lonField)!)
        let f2 = Character(UnicodeScalar(65 + latField)!)
        return "\(f1)\(f2)\(lonSquare)\(latSquare)"
    }

    private func fieldColor(gridCount: Int) -> Color {
        if gridCount == 0 {
            return Color(.systemGray5)
        }
        let intensity = min(Double(gridCount) / 10.0, 1.0)
        return Color.green.opacity(0.3 + intensity * 0.7)
    }

    private func gridColor(for gridKey: String) -> Color {
        guard let data = summary.gridData[gridKey] else {
            return Color(.systemGray5)
        }
        switch data.status {
        case .notWorked:
            return Color(.systemGray5)
        case .worked:
            let intensity = min(Double(data.qsoCount) / 5.0, 1.0)
            return Color.blue.opacity(0.3 + intensity * 0.4)
        case .confirmed:
            let intensity = min(Double(data.qsoCount) / 5.0, 1.0)
            return Color.green.opacity(0.3 + intensity * 0.5)
        }
    }
}

// MARK: - FieldBounds

/// Computed bounds for the visible field range.
private struct FieldBounds {
    let colRange: [Int] // longitude field indices
    let rowRange: [Int] // latitude field indices
}
