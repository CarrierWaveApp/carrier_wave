import CarrierWaveCore
import CoreGraphics
import Foundation
import UIKit
import Vision

// MARK: - ScannedQSORow

/// A single row from a scanned log page, with parse results and confidence.
struct ScannedQSORow: Identifiable {
    let id = UUID()
    /// Raw OCR text for this row
    let rawText: String
    /// Parsed QSO result from QuickEntryParser (nil if parsing failed)
    var parseResult: QuickEntryResult?
    /// Extracted timestamp (nil if no date/time found)
    var timestamp: Date?
    /// Date components extracted from this row (for inheritance to next rows)
    var dateComponents: DateComponents?
    /// Minimum OCR confidence across blocks in this row
    let minConfidence: Float
    /// Average OCR confidence across blocks in this row
    let averageConfidence: Float
    /// Cropped image of this row from the scanned page
    let rowImage: UIImage?
    /// Whether the user has selected this row for import
    var isSelected: Bool = true

    var confidence: RowConfidence {
        guard let result = parseResult else {
            return .failed
        }
        if result.callsign.isEmpty {
            return .low
        }
        if minConfidence < 0.7 || result.notes != nil {
            return .low
        }
        return .high
    }
}

// MARK: - RowConfidence

enum RowConfidence {
    case high
    case low
    case failed
}

// MARK: - LogPageScanner

/// Orchestrates the full scan pipeline: image → OCR → row grouping → timestamp
/// extraction → quick entry parsing.
enum LogPageScanner {
    // MARK: Internal

    /// Process a single page image into scanned QSO rows.
    /// - Parameters:
    ///   - image: The page image to scan
    ///   - rstOrder: RST ordering preference
    ///   - defaultDate: User-provided fallback date
    ///   - previousDateComponents: Date inherited from previous page's last row
    /// - Returns: Array of scanned rows with parse results
    static func scanPage(
        image: CGImage,
        rstOrder: RSTOrder,
        defaultDate: Date?,
        previousDateComponents: DateComponents? = nil
    ) async throws -> [ScannedQSORow] {
        let observations = try await performOCR(on: image)
        let textRows = TextRowGrouper.groupIntoRows(observations)

        var rows: [ScannedQSORow] = []
        var lastDateComponents = previousDateComponents

        for textRow in textRows {
            let extraction = TimestampExtractor.extract(from: textRow.text)
            let effectiveDateComponents = extraction.date ?? lastDateComponents

            if extraction.date != nil {
                lastDateComponents = extraction.date
            }

            let timestamp = TimestampExtractor.buildDate(
                date: extraction.date,
                time: extraction.time,
                fallbackDate: lastDateComponents,
                defaultDate: defaultDate
            )

            var parseResult = QuickEntryParser.parse(
                extraction.remainingText,
                rstOrder: rstOrder
            )

            // QuickEntryParser requires callsign + at least one other token.
            // For scanned rows that fail full parsing, classify tokens individually
            // so recognized fields (RST, freq, mode) are still captured. Anything
            // unrecognized goes into notes for the user to fix via the edit sheet.
            if parseResult == nil, !extraction.remainingText.isEmpty {
                parseResult = buildPartialResult(
                    from: extraction.remainingText,
                    rstOrder: rstOrder
                )
            }

            let rowImage = cropRow(from: image, boundingBox: textRow.boundingBox)

            let row = ScannedQSORow(
                rawText: textRow.text,
                parseResult: parseResult,
                timestamp: timestamp,
                dateComponents: effectiveDateComponents,
                minConfidence: textRow.minConfidence,
                averageConfidence: textRow.averageConfidence,
                rowImage: rowImage
            )
            rows.append(row)
        }

        return rows
    }

    /// Process multiple page images sequentially, carrying date context across pages.
    static func scanPages(
        images: [CGImage],
        rstOrder: RSTOrder,
        defaultDate: Date?
    ) async throws -> [ScannedQSORow] {
        var allRows: [ScannedQSORow] = []
        var lastDateComponents: DateComponents?

        for image in images {
            let pageRows = try await scanPage(
                image: image,
                rstOrder: rstOrder,
                defaultDate: defaultDate,
                previousDateComponents: lastDateComponents
            )
            if let lastRow = pageRows.last {
                lastDateComponents = lastRow.dateComponents
            }
            allRows.append(contentsOf: pageRows)
        }

        return allRows
    }

    // MARK: Private

    private struct ClassifiedTokens {
        var callsign: String?
        var frequency: Double?
        var band: String?
        var mode: String?
        var rstValues: [String] = []
        var state: String?
        var park: String?
        var grid: String?
        var zuluTime: ZuluTime?
        var unrecognized: [String] = []
    }

    /// Vocabulary hints for Vision OCR to bias recognition toward amateur radio terms.
    /// These don't force results but help disambiguate when confidence is borderline.
    nonisolated private static let ocrCustomWords: [String] = [
        // Common modes
        "SSB", "USB", "LSB", "CW", "FM", "AM", "FT8", "FT4", "RTTY", "PSK31",
        "DIGI", "DATA", "JS8", "SSTV", "VARA", "WINLINK",
        // Common log column headers
        "RST", "FREQ", "BAND", "MODE", "CALL", "DATE", "TIME", "UTC", "GMT",
        // Signal reports
        "599", "59", "579", "57", "339", "559",
        // Park references
        "POTA", "SOTA", "WWFF",
    ]

    /// Assign RST values based on order preference.
    private static func assignRSTs(
        _ values: [String],
        order: RSTOrder
    ) -> (sent: String?, received: String?) {
        guard !values.isEmpty else {
            return (nil, nil)
        }
        if values.count >= 2 {
            switch order {
            case .receivedFirst: return (values[1], values[0])
            case .sentFirst: return (values[0], values[1])
            }
        }
        switch order {
        case .receivedFirst: return (nil, values[0])
        case .sentFirst: return (values[0], nil)
        }
    }

    /// Classify tokens individually when QuickEntryParser fails (no valid callsign
    /// found or only one token). Recognized fields are placed into the result;
    /// everything else becomes notes so the user can correct via the edit sheet.
    private static func buildPartialResult(
        from text: String,
        rstOrder: RSTOrder
    ) -> QuickEntryResult {
        let classified = classifyTokens(text)
        let rsts = assignRSTs(classified.rstValues, order: rstOrder)
        let notes = classified.unrecognized.isEmpty
            ? nil : classified.unrecognized.joined(separator: " ")

        return QuickEntryResult(
            callsign: classified.callsign ?? "",
            rstSent: rsts.sent,
            rstReceived: rsts.received,
            state: classified.state,
            theirPark: classified.park,
            theirGrid: classified.grid,
            frequency: classified.frequency,
            band: classified.band,
            mode: classified.mode,
            notes: notes,
            zuluTime: classified.zuluTime
        )
    }

    private static func classifyTokens(_ text: String) -> ClassifiedTokens {
        let parser = CarrierWaveCore.QuickEntryParser.self
        let tokens = text.uppercased()
            .split(separator: " ", omittingEmptySubsequences: true)
            .map(String.init)

        var result = ClassifiedTokens()
        for token in tokens {
            if parser.isZuluTime(token) {
                result.zuluTime = parser.parseZuluTime(token)
            } else if result.callsign == nil, parser.isCallsign(token) {
                result.callsign = token
            } else if parser.isRST(token) {
                result.rstValues.append(parser.stripRSTSuffix(token).value)
            } else if let freq = FrequencyFormatter.parse(token) {
                result.frequency = freq
                result.band = BandUtilities.deriveBand(from: freq * 1_000)
            } else if parser.isMode(token) {
                result.mode = token
            } else if parser.isParkReference(token) {
                result.park = token
            } else if parser.isGridSquare(token) {
                result.grid = token
            } else if parser.isStateOrRegion(token) {
                result.state = token
            } else {
                result.unrecognized.append(token)
            }
        }
        return result
    }

    /// Crop a row region from the page image using Vision's normalized bounding box.
    /// Adds vertical padding so handwriting ascenders/descenders aren't clipped.
    private static func cropRow(from image: CGImage, boundingBox: CGRect) -> UIImage? {
        let imgWidth = CGFloat(image.width)
        let imgHeight = CGFloat(image.height)
        let padding = imgHeight * 0.01

        // Vision: origin at bottom-left, y increases upward
        // CGImage: origin at top-left, y increases downward
        let pixelX = boundingBox.minX * imgWidth
        let pixelY = (1 - boundingBox.maxY) * imgHeight - padding
        let pixelW = boundingBox.width * imgWidth
        let pixelH = boundingBox.height * imgHeight + padding * 2

        let cropRect = CGRect(x: pixelX, y: pixelY, width: pixelW, height: pixelH)
            .intersection(CGRect(x: 0, y: 0, width: imgWidth, height: imgHeight))

        guard !cropRect.isEmpty, let cropped = image.cropping(to: cropRect) else {
            return nil
        }
        return UIImage(cgImage: cropped)
    }

    nonisolated private static func performOCR(
        on image: CGImage
    ) async throws -> [VNRecognizedTextObservation] {
        try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { @Sendable request, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                nonisolated(unsafe) let observations =
                    request.results as? [VNRecognizedTextObservation] ?? []
                continuation.resume(returning: observations)
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = false
            request.customWords = Self.ocrCustomWords

            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}
